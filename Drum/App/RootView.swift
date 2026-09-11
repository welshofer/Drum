import SwiftUI

/// Black window → (power transition) → the CRT stage.
struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            Color.black
            if state.isPoweredOn {
                CRTStage()
                    .transition(PowerOnTransition.asymmetric(tint: state.crt.phosphor.swiftUIColor))
            }
        }
        .background(Color.black)
        .navigationTitle(state.terminal.title)
        .task { state.powerOn() }
    }
}

/// Two layers with the same geometry: the picture (mirror image + glow) under
/// the CRT chain, and above it the real, invisible terminal view for input.
/// The chain is applied exactly once, here. The input view is outside it
/// because SwiftUI's shader modifiers cannot host AppKit views (Phase 1 finding).
struct CRTStage: View {
    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale

    /// The persisted settings with the live backing scale: scanline period is
    /// in device pixels, and the window can move between 1× and 2× displays.
    private var settings: CRTSettings {
        var s = state.crt
        s.scale = Float(displayScale)
        return s
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !state.crt.animated)) { context in
                PictureStage()
                    .crt(settings, time: context.date.timeIntervalSinceReferenceDate)
            }
            InputStage()
        }
    }

    /// Breathing room inside the bezel so the barrel and vignette never eat the
    /// first column or the last row. Shared by both stages so they line up.
    static let inset = EdgeInsets(top: 22, leading: 28, bottom: 18, trailing: 28)
}

/// What the tube shows: the mirrored terminal bitmap plus the new-text glow.
///
/// The image is drawn at its natural point size but never *proposes* that size
/// upward: the stage always fills whatever the window gives it. Otherwise the
/// window would grow to fit the picture, the terminal would grow with the
/// window, and the next capture would be bigger still.
struct PictureStage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let mirror = state.terminal.mirror
        Color.black
            .overlay(alignment: .topLeading) {
                if let image = mirror.image {
                    Image(decorative: image, scale: mirror.scale)
                        .overlay(alignment: .topLeading) {
                            CaretOverlay(caret: mirror.caret, phosphor: state.crt.phosphor)
                        }
                        .overlay { GlowOverlay(session: state.terminal, phosphor: state.crt.phosphor) }
                        .padding(CRTStage.inset)
                }
            }
            .clipped()
    }
}

/// The real terminal, laid out exactly over the picture, invisible, focused.
struct InputStage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TerminalView(session: state.terminal, theme: TerminalTheme(state: state))
            .padding(CRTStage.inset)
    }
}
