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
/// the CRT chain, and above it the real terminal for input and CRT-off display.
/// The chain is applied exactly once, here. The input view is outside it
/// because SwiftUI's shader modifiers cannot host AppKit views (Phase 1 finding).
struct CRTStage: View {
    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale

    /// The persisted settings with the live backing scale: scanline period is
    /// in device pixels, and the window can move between 1× and 2× displays.
    private var settings: CRTSettings {
        state.crt.forRendering(scale: Float(displayScale),
                               liveResize: state.terminal.mirror.isLiveResizing)
    }

    var body: some View {
        ZStack {
            if state.crt.enabled {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !needsAnimation)) { context in
                    PictureStage(date: context.date)
                        .crt(settings, time: settings.isWobbling ? context.date.timeIntervalSinceReferenceDate : 0,
                             liveResize: state.terminal.mirror.isLiveResizing)
                }
            }
            InputStage()
        }
    }

    private var needsAnimation: Bool {
        state.terminal.mirror.isVisible && !state.terminal.mirror.isLiveResizing &&
            (settings.isWobbling || !state.terminal.flashes.isEmpty)
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
    let date: Date
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
                        .overlay {
                            if !mirror.isLiveResizing {
                                GlowOverlay(session: state.terminal, date: date)
                            }
                        }
                        .padding(CRTStage.inset)
                }
            }
            .clipped()
    }
}

/// The same terminal stays mounted and focused in both rendering modes.
struct InputStage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TerminalView(session: state.terminal, theme: TerminalTheme(state: state), crtEnabled: state.crt.enabled)
            .padding(CRTStage.inset)
    }
}
