OS: Version 27.0 (Build 26A428); CRT stage: 2560×720 pixels; scale: 2×

Timings are median / p95 / max, in milliseconds. CPU is percent of one core.

Paint endpoint: native: AppKit viewWillDraw; CRT: bitmap publication; neither is screen presentation
Resize method: 90 programmatic window resizes with live-resize policy enabled

60 Hz main-thread ticks measure scheduling, not rendered FPS or screen presentation.

| Mode | Workload | CPU % | Input→PTY | Output handling | Output→paint endpoint | Capture | Terminal resize | Main-thread tick interval |
|---|---|---:|---|---|---|---|---|---|
| native | idle | 2.4 | — | — | — | — | — | 16.67 / 16.69 / 16.69 |
| native | typing | 9.9 | 0.20 / 0.69 / 1.07 | 0.14 / 0.19 / 0.19 | 5.23 / 6.84 / 12.39 | — | — | 16.67 / 16.70 / 17.00 |
| native | dashboard | 14.5 | — | 0.12 / 0.22 / 0.26 | 28.38 / 28.89 / 33.22 | — | — | 16.67 / 16.69 / 16.76 |
| native | scrolling | 18.9 | — | — | — | — | — | 16.67 / 16.69 / 17.13 |
| native | resize | 34.8 | — | — | — | — | 0.20 / 0.35 / 0.43 | 16.67 / 18.14 / 19.49 |
| crt | idle | 10.8 | — | — | — | — | — | 16.67 / 16.69 / 16.73 |
| crt | typing | 42.0 | 0.18 / 1.13 / 4.71 | 0.16 / 0.23 / 0.33 | 3.63 / 14.16 / 16.24 | 1.35 / 2.18 / 5.39 | — | 16.67 / 18.95 / 77.75 |
| crt | dashboard | 62.7 | — | 0.11 / 0.20 / 0.44 | 13.10 / 30.81 / 38.97 | 5.11 / 7.41 / 8.09 | — | 16.51 / 23.52 / 24.81 |
| crt | scrolling | 76.9 | — | — | — | 5.37 / 6.88 / 7.28 | — | 16.56 / 21.13 / 22.64 |
| crt | resize | 76.8 | — | — | — | 4.48 / 6.34 / 6.82 | 0.15 / 0.29 / 0.41 | 16.58 / 23.43 / 37.09 |

Sample counts by mode/workload (input echoes, captures, tick intervals):
- native/idle: 0, 0, 52
- native/typing: 48, 0, 101
- native/dashboard: 0, 0, 95
- native/scrolling: 0, 0, 95
- native/resize: 0, 0, 108
- crt/idle: 0, 0, 52
- crt/typing: 48, 48, 102
- crt/dashboard: 0, 68, 100
- crt/scrolling: 0, 91, 99
- crt/resize: 0, 92, 109
