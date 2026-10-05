OS: Version 27.0.1 (Build 26A434); CRT stage: 2560×720 pixels; scale: 2×

Timings are median / p95 / max, in milliseconds. CPU is percent of one core.

Paint endpoint: native: AppKit viewWillDraw; CRT: bitmap publication; neither is screen presentation
Resize method: repeated batches of 90 programmatic window resizes with live-resize policy enabled

60 Hz main-thread ticks measure scheduling, not rendered FPS or screen presentation.

| Mode | Workload | CPU % | Input→PTY | Output handling | Output→paint endpoint | Capture | Terminal resize | Main-thread tick interval |
|---|---|---:|---|---|---|---|---|---|
| crt | idle | 11.9 | — | — | — | — | — | 16.67 / 16.69 / 16.92 |
| crt | typing | 39.2 | 0.15 / 0.28 / 7.41 | 0.14 / 0.21 / 0.28 | 4.21 / 16.34 / 19.50 | 1.56 / 3.37 / 5.20 | — | 16.67 / 19.40 / 22.03 |
| crt | dashboard | 59.1 | — | 0.08 / 0.17 / 0.29 | 11.25 / 30.80 / 42.05 | 3.56 / 6.78 / 8.54 | — | 16.67 / 21.01 / 25.31 |
| crt | scrolling | 71.8 | — | — | — | 3.81 / 4.75 / 9.30 | — | 16.67 / 17.98 / 33.91 |
| crt | resize | 84.0 | — | — | — | 4.24 / 5.53 / 30.24 | 0.16 / 0.27 / 0.60 | 16.66 / 22.09 / 70.19 |

Sample counts by mode/workload (input echoes, captures, tick intervals):
- crt/idle: 0, 0, 1838
- crt/typing: 912, 912, 1882
- crt/dashboard: 0, 1439, 1883
- crt/scrolling: 0, 1802, 1854
- crt/resize: 0, 1530, 1793
