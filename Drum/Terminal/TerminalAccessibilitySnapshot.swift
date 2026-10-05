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
        var row = 0
        while let line = terminal.bufferLine(atRow: row) {
            if row > 0, !line.isWrapped { value.append("\n"); length += 1 }
            let lineText = line.translateToString(trimRight: true, skipNullCellsFollowingWide: true,
                                                  characterProvider: { terminal.getCharacter(for: $0) })
                .replacingOccurrences(of: "\u{0}", with: " ")
            ranges.append(NSRange(location: length, length: lineText.utf16.count))
            value += lineText
            length += lineText.utf16.count
            row += 1
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
        caretLine = min(max(0, ranges.count - terminal.rows + terminal.buffer.y), max(0, ranges.count - 1))
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
