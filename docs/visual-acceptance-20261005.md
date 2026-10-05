# Visual reference preparation — 2026-10-05

ATTR-1 is partially prepared. `scripts/terminal-demo.sh` provides fixed normal text, a full-width ruler, box drawing, a selection target and left/right edge columns. Its bytes repeat for the same column/row arguments. Run it inside a disposable Drum shell:

```sh
scripts/terminal-demo.sh
# Explicit deterministic dimensions for an output fixture:
scripts/terminal-demo.sh 80 24
```

After the command returns, drag across `SELECT THIS TEXT` on row 6 to create a **real native selection**. Inverse-colour terminal output would not demonstrate the selection path. The shell prompt may overwrite row 10; move the cursor or rerun the fixture before capturing. Do not capture unrelated terminal history or credentials.

The machine used for this run has no physical 2560×720 ribbon panel. A 2560×720 backing bitmap on a 6016×3384 display is not panel acceptance. No acceptance screenshot has been produced, no style values have been retuned, and the specification §8 visual gate remains open.

## Capture and comparison checklist

Use the real target panel with Drum's ordinary window maximised, at the panel's native resolution. Record app commit, macOS/build, panel model, physical mode and refresh rate, window content points, backing pixels and display scale. Record font/size, phosphor, CRT values, Reduce Motion and wobble state alongside each PNG. A single static PNG does not establish sustained performance or input latency.

1. Use an isolated settings suite or record the current settings for restoration. Capture the existing `CRTSettings()` defaults and existing `CRTSettings.ribbon` values separately, without aesthetic retuning. The preset values are defined in `Drum/CRT/CRTSettings.swift`; ribbon tuning has no new user-facing selector in this change.
2. Run the same demo and make the same row-6 selection in both captures. Use a macOS window screenshot of the running app, including its displayed Metal effects. `NSView.cacheDisplay` captures the pre-effect terminal and cannot close this gate.
3. Retain the actual PNGs as `docs/visual-default-2560x720.png` and `docs/visual-ribbon-2560x720.png`, with the metadata and observed results in a dated acceptance record. These are expected future paths, not files created in this run.
4. Inspect normal-text strokes, counters, box junctions and both edge columns at native scale. Record readability and the bloom/scanline/grille/bezel appearance for each preset, including any clipping or excessive glow.
5. Check real selection start/end at centre and edges, click the intended word with curvature/wobble enabled, compare cursor glyph/blink phases, and test resize plus CRT on/off without losing the PTY, focus or selection. Record actual input-method candidate popup alignment separately.
6. Record the Cathode-inspired visual judgment and decide whether any tuning change is warranted. Keep presentation/FPS acceptance separate and use the measured-present workflow in `docs/performance-presentation-20261005.md`.

Prepared output checks: shell syntax, repeated-byte comparison at 80×24 and 160×30, range rejection and the row/edge structure. Physical panel captures and the manual checklist are blocked by absent hardware; the automated rendering regressions cover separate pre-effect correctness only.
