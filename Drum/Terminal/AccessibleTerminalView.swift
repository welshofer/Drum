import AppKit
import SwiftTerm

/// One native text surface for input and output, independent of CRT opacity.
/// The picture remains decorative; this view exposes scrollback and selection.
class AccessibleTerminalView: LocalProcessTerminalView {
    private var snapshot: TerminalAccessibilitySnapshot {
        TerminalAccessibilitySnapshot(terminal: getTerminal(), selection: selection)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func isAccessibilityHidden() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { "Terminal" }
    override func accessibilityValue() -> Any? { snapshot.text as String }
    override func accessibilityNumberOfCharacters() -> Int { snapshot.text.length }
    override func accessibilitySelectedTextRange() -> NSRange { snapshot.selectedRange }
    override func accessibilitySelectedTextRanges() -> [NSValue]? {
        [NSValue(range: snapshot.selectedRange)]
    }
    override func accessibilitySelectedText() -> String? {
        let value = snapshot
        return value.string(for: value.selectedRange)
    }
    override func accessibilityVisibleCharacterRange() -> NSRange { snapshot.visibleRange }
    override func accessibilityInsertionPointLineNumber() -> Int { snapshot.caretLine }
    override func accessibilityString(for range: NSRange) -> String? { snapshot.string(for: range) }
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        snapshot.string(for: range).map { NSAttributedString(string: $0) }
    }
    override func accessibilityRange(forLine line: Int) -> NSRange {
        let value = snapshot
        return value.lines.indices.contains(line) ? value.lines[line] : NSRange(location: NSNotFound, length: 0)
    }
    override func accessibilityLine(for index: Int) -> Int {
        let value = snapshot
        guard index >= 0, index <= value.text.length else { return NSNotFound }
        return value.lines.lastIndex { $0.location <= index } ?? 0
    }
    override func accessibilityRange(for index: Int) -> NSRange {
        let value = snapshot
        guard index >= 0, index < value.text.length else {
            return NSRange(location: index == value.text.length ? index : NSNotFound, length: 0)
        }
        return value.text.rangeOfComposedCharacterSequence(at: index)
    }
    override func isAccessibilityFocused() -> Bool { window?.firstResponder === self }
    override func setAccessibilityFocused(_ focused: Bool) {
        if focused { window?.makeFirstResponder(self) }
    }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(setAccessibilityValue(_:)) ||
            selector == #selector(setAccessibilitySelectedText(_:)) ||
            selector == #selector(setAccessibilitySelectedTextRange(_:)) ||
            selector == #selector(setAccessibilitySelectedTextRanges(_:)) {
            return false
        }
        return super.isAccessibilitySelectorAllowed(selector)
    }

    override func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        NSAccessibility.post(element: self, notification: .valueChanged)
        NSAccessibility.post(element: self, notification: .selectedTextChanged)
    }
    override func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        NSAccessibility.post(element: self, notification: .selectedTextChanged)
    }
}
