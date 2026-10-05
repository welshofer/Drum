# CRT pointer mapping — 2026-10-05

The AppKit terminal converts window mouse points through the same output-to-source barrel map as the picture. Both receive the current TimelineView settings and timestamp. Native mode bypasses the map; live resize uses the same motion policy as rendering. View-to-view and rectangle conversions retain AppKit semantics, including IME candidate geometry.

Actual NSWindow-dispatched events compare curved and native word selection, drag selection, OSC 8 activation, and TUI press/drag/release/motion reports at 640, 1280 and 2560×720 point fixtures with curvature 0.02 and 0.15. Debug and Release pass.

The previous `fract(sin()*43758.5453)` noise produced a measured CPU/Metal disagreement of 5.1000214 points at maximum wobble. The coordinated shader and pointer implementation now share an integer hash of the scanline and wrapped frame time. The smooth sync sine and configured amplitude remain. A regression executes the literal Metal barrel function, comparing four horizontal positions across every scanline at three sizes and four times, with curvature 0.15 and wobble 0.01. The maximum measured disagreement is 0.000732421875 points in both configurations, below the 0.002-point test limit.

These are geometry and shader-computation checks. The physical 2560×720 ribbon display is not attached, and a compositor presentation timestamp has not been measured. A stale picture during severe rendering stalls can still differ from the latest scheduled TimelineView state; the presentation gate remains open.
