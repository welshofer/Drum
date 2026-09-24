# Phase 1 — Inventory

Audit date: 2026-09-24. Root: `/Users/welshofer/Developer/Drum`. Baseline: `fcfe548`; working tree initially clean. All audit writes are confined to `audit/`.

## Project instruction and reference files

| File | Lines | Role |
| --- | ---: | --- |
| `CLAUDE.md` | 27 | Primary agent instructions |
| `CREDITS.md` | 24 | Legal attribution/license; preserve requirements |
| `Drum/Resources/Fonts/Glass_TTY_VT220-LICENSE.txt` | 24 | Legal attribution/license; preserve requirements |
| `Drum/Resources/Fonts/Px437_IBM_VGA_8x16-LICENSE.txt` | 428 | Legal attribution/license; preserve requirements |
| `docs/benchmarks/2026-09-18-generic-rgb.md` | 33 | Specification, implementation history, or operating procedure |
| `docs/benchmarks/2026-09-18-srgb.md` | 33 | Specification, implementation history, or operating procedure |
| `docs/performance-benchmark.md` | 79 | Specification, implementation history, or operating procedure |
| `docs/performance.md` | 90 | Specification, implementation history, or operating procedure |
| `docs/phase-1-findings.md` | 98 | Specification, implementation history, or operating procedure |
| `docs/sound.md` | 29 | Specification, implementation history, or operating procedure |
| `drum-spec.md` | 303 | Specification, implementation history, or operating procedure |

Embedded instructions: `drum-spec.md:67–142` and `152–226` are code templates; `263–277` duplicates CLAUDE rules; `281–293` is the kickoff prompt; `297–303` amends earlier requirements. Phases/gates are at `251–259`. No separate few-shot conversation dataset found.

## Configuration, scripts, source comments, and tests

- `.flowdeck/config.json`: Xcode build invocation override (package-plugin validation).
- `project.yml`: authoritative XcodeGen build, dependency, and test configuration.
- `Drum.xcodeproj/project.pbxproj`, shared `Drum.xcscheme`, workspace contents, and `Package.resolved`: generated project and pinned dependency state.
- `scripts/benchmark-performance.sh`, `scripts/profile-performance.py`, `scripts/summarize-performance.py`: executable workflow instructions, usage strings, and comments.
- `Drum/**/*.swift`, `Drum/CRT/CRT.metal`, `DrumTests/*.swift`: implementation invariants and test contracts reviewed in subsequent phases; no LLM runtime prompt construction found by prompt/system/few-shot search.
- `.gitignore`: local build output exclusions. `Drum/Info.plist`: app metadata.

## Searched instruction locations and absences

Enumerated all non-Git files including dotfiles; searched names and content for instructions, prompts, TODO/FIXME, plans, specs, and READMEs. No repository `AGENTS.md`, `.claude/`, `.cursor/`, `.cursorrules`, `.github/` instructions, standalone README, TODO list, or additional plan file exists. `.git/` internals and font binaries are not instruction sources.

Checked ancestor `AGENTS.md` through filesystem root and `CLAUDE.md` in home/Developer; none found. User-wide `~/.codex/AGENTS.md` exists but is empty; `~/.claude/CLAUDE.md` is absent. Session-injected host instructions are not editable project files.

## Local session history

| File | Date range (UTC) | Lines | Scope |
| --- | --- | ---: | --- |
| `/Users/welshofer/.claude/projects/-Users-welshofer-Developer-Drum/e43f9fdd-2984-441b-91bf-63e4fea4815b.jsonl` | 2026-09-11T02:41:03.885Z to 2026-09-11T02:43:22.126Z | 153 | Project history for Phase 3 |
| `/Users/welshofer/.codex/sessions/2026/09/18/rollout-2026-09-18T12-03-54-01a0b5e7-6042-78a3-98bb-6d8e1dfc843d.jsonl` | 2026-09-18T19:04:26.815Z to 2026-09-21T23:43:15.637Z | 1859 | Project history for Phase 3 |
| `/Users/welshofer/.codex/sessions/2026/09/24/rollout-2026-09-24T07-08-51-01a0d3bf-6862-7663-bdeb-88eeafa3857e.jsonl` | 2026-09-24T14:08:55.202Z to 2026-09-24T14:09:46.972Z | 46 | Current audit; excluded as historical evidence |

