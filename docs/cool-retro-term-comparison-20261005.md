# Drum and cool-retro-term — 2026-10-05

Yes: the strongest ideas to adopt are complete appearance profiles, colour
preservation and convenient typography controls. Most core tube effects
already overlap. This is a source-based comparison and a proposed next phase,
not an implementation request, visual acceptance result or performance ranking.

The inspected upstream `master` snapshot is
`1394ce82fa53d2a87d5adc4d99f9eeba598ea53d`. Its
[README](https://github.com/Swordfish90/cool-retro-term/tree/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d)
describes a Qt6 terminal for Linux and macOS using qmltermwidget. Drum is a
native macOS 26 SwiftUI/Metal application using SwiftTerm. No upstream code,
profile payloads, fonts or assets were copied into Drum.

## Existing overlap and differences

Drum already implements bloom, phosphor colours, scanlines, grille, curvature,
vignette, wobble and a rounded bezel, with live controls and two bundled retro
fonts. Its power transitions and five independently optional sound effects are
part of the current scope. See [current requirements](/Users/welshofer/Developer/Drum/drum-spec.md:9).

Cool-retro-term exposes a broader styling surface: complete profiles, font
sources and rasterization choices, colour mixing, noise/flicker/RGB shift,
ambient light/frame treatment and frame-history burn-in. Its current source
also has [tabs](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/TerminalTabs.qml).
Those are observed source features; no claim is made about their runtime
quality or speed on this machine.

## Recommended order

| Priority | Upstream idea | Drum today | Proposed adaptation |
| --- | --- | --- | --- |
| 1 | [Complete profiles and JSON import/export](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/SettingsGeneralTab.qml) | Phosphor presets and one persisted current configuration | Curated complete looks such as VT220, IBM VGA, Warm Amber, Daily Driver and Ribbon; save/duplicate/share a user's own look. |
| 2 | [Chroma and saturation controls](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/SettingsTerminalTab.qml) | CRT mode phosphor-tints all input; the 16 ANSI slots also remain remapped in native mode | Offer Monochrome and Colour CRT modes, optionally a colour-strength control. Preserve distinctions in errors, diffs and coding-tool output. |
| 3 | [System fonts and spacing](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/SettingsTerminalTab.qml), plus [quick zoom](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/menus/WindowMenu.qml) | Three font choices and a size slider in Settings | Add Cmd-plus/minus/reset and a system monospace picker first; evaluate line spacing with wide/combined characters. |
| 4 | [Launch directory, command and profile arguments](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/main.cpp) | Login-shell launch; reported local CWD used for restart | A small launcher for opening a project or command in Drum, with an optional appearance selection. |
| 5 | [Effects and texture-quality controls](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/SettingsAdvancedTab.qml) | Full-quality bloom normally, reduced taps during live resize, idle/hidden capture pausing | A few measured quality modes such as Balanced and Full. Preserve crisp text and idle pausing; qualify any performance claim with actual presentation evidence. |

Priorities are product judgments based on Drum's daily terminal use and its
wide-panel goal. They are not upstream benchmark results. I would start with
quick zoom as the small improvement, then complete appearance profiles and
colour preservation as the substantial next phase.

Profiles currently appear under **Out (v1)** in the specification. Adopting
them requires deliberately changing that scope; this comparison does not
silently change it. Appearance profiles should be versioned, bounded data with
validation and sensible fallback for missing fonts. Keep shell commands and
working directories in an explicit launch configuration rather than executable
content in a shared appearance file. Reuse Drum's typed Codable settings.

Colour preservation must change both
[TerminalTheme's ANSI palette](/Users/welshofer/Developer/Drum/Drum/Terminal/TerminalTheme.swift:45)
and [the monochrome Metal mask](/Users/welshofer/Developer/Drum/Drum/CRT/CRT.metal:78).
Changing only the phosphor picker would not restore colour. A complete look
must retain the PTY; font changes need explicit regression checks because the
pinned terminal engine's font setter can reset modes and selection.

## Later, conditional ideas

Cool-retro-term's
[burn-in path](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/BurnInEffect.qml)
retains previous-frame information and updates on terminal painting, with a
separate resize policy. That is materially different from Drum's current
80 ms changed-row glow. True phosphor trails could add authenticity, but
Drum's optional persistence phase already requires demonstrated need and a
verified rendering design. Close sustained presentation/readability gates
before accepting more retained textures and rendering work.

Subtle static noise, reflection and richer bezel treatment could follow. Keep
animated noise, flicker and RGB separation opt-in, respect Reduce Motion and
verify legibility. Tabs are a separate session/lifecycle expansion beyond
Drum's single-window v1; they are lower priority for the ribbon-panel goal.

## Licensing boundary

The inspected upstream QML files declare GPL version 3 or later; see the
[effect's license header](https://github.com/Swordfish90/cool-retro-term/blob/1394ce82fa53d2a87d5adc4d99f9eeba598ea53d/app/qml/BurnInEffect.qml).
Use these as feature inspiration and implement Drum's own code. Copying or
porting GPL code needs a separate licensing decision; SwiftTerm's MIT license
does not override that code's terms. SwiftTerm itself permits an open-source
Drum, retaining its
[pinned MIT notices](https://github.com/migueldeicaza/SwiftTerm/blob/5d14406844143538cd8f8851d2d8a67c1fe443e5/LICENSE).
The bundled fonts keep their separate [credits/licenses](/Users/welshofer/Developer/Drum/CREDITS.md:7).

## Burn-down — 20261005

After this comparison, the user's “go!” authorized quick font zoom, complete
appearance profiles with JSON interchange, and colour-preserving CRT. All three
are implemented locally in `9d42220` and `76bb1a5`; the v1 specification now
includes profiles. Debug and Release each passed the full regression run with
88 reported tests / 19 suites, retaining the two opt-in skips. Independent
review approved the implementation. The AppIntents tooling warning remains open.

[The execution record](retro-features-burndown-20261005.md) contains item IDs,
exact commits, source proof, routing/isolation, cycle counts, check commands,
and acceptance limits. Native file-dialog and shortcut interaction acceptance
remains manual; computer-use inspection stopped while the user was actively
using Drum. The remaining ideas in this original comparison are still deferred.
