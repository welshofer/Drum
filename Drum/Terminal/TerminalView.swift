import AppKit
import SwiftUI

/// `NSViewRepresentable` around the session's `LocalProcessTerminalView`.
///
/// It never creates the terminal; it parents the session's long-lived view
/// inside a host view SwiftUI owns, and re-parents it if SwiftUI rebuilt the
/// host. The theme is re-applied only for the parts that actually changed.
///
/// With CRT enabled the host is invisible and the mirror supplies the picture.
/// With CRT disabled the same host draws directly, without bitmap capture.
/// It always stays outside the shader chain and keeps input, selection and PTY
/// state intact when the rendering mode changes.
struct TerminalView: NSViewRepresentable {
    let session: TerminalSession
    let theme: TerminalTheme
    let crtEnabled: Bool

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.setCRTEnabled(crtEnabled, session: session)
        host.attach(session.view)
        theme.apply(to: session.view, previous: session.appliedTheme)
        session.appliedTheme = theme
        return host
    }

    func updateNSView(_ host: TerminalHostView, context: Context) {
        host.setCRTEnabled(crtEnabled, session: session)
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

    func setCRTEnabled(_ enabled: Bool, session: TerminalSession) {
        session.setCRTEnabled(enabled)
        let alpha: CGFloat = enabled ? 0 : 1
        if alphaValue != alpha {
            alphaValue = alpha
            session.view.needsDisplay = true
        }
    }

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

}
