# Optional terminal sounds

Settings → Sound provides independent switches, volume sliders, and previews for:

| Sound | Synthesis | Trigger |
| --- | --- | --- |
| Boot tone | Rounded 785 Hz pulse, 125 ms | Launch and Tube → Power Cycle |
| Terminal bell | Same 785 Hz pulse, 250 ms | SwiftTerm's parsed BEL event |
| Key clicks | Damped bipolar impulse, 3 ms | A key-down while the terminal has focus |
| CRT flyback whine | Quiet sine at 15,734 or 15,625 Hz | Continuous while enabled and active |
| System hum | 50 or 60 Hz, plus second and third harmonics | Continuous while enabled and active |

All switches default to off. Sound preferences persist independently of CRT visual settings. Volume zero mutes a sound. Sounds stop when Drum becomes inactive or powers off; enabled ambient sounds return when it becomes active again. Returning to the app does not replay the boot tone. Ambient start/stop and level changes use short fades.

Previews work without enabling the corresponding switch and do not loop. Leaving the Sound tab or deactivating the app stops a preview. Bell playback is bounded to one voice, so a flood of BELs cannot queue minutes of audio. Key clicks use at most four prepared voices. Command shortcuts, modifier-only keys, paste content, terminal responses, and incoming text do not generate clicks. An OSC sequence terminated by BEL does not ring.

To test a received bell in a shell, run `printf '\a'`. Ctrl-G sends input to the running application; that application decides whether it produces a BEL in response.

## Fidelity

These are VT100-inspired synthesized effects, not recordings or a circuit simulation. The [VT100 Technical Manual, chapter 4](https://vt100.net/docs/vt100-tm/chapter4.html) describes a shared speaker circuit for clicks and a roughly 800 Hz, quarter-second bell. The [simulator author's analysis](https://github.com/larsbrinkhoff/terminal-simulator/issues/15#issuecomment-850822953) derives 785 Hz from keyboard transfer timing. Drum uses 785 Hz for both tones and deliberately chooses a shorter, 125 ms startup burst; that startup duration has not been verified as a hardware specification.

The manual specifies 15.734 kHz horizontal scanning for the VT100, independently of column mode. The 15.625 kHz selection is a broader CRT variation, not a claim about a PAL VT100. The low hum is an optional atmospheric approximation.

## Implementation and verification

AVFoundation plays reusable, in-memory PCM. No per-sample synthesis or file access occurs on the key-input or redraw paths. The key event monitor exists only when key clicks are enabled at nonzero volume. With every sound disabled, no audio players are prepared. No new dependency or bundled sound asset is required.

Tests cover PCM decoding, duration, frequency, bounded amplitudes, settings persistence, silent defaults, power/activity transitions, finite previews, errors, parsed BEL versus OSC termination, terminal focus, and command/paste exclusions. Debug and Release each pass 32 regression tests; the separate performance benchmark remains opt-in. The Sound tab, previews, toggle restoration, and shell BEL command were exercised in the running app without reported playback errors. Subjective sound fidelity and physical key-to-audio latency have not been measured.
