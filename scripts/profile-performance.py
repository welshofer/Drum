#!/usr/bin/env python3
"""Attach before releasing the test workload; don't infer readiness from stdout."""
import ctypes
import datetime
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid
from xml.etree import ElementTree

repo = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1] if len(sys.argv) > 1 else
              f"/tmp/drum-performance/profile-{datetime.datetime.now():%Y%m%d-%H%M%S}").resolve()
if output.exists() and any(output.iterdir()):
    raise SystemExit("Choose an empty output directory for a new profile.")
output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, DRUM_BENCHMARK_WAIT="1", DRUM_BENCHMARK_REPETITIONS="1")
notify = ctypes.CDLL('/usr/lib/system/libsystem_notify.dylib')
token = ctypes.c_int()
name = f"com.welshofer.Drum.profile.{uuid.uuid4()}"
if notify.notify_register_check(name.encode(), ctypes.byref(token)) != 0:
    raise SystemExit("Could not register for Instruments' recording-start notification.")
flag = ctypes.c_int()
notify.notify_check(token.value, ctypes.byref(flag))  # Clear the registration edge.
children = []

def wait_for(condition, process, seconds):
    deadline = time.monotonic() + seconds
    while not condition():
        if process.poll() is not None:
            raise RuntimeError("A child exited before becoming ready; inspect its log.")
        if time.monotonic() >= deadline:
            raise TimeoutError("Timed out waiting for recording readiness.")
        time.sleep(.1)

try:
    with (output / 'runner.log').open('w') as runner_log, (output / 'trace.log').open('w') as trace_log:
        runner = subprocess.Popen([str(repo / 'scripts/benchmark-performance.sh'), str(output)],
                                  env=env, stdout=runner_log, stderr=subprocess.STDOUT, start_new_session=True)
        children.append(runner)
        print(f"Building isolated benchmark; output: {output}", flush=True)
        wait_for(lambda: (output / 'ready').exists(), runner, 300)
        pid = (output / 'ready').read_text().strip()
        trace = subprocess.Popen(['xcrun', 'xctrace', 'record', '--template', 'SwiftUI',
                                  '--instrument', 'os_signpost', '--attach', pid, '--time-limit', '40s',
                                  '--notify-tracing-started', name, '--no-prompt',
                                  '--output', str(output / 'swiftui.trace')],
                                 stdout=trace_log, stderr=subprocess.STDOUT, start_new_session=True)
        children.append(trace)
        def started():
            notify.notify_check(token.value, ctypes.byref(flag))
            return flag.value != 0
        wait_for(started, trace, 90)
        (output / 'start').touch()
        print('Recording-start notification received; releasing workloads.', flush=True)
        if runner.wait(timeout=240) != 0 or trace.wait(timeout=240) != 0:
            raise RuntimeError('Benchmark or trace failed; inspect runner.log and trace.log.')
    for line in (output / 'trace.log').read_text().splitlines():
        if '[Warning]' in line:
            print(line, flush=True)
    trace_path = str(output / 'swiftui.trace')
    subprocess.run(['xcrun', 'xctrace', 'export', '--input', trace_path, '--toc',
                    '--output', str(output / 'toc.xml')], check=True, stdout=subprocess.DEVNULL)
    tree = ElementTree.parse(output / 'toc.xml')
    for target in tree.findall('.//target'):
        for environment in target.findall('environment'):
            target.remove(environment)
    tree.write(output / 'toc.xml')
    for schema in ['os-signpost', 'hitches', 'time-profile']:
        subprocess.run(['xcrun', 'xctrace', 'export', '--input', trace_path,
                        '--xpath', f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]',
                        '--output', str(output / f'{schema}.xml')], check=True, stdout=subprocess.DEVNULL)
    print(f'Profile and measurements ready: {output}')
finally:
    notify.notify_cancel(token.value)
    for child in children:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
