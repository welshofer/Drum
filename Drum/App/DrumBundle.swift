import AppKit
import CoreText
import SwiftUI

/// Where the compiled shaders and bundled fonts live.
///
/// In the Xcode build (the real product) `default.metallib` and `Fonts/` are in
/// the main bundle and `ATSApplicationFontsPath` registers the fonts. Under
/// `swift build` — the guard-permitted compile-and-run check — SwiftPM puts
/// both in `Bundle.module`, so the `SWIFT_PACKAGE` branches point there and
/// register the fonts by hand. Nothing here runs in the Xcode product.
enum DrumBundle {
    static var shaders: ShaderLibrary {
        #if SWIFT_PACKAGE
        ShaderLibrary.bundle(.module)
        #else
        ShaderLibrary.default
        #endif
    }

    @MainActor
    static func prepareForLaunch() {
        #if SWIFT_PACKAGE
        NSApp.setActivationPolicy(.regular)
        guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        let fonts = files.filter { $0.pathExtension.lowercased() == "ttf" }
        if !fonts.isEmpty {
            CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
        }
        #endif
    }

    /// Dev harness (SwiftPM builds only): with `DRUM_SNAPSHOT_DIR` set, the app
    /// dumps its NSView and Core Animation layer trees a few seconds after
    /// launch, again after resizing to the ribbon aspect, then quits.
    /// `DRUM_CRT_OFF=1` disables the shader chain for that run. Used to answer
    /// the §5 question (does SwiftUI host the SwiftTerm view under a layer
    /// effect?) without screen-recording permission.
    @MainActor
    static func armSnapshots(state: AppState) {
        #if SWIFT_PACKAGE
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["DRUM_SNAPSHOT_DIR"] else { return }
        let crtWasEnabled = state.crt.enabled
        if env["DRUM_CRT_OFF"] == "1" {
            state.crt.enabled = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                NSApp.terminate(nil)
                return
            }
            WindowSnapshot.write(window, note: Self.stateNote(state), to: "\(dir)/snapshot-1")
            window.setContentSize(NSSize(width: 1400, height: 394))
            try? await Task.sleep(for: .seconds(2))
            WindowSnapshot.write(window, note: Self.stateNote(state), to: "\(dir)/snapshot-2")
            state.crt.enabled = crtWasEnabled
            NSApp.terminate(nil)
        }
        #endif
    }

    #if SWIFT_PACKAGE
    @MainActor
    private static func stateNote(_ state: AppState) -> String {
        let view = state.terminal.view
        let mirror = state.terminal.mirror.image.map { "\($0.width)x\($0.height)" } ?? "nil"
        return "poweredOn=\(state.isPoweredOn) crtEnabled=\(state.crt.enabled) shellRunning=\(state.terminal.isRunning)"
            + " terminalSuperview=\(view.superview.map { String(describing: type(of: $0)) } ?? "nil")"
            + " terminalInWindow=\(view.window != nil) terminalFrame=\(view.frame.integral) mirror=\(mirror)"
    }
    #endif
}

#if SWIFT_PACKAGE
enum WindowSnapshot {
    @MainActor
    static func write(_ window: NSWindow, note: String, to base: String) {
        guard let content = window.contentView else { return }
        var text = "window frame=\(window.frame.integral) backingScale=\(window.backingScaleFactor)\n"
        text += note + "\n"
        text += "firstResponder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")\n\n"
        text += "VIEWS\n"
        dumpViews(content, depth: 0, into: &text)
        text += "\nLAYERS\n"
        if let layer = content.layer {
            dumpLayers(layer, depth: 0, into: &text)
        } else {
            text += "content view has no layer\n"
        }
        try? text.write(toFile: base + ".txt", atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func dumpViews(_ view: NSView, depth: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: depth)
        out += "\(pad)\(type(of: view)) frame=\(view.frame.integral) hidden=\(view.isHidden)"
        out += " alpha=\(view.alphaValue) inWindow=\(view.window != nil)\n"
        for sub in view.subviews {
            dumpViews(sub, depth: depth + 1, into: &out)
        }
    }

    @MainActor
    private static func dumpLayers(_ layer: CALayer, depth: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: depth)
        let filters = layer.filters?.count ?? 0
        let delegate = layer.delegate.map { String(describing: type(of: $0)) } ?? "-"
        out += "\(pad)\(type(of: layer)) filters=\(filters) delegate=\(delegate)"
        out += " frame=\(layer.frame.integral) hidden=\(layer.isHidden) opacity=\(layer.opacity)\n"
        for sublayer in layer.sublayers ?? [] {
            dumpLayers(sublayer, depth: depth + 1, into: &out)
        }
    }
}
#endif