Discovery: scanned first-record working-directory metadata in 492 Codex sessions and 2 archived sessions; two match this root, one is this audit. Claude has one project JSONL and no subagent transcripts in its Drum directory. Cursor project directories and Gemini tmp content contain no matching project path or Drum directory. No evidence of additional local project history in these locations. Metadata index: `audit/history-index.json`. Raw transcripts are not copied into the audit.

## Review boundaries

Phase 1 complete. Phase 2 reviews all files above for instruction quality; Phase 3 reads both prior sessions in batches and saves sanitized notes. Phase 4 uses checks that keep outputs within `audit/`; app launches, profile scripts, builds/tests with external side effects require care and may be deferred. No changes outside `audit/` are authorized.

## Complete project file list

The following 57 files were present at baseline, including configuration and implementation files searched for embedded instructions.

- `.flowdeck/config.json`
- `.gitignore`
- `CLAUDE.md`
- `CREDITS.md`
- `Drum/App/AppState.swift`
- `Drum/App/DrumApp.swift`
- `Drum/App/DrumBundle.swift`
- `Drum/App/RootView.swift`
- `Drum/Audio/SoundPlayback.swift`
- `Drum/Audio/SoundSettings.swift`
- `Drum/Audio/SoundWaveform.swift`
- `Drum/Audio/TerminalAudio.swift`
- `Drum/CRT/CRT.metal`
- `Drum/CRT/CRTEffect.swift`
- `Drum/CRT/CRTSettings.swift`
- `Drum/CRT/Phosphor.swift`
- `Drum/CRT/PowerOnTransition.swift`
- `Drum/Info.plist`
- `Drum/Resources/Fonts/Glass_TTY_VT220-LICENSE.txt`
- `Drum/Resources/Fonts/Glass_TTY_VT220.ttf`
- `Drum/Resources/Fonts/Px437_IBM_VGA_8x16-LICENSE.txt`
- `Drum/Resources/Fonts/Px437_IBM_VGA_8x16.ttf`
- `Drum/Settings/SettingsView.swift`
- `Drum/Settings/SoundSettingsView.swift`
- `Drum/Terminal/CaretOverlay.swift`
- `Drum/Terminal/DrumTerminalView.swift`
- `Drum/Terminal/GlowOverlay.swift`
- `Drum/Terminal/TerminalBitmapStore.swift`
- `Drum/Terminal/TerminalDisplayClock.swift`
- `Drum/Terminal/TerminalMirror.swift`
- `Drum/Terminal/TerminalSession.swift`
- `Drum/Terminal/TerminalTheme.swift`
- `Drum/Terminal/TerminalTimingObserver.swift`
- `Drum/Terminal/TerminalView.swift`
- `Drum.xcodeproj/project.pbxproj`
- `Drum.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `Drum.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `Drum.xcodeproj/xcshareddata/xcschemes/Drum.xcscheme`
- `DrumTests/CRTSettingsTests.swift`
- `DrumTests/CapturePixels.swift`
- `DrumTests/PerformanceRecorder.swift`
- `DrumTests/TerminalAudioTests.swift`
- `DrumTests/TerminalBitmapStoreTests.swift`
- `DrumTests/TerminalPerformanceTests.swift`
- `DrumTests/TerminalRenderingTests.swift`
- `DrumTests/TerminalThemeTests.swift`
- `docs/benchmarks/2026-09-18-generic-rgb.md`
- `docs/benchmarks/2026-09-18-srgb.md`
- `docs/performance-benchmark.md`
- `docs/performance.md`
- `docs/phase-1-findings.md`
- `docs/sound.md`
- `drum-spec.md`
- `project.yml`
- `scripts/benchmark-performance.sh`
- `scripts/profile-performance.py`
- `scripts/summarize-performance.py`
