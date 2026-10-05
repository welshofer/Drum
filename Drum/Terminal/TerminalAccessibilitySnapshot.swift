import Foundation
import SwiftTerm

/// UTF-16 text coordinates derived from SwiftTerm's public buffer API.
/// Wide-cell padding is omitted; combined characters use SwiftTerm's decoder.
struct TerminalAccessibilitySnapshot {
    let text: NSString
    let lines: [NSRange]
    let selectedRange: NSRange
    let visibleRange: NSRange
    let caretLine: Int

    @MainActor init(terminal: Terminal, selection: SelectionService) {
        var value = ""
        var length = 0
        var ranges: [NSRange] = []
        var bufferLines: [BufferLine] = []
        var row = 0
        while let line = terminal.bufferLine(atRow: row) {
            bufferLines.append(line)
            row += 1
        }
        let activeCaretLine = min(max(0, bufferLines.count - terminal.rows + terminal.buffer.y),
                                  max(0, bufferLines.count - 1))
        for (row, line) in bufferLines.enumerated() {
            if row > 0, !line.isWrapped { value.append("\n"); length += 1 }
            var lineText = line.translateToString(trimRight: true, skipNullCellsFollowingWide: true,
                                                  characterProvider: { terminal.getCharacter(for: $0) })
                .replacingOccurrences(of: "\u{0}", with: " ")
            if row == activeCaretLine {
                // Cursor movement can leave the insertion point beyond text.
                // Include its blank-cell prefix before calculating ANY row offset.
                let prefix = line.translateToString(trimRight: false,
                    endCol: min(max(terminal.buffer.x, 0), terminal.cols), skipNullCellsFollowingWide: true,
                    characterProvider: { terminal.getCharacter(for: $0) })
                    .replacingOccurrences(of: "\u{0}", with: " ")
                if prefix.utf16.count > lineText.utf16.count { lineText = prefix }
            }
            ranges.append(NSRange(location: length, length: lineText.utf16.count))
            value += lineText
            length += lineText.utf16.count
        }
        text = value as NSString
        lines = ranges
        func offset(_ position: Position) -> Int {
            guard !ranges.isEmpty else { return 0 }
            let row = min(max(position.row, 0), ranges.count - 1)
            guard let line = terminal.bufferLine(atRow: row) else { return ranges[row].location }
            let prefix = line.translateToString(trimRight: false, endCol: min(max(position.col, 0), terminal.cols),
                                                skipNullCellsFollowingWide: true,
                                                characterProvider: { terminal.getCharacter(for: $0) })
            return ranges[row].location + min(prefix.utf16.count, ranges[row].length)
        }
        caretLine = activeCaretLine
        if selection.active {
            let first = offset(selection.start)
            let last = offset(selection.end)
            selectedRange = NSRange(location: min(first, last), length: abs(last - first))
        } else {
            selectedRange = NSRange(location: offset(Position(col: terminal.buffer.x, row: caretLine)), length: 0)
        }
        if ranges.isEmpty {
            visibleRange = NSRange(location: 0, length: 0)
        } else {
            let first = min(max(terminal.buffer.yDisp, 0), ranges.count - 1)
            let last = min(first + terminal.rows - 1, ranges.count - 1)
            visibleRange = NSRange(location: ranges[first].location,
                                   length: NSMaxRange(ranges[last]) - ranges[first].location)
        }
    }

    func string(for range: NSRange) -> String? {
        guard range.location >= 0, range.length >= 0, range.location <= text.length,
              range.length <= text.length - range.location else { return nil }
        return text.substring(with: range)
    }
}
