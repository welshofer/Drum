"""Read-only project checks; all generated evidence stays in audit/."""
from pathlib import Path
import ast, hashlib, json, plistlib, re, subprocess, sys
from xml.etree import ElementTree
root = Path(__file__).resolve().parent.parent
out = root / 'audit'
checks = []
def check(name, ok, detail):
    checks.append({'check': name, 'passed': bool(ok), 'detail': detail})
def run(name, args):
    p = subprocess.run(args, cwd=root, text=True, capture_output=True)
    (out / (name + '.log')).write_text(p.stdout + p.stderr)
    check(name, p.returncode == 0, f'exit {p.returncode}; audit/{name}.log')
    return p
for p in (root / 'scripts').glob('*.py'):
    ast.parse(p.read_text(), filename=str(p))
    check('Python syntax: ' + p.name, True, 'Parsed in memory; no bytecode cache')
run('shell-syntax', ['/bin/bash', '-n', 'scripts/benchmark-performance.sh'])
for f in ['Drum/Info.plist', 'Drum.xcodeproj/project.pbxproj']:
    run('plist-' + Path(f).name, ['/usr/bin/plutil', '-lint', f])
for f in ['Drum.xcodeproj/xcshareddata/xcschemes/Drum.xcscheme', 'Drum.xcodeproj/project.xcworkspace/contents.xcworkspacedata']:
    ElementTree.parse(root / f)
    check('XML: ' + Path(f).name, True, 'Parsed in memory')
for f in ['.flowdeck/config.json', 'Drum.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']:
    json.loads((root / f).read_text())
    check('JSON: ' + Path(f).name, True, 'Parsed in memory')
sources = sorted((root / 'Drum').rglob('*.swift')) + sorted((root / 'DrumTests').rglob('*.swift'))
swift = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
run('swift-parse', [swift, '-frontend', '-parse', '-swift-version', '6', '-module-cache-path', str(out / 'ModuleCache')] + [str(p) for p in sources])
check('Swift syntax scope', True, f'{len(sources)} Swift files parsed; no typecheck, linking, tests, or app execution')
keys = ['inputToPTYMs','outputHandlingMs','outputToPaintMs','captureMs','terminalResizeMs','mainThreadTickIntervalsMs']
def stage(cpu, values):
    return {'mode':'crt','workload':'typing','processCPUPercent':cpu, **{k:values if k=='inputToPTYMs' else [] for k in keys}}
fixture = {'os':'synthetic fixture','scale':2,'paintEndpoint':'synthetic; not screen presentation','resizeMethod':'synthetic', 'stages':[stage(10,[1,2,3]),stage(30,[4,5])]}
(out / 'summary-fixture.json').write_text(json.dumps(fixture))
p=run('summary-smoke', [sys.executable, '-B', 'scripts/summarize-performance.py', 'audit/summary-fixture.json'])
check('Summary calculations', '| crt | typing | 20.0 | 3.00 / 5.00 / 5.00 |' in p.stdout and '- crt/typing: 5, 0, 0' in p.stdout, 'Known median, p95, maximum, mean CPU, empty series and sample counts')
check('Summary presentation caveat', 'not rendered FPS or screen presentation' in p.stdout, 'Avoid equating display callbacks to presentation')
run('diff-check', ['git','diff','--check'])
baseline=json.loads((out/'baseline.json').read_text())
changed=[f for f,digest in baseline.items() if not (root/f).is_file() or hashlib.sha256((root/f).read_bytes()).hexdigest()!=digest]
check('Tracked project unchanged', not changed, f'{len(baseline)} file hashes compared; changed: {changed}')
# Corroboration of current instruction findings, not runtime behavior tests.
claude=(root/'CLAUDE.md').read_text(); spec=(root/'drum-spec.md').read_text()
check('Whole-file mandate remains', 'Always return whole files' in claude and 'whole-file edits only' in spec, 'P1')
check('Window conflict remains', 'window goes `styleMask = [.borderless]`' in spec and 'No screen pinning' in claude and 'Window("Drum"' in (root/'Drum/App/DrumApp.swift').read_text(), 'P2')
check('Copied rules and kickoff remain', '## 9. CLAUDE.md' in spec and '## 10. Kickoff prompt' in spec and 'Use the shader and modifier code in the spec as the starting point' in spec, 'P3/P4')
check('Native rendering implemented', 'let alpha: CGFloat = enabled ? 0 : 1' in (root/'Drum/Terminal/TerminalView.swift').read_text(), 'P6; behavior differs from unconditional invisible wording')
check('Bounds wording overbroad', 'every shader takes' in claude and bool(re.search(r'crtBloom\(float2 position, SwiftUI::Layer layer,\s+float radius', (root/'Drum/CRT/CRT.metal').read_text())), 'P8; bloom has no bounds argument')
check('Build documentation drift remains', '-skipPackagePluginValidation' not in claude and '-skipPackagePluginValidation' in (root/'.flowdeck/config.json').read_text() and 'ENABLE_TESTABILITY=YES' in (root/'docs/performance.md').read_text(), 'P7; no claim a fresh build was attempted')
report_fields=(root/'DrumTests/TerminalPerformanceTests.swift').read_text().split('private struct Report: Encodable')[1]
check('Benchmark provenance fields absent', all(x not in report_fields for x in ['revision','commit','xcode','hardware']), 'S7; report has OS, scale, stage size, endpoint, resize method, stages')
(out/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
for c in checks: print(('PASS' if c['passed'] else 'FAIL') + ' ' + c['check'] + ': ' + c['detail'])
sys.exit(0 if all(c['passed'] for c in checks) else 1)
