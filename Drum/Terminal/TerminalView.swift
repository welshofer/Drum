import AppKit
import SwiftUI

/// `NSViewRepresentable` around the session's `LocalProcessTerminalView`.
///
/// It never creates the terminal; it parents the session's long-lived view
/// inside a host view SwiftUI owns, and re-parents it if SwiftUI rebuilt the
/// host. The theme is re-applied only for the parts that actually changed.
///
/// The host is invisible (`alphaValue = 0`): what you see is `TerminalMirror`'s
/// image drawn through the CRT chain. This view exists for input — it is the
/// window's first responder, so keys, copy/paste, and mouse selection work —
/// and must sit outside the shader chain, which cannot host AppKit views.
struct TerminalView: NSViewRepresentable {
    let session: TerminalSession
    let theme: TerminalTheme

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.attach(session.view)
        theme.apply(to: session.view, previous: session.appliedTheme)
        session.appliedTheme = theme
        return host
    }

    func updateNSView(_ host: TerminalHostView, context: Context) {
        host.attach(session.view)
        if session.appliedTheme != theme {
            theme.apply(to: session.view, previous: session.appliedTheme)
            session.appliedTheme = theme
            session.mirror.markDirty()
        }
    }
}

/// Plain container so the terminal NSView can move between hosts intact.
final class TerminalHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func attach(_ terminal: NSView) {
        guard terminal.superview !== self else { return }
        terminal.removeFromSuperview()
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
        if let window, terminal.window === window {
            window.makeFirstResponder(terminal)
        }
    }

    override func layout() {
        super.layout()
        for view in subviews {
            view.frame = bounds
        }
    }
}
