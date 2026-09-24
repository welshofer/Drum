#!/usr/bin/env python3
"""Record benchmark provenance and export only validated numeric evidence."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

REPO = Path(__file__).resolve().parent.parent
MODES = {'native', 'crt', 'crt-no-bloom', 'crt-static'}
WORKLOADS = {'idle', 'typing', 'dashboard', 'scrolling', 'resize'}
SERIES = ('inputToPTYMs', 'outputHandlingMs', 'outputToPaintMs', 'captureMs',
          'captureArea', 'terminalResizeMs', 'mainThreadTickIntervalsMs')
SCALARS = ('startedAtUptimeSeconds', 'wallSeconds', 'processCPUPercent')
ENDPOINT = 'native: AppKit viewWillDraw; CRT: bitmap publication; neither is screen presentation'
RESIZE = '90 programmatic window resizes with live-resize policy enabled'


def command(*args):
    return subprocess.check_output(args, cwd=REPO, text=True).strip()


def timestamp():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_digest():
    # Include uncommitted/new build inputs without exporting paths or contents.
    files = [REPO / 'project.yml']
    for folder in ('Drum', 'DrumTests', 'Drum.xcodeproj', 'scripts'):
        files.extend(p for p in (REPO / folder).rglob('*') if p.is_file()
                     and not {'xcuserdata', '__pycache__'}.intersection(p.parts))
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(str(path.relative_to(REPO)).encode() + b'\0')
        digest.update(path.read_bytes() + b'\0')
    return digest.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
            'Measurement must be a finite nonnegative number.')
    return value


def text_matching(value, pattern):
    require(isinstance(value, str) and re.fullmatch(pattern, value), 'Unexpected metadata format.')
    return value


def selected_modes(value):
    modes = value.split(',')
    require(modes and len(modes) == len(set(modes)) and set(modes) <= MODES,
            'Choose unique modes from native,crt,crt-no-bloom,crt-static.')
    return modes


def start(directory, modes, repetitions):
    require(repetitions > 0, 'Repetitions must be positive.')
    selected = selected_modes(modes)
    path = directory / 'manifest.json'
    require(not path.exists(), 'Refusing to overwrite a run manifest.')
    lock = json.loads((REPO / 'Drum.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
    pin = next(p for p in lock['pins'] if p['identity'] == 'swiftterm')['state']
    xcode = command('xcodebuild', '-version').splitlines()
    require(len(xcode) == 2, 'Unexpected Xcode version output.')
    directory.mkdir(parents=True, exist_ok=True)
    write_json(path, {
        'schema_version': 1, 'status': 'running', 'started_at_utc': timestamp(),
        'source_commit': command('git', 'rev-parse', 'HEAD'),
        'source_dirty': bool(command('git', 'status', '--porcelain')),
        'source_sha256': source_digest(), 'xcode_version': xcode[0], 'xcode_build': xcode[1],
        'configuration': 'Release', 'architecture': 'arm64',
        'swiftterm_revision': pin['revision'], 'swiftterm_version': pin['version'],
        'modes': selected, 'repetitions': repetitions,
    })


def sanitized_report(raw):
    # Free-form strings, unknown keys, environments and terminal text are not exported.
    result = {
        'os': text_matching(raw['os'], r'Version [0-9.]+ \(Build [A-Za-z0-9]+\)'),
        'scale': number(raw['scale']), 'stagePixels': [2560, 720],
        'paintEndpoint': ENDPOINT, 'resizeMethod': RESIZE, 'stages': [],
    }
    require(raw['stagePixels'] == result['stagePixels'] and raw['paintEndpoint'] == ENDPOINT
            and raw['resizeMethod'] == RESIZE and result['scale'] > 0, 'Unexpected benchmark contract.')
    require(isinstance(raw['stages'], list) and raw['stages'], 'No workload samples.')
    for stage in raw['stages']:
        require(stage['mode'] in MODES and stage['workload'] in WORKLOADS, 'Unknown mode/workload.')
        clean = {'mode': stage['mode'], 'workload': stage['workload']}
        clean.update({key: number(stage[key]) for key in SCALARS})
        for key in SERIES:
            require(isinstance(stage[key], list), 'Expected sample array.')
            clean[key] = [number(value) for value in stage[key]]
        result['stages'].append(clean)
    return result


def sanitized_manifest(raw):
    require(raw['schema_version'] == 1 and raw['status'] == 'complete', 'Run is incomplete.')
    clean = {'schema_version': 1, 'status': 'complete'}
    for key in ('started_at_utc', 'finished_at_utc'):
        value = raw[key]
        require(datetime.fromisoformat(value).utcoffset().total_seconds() == 0, 'Expected UTC date.')
        clean[key] = text_matching(value, r'[0-9T:+.\-]+')
    for key in ('source_commit', 'swiftterm_revision'):
        clean[key] = text_matching(raw[key], r'[a-f0-9]{40}')
    for key in ('source_sha256', 'measurements_sha256'):
        clean[key] = text_matching(raw[key], r'[a-f0-9]{64}')
    for key, pattern in [('xcode_version', r'Xcode [0-9.]+'),
                         ('xcode_build', r'Build version [A-Za-z0-9]+'),
                         ('swiftterm_version', r'[0-9.]+')]:
        clean[key] = text_matching(raw[key], pattern)
    require(type(raw['source_dirty']) is bool, 'Expected dirty boolean.')
    require(raw['configuration'] == 'Release' and raw['architecture'] == 'arm64', 'Unexpected build configuration.')
    clean.update(source_dirty=raw['source_dirty'], configuration='Release', architecture='arm64')
    require(isinstance(raw['modes'], list), 'Expected modes list.')
    clean['modes'] = selected_modes(','.join(raw['modes']))
    require(type(raw['repetitions']) is int and raw['repetitions'] > 0, 'Invalid repetitions.')
    clean['repetitions'] = raw['repetitions']
    require(type(raw['build_warning_count']) is int and raw['build_warning_count'] >= 0, 'Invalid warning count.')
    clean['build_warning_count'] = raw['build_warning_count']
    return clean


def check_coverage(report, manifest):
    actual = Counter((s['mode'], s['workload']) for s in report['stages'])
    expected = Counter({(mode, workload): manifest['repetitions']
                        for mode in manifest['modes'] for workload in WORKLOADS})
    require(actual == expected, 'Missing or unexpected workload repetitions.')


def finish(directory):
    path = directory / 'manifest.json'
    manifest = json.loads(path.read_text())
    require(manifest['status'] == 'running', 'Run was already finalized.')
    require(source_digest() == manifest['source_sha256'], 'Build inputs changed during the run; rerun it.')
    report = sanitized_report(json.loads((directory / 'measurements.json').read_text()))
    check_coverage(report, manifest)
    log = (directory / 'build-test.log').read_text(errors='replace')
    manifest.update(status='complete', finished_at_utc=timestamp(),
                    measurements_sha256=checksum(directory / 'measurements.json'),
                    build_warning_count=len(re.findall(r'(?im)(?:^|\s)warning:', log)))
    write_json(path, sanitized_manifest(manifest))


def export(directory, destination):
    manifest = sanitized_manifest(json.loads((directory / 'manifest.json').read_text()))
    require(checksum(directory / 'measurements.json') == manifest['measurements_sha256'],
            'Sample checksum does not match the completed run.')
    report = sanitized_report(json.loads((directory / 'measurements.json').read_text()))
    check_coverage(report, manifest)
    require(not destination.exists(), 'Choose a new evidence directory; refusing to overwrite.')
    # Prepare the summary before creating the destination. Only these three files leave the run directory.
    summary = subprocess.check_output(
        ['python3', str(REPO / 'scripts/summarize-performance.py'), '/dev/stdin'],
        input=json.dumps(report), text=True, cwd=REPO)
    destination.mkdir(parents=True)
    write_json(destination / 'measurements.json', report)
    manifest['measurements_sha256'] = checksum(destination / 'measurements.json')
    write_json(destination / 'manifest.json', manifest)
    (destination / 'summary.md').write_text(summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    begin = sub.add_parser('start')
    begin.add_argument('directory', type=Path)
    begin.add_argument('--modes', default='native,crt')
    begin.add_argument('--repetitions', type=int, default=3)
    end = sub.add_parser('finish')
    end.add_argument('directory', type=Path)
    copy = sub.add_parser('export')
    copy.add_argument('directory', type=Path)
    copy.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'start': start(args.directory, args.modes, args.repetitions)
        elif args.action == 'finish': finish(args.directory)
        else: export(args.directory, args.destination)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Benchmark evidence failed: {error}\n')


if __name__ == '__main__':
    main()
