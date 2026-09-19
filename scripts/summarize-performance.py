#!/usr/bin/env python3
"""Summarize raw samples without confusing display callbacks with rendered FPS."""
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
groups = defaultdict(list)
for stage in report["stages"]:
    groups[(stage["mode"], stage["workload"])].append(stage)

def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]

def summary(values):
    if not values:
        return "—"
    return f"{statistics.median(values):.2f} / {percentile(values, .95):.2f} / {max(values):.2f}"

print(f"OS: {report['os']}; CRT stage: 2560×720 pixels; scale: {report['scale']}×")
print("\nTimings are median / p95 / max, in milliseconds. CPU is percent of one core.")
print("\nPaint endpoint: " + report["paintEndpoint"])
print("Resize method: " + report["resizeMethod"])
print("\n60 Hz main-thread ticks measure scheduling, not rendered FPS or screen presentation.\n")
print("| Mode | Workload | CPU % | Input→PTY | Output handling | Output→paint endpoint | Capture | Terminal resize | Main-thread tick interval |")
print("|---|---|---:|---|---|---|---|---|---|")
keys = ["inputToPTYMs", "outputHandlingMs", "outputToPaintMs", "captureMs", "terminalResizeMs", "mainThreadTickIntervalsMs"]
for (mode, workload), stages in groups.items():
    cpu = statistics.mean(stage["processCPUPercent"] for stage in stages)
    cells = [summary([v for stage in stages for v in stage[key]]) for key in keys]
    print(f"| {mode} | {workload} | {cpu:.1f} | " + " | ".join(cells) + " |")
print("\nSample counts by mode/workload (input echoes, captures, tick intervals):")
for (mode, workload), stages in groups.items():
    counts = [sum(len(s[key]) for s in stages) for key in ["inputToPTYMs", "captureMs", "mainThreadTickIntervalsMs"]]
    print(f"- {mode}/{workload}: " + ", ".join(map(str, counts)))
