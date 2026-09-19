OS: Version 27.0 (Build 26A428); CRT stage: 2560×720 pixels; scale: 2×

Timings are median / p95 / max, in milliseconds. CPU is percent of one core.

Paint endpoint: native: AppKit viewWillDraw; CRT: bitmap publication; neither is screen presentation
Resize method: 90 programmatic window resizes with live-resize policy enabled

60 Hz main-thread ticks measure scheduling, not rendered FPS or screen presentation.

| Mode | Workload | CPU % | Input→PTY | Output handling | Output→paint endpoint | Capture | Terminal resize | Main-thread tick interval |
|---|---|---:|---|---|---|---|---|---|
| native | idle | 1.1 | — | — | — | — | — | 16.67 / 16.68 / 16.69 |
| native | typing | 7.9 | 0.16 / 0.30 / 0.64 | 0.12 / 0.26 / 0.46 | 5.60 / 7.04 / 16.44 | — | — | 16.67 / 16.69 / 16.72 |
| native | dashboard | 13.0 | — | 0.11 / 0.15 / 0.23 | 11.25 / 31.15 / 33.49 | — | — | 16.67 / 16.68 / 16.78 |
| native | scrolling | 17.4 | — | — | — | — | — | 16.67 / 16.68 / 16.82 |
| native | resize | 29.8 | — | — | — | — | 0.21 / 0.35 / 0.47 | 16.66 / 17.46 / 19.24 |
| crt | idle | 7.4 | — | — | — | — | — | 16.67 / 16.68 / 16.69 |
| crt | typing | 43.3 | 0.15 / 0.18 / 0.20 | 0.15 / 0.18 / 0.29 | 2.76 / 4.60 / 18.87 | 1.14 / 1.33 / 3.57 | — | 16.67 / 18.03 / 18.73 |
| crt | dashboard | 80.5 | — | 0.10 / 0.14 / 0.20 | 10.83 / 29.87 / 41.78 | 4.47 / 4.80 / 5.28 | — | 16.66 / 21.60 / 22.12 |
| crt | scrolling | 91.4 | — | — | — | 4.53 / 5.02 / 5.21 | — | 16.65 / 18.28 / 21.81 |
| crt | resize | 83.6 | — | — | — | 4.62 / 5.22 / 6.87 | 0.14 / 0.27 / 0.50 | 16.65 / 21.80 / 23.76 |

Sample counts by mode/workload (input echoes, captures, tick intervals):
- native/idle: 0, 0, 154
- native/typing: 144, 0, 303
- native/dashboard: 0, 0, 291
- native/scrolling: 0, 0, 285
- native/resize: 0, 0, 316
- crt/idle: 0, 0, 156
- crt/typing: 144, 144, 303
- crt/dashboard: 0, 222, 295
- crt/scrolling: 0, 276, 287
- crt/resize: 0, 284, 322
