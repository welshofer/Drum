"""Validate the applied audit scope without rebuilding unchanged app code."""
from pathlib import Path
import ast
import hashlib
import json
import re
import subprocess

root=Path(__file__).resolve().parents[2]
notes=[]
def record(message): notes.append(message)
baseline=json.loads((root/'audit/baseline.json').read_text())
allowed={'.gitignore','CLAUDE.md','drum-spec.md','docs/phase-1-findings.md',
         'Drum/CRT/CRT.metal','docs/performance-benchmark.md','scripts/benchmark-performance.sh'}
changed={p for p,digest in baseline.items() if not (root/p).exists() or hashlib.sha256((root/p).read_bytes()).hexdigest()!=digest}
assert changed==allowed,(changed,allowed)
record('Exactly seven approved tracked paths changed; project, lockfile, tests, licensing and all other source content unchanged.')
old=subprocess.check_output(['git','show','HEAD:Drum/CRT/CRT.metal'],cwd=root,text=True)
strip=lambda s:re.sub(r'\s+','',re.sub(r'//[^\n]*','',s))
assert strip(old)==strip((root/'Drum/CRT/CRT.metal').read_text())
assert not (root/'scripts/check-project.sh').exists() and not (root/'docs/development.md').exists()
record('Metal executable tokens unchanged. Reverted R3 helper/runbook absent.')
for p in (root/'scripts').glob('*.py'): ast.parse(p.read_text(),filename=str(p))
subprocess.run(['bash','-n','scripts/benchmark-performance.sh'],cwd=root,check=True)
subprocess.run(['git','diff','--check'],cwd=root,check=True)
record('Production Python AST, benchmark shell syntax and diff whitespace checks pass.')
files=['CLAUDE.md','drum-spec.md','docs/phase-1-findings.md','docs/performance-benchmark.md','docs/history/drum-kickoff-2026-09-10.md','audit/CHANGELOG.md']
links=0
for f in files:
 for target in re.findall(r'\]\(([^)]+)\)',(root/f).read_text()):
  if '://' in target: continue
  path,_,anchor=target.partition('#');dest=(root/f).parent/path if path else root/f
  assert dest.exists(),(f,target)
  if anchor:
   headings=[re.sub(r'[^\w\- ]','',line.lstrip('# ').strip().lower()).replace(' ','-') for line in dest.read_text().splitlines() if line.startswith('#')]
   assert anchor in headings,(f,target)
  links+=1
record(f'{links} local document links and anchors resolve.')
original=subprocess.check_output(['git','show','HEAD:drum-spec.md'],cwd=root,text=True)
spec=(root/'drum-spec.md').read_text()
for line in original.splitlines():
 if line.startswith('| **'): assert line.split('|')[3].strip() in spec
for p in ['CLAUDE.md','drum-spec.md']:
 text=(root/p).read_text()
 for old in ['Always return whole files','whole-file edits only','every shader takes','WindowGroup']:
  assert old not in text,(p,old)
record('All three phase gates preserved; active stale whole-file/window/shader instructions removed.')
evidence=root/'docs/benchmarks/2026-09-24-audit-validation'
manifest=json.loads((evidence/'manifest.json').read_text())
assert manifest['measurements_sha256']==hashlib.sha256((evidence/'measurements.json').read_bytes()).hexdigest()
summary=subprocess.check_output(['python3','scripts/summarize-performance.py',str(evidence/'measurements.json')],cwd=root,text=True)
assert summary==(evidence/'summary.md').read_text()
assert {p.name for p in evidence.iterdir()}=={'manifest.json','measurements.json','summary.md'}
record('Retained evidence checksum and exact regenerated summary verified; only three allowlisted files present.')
for name in ['r3-debug-tests','r3-release-tests']:
 text=(root/'audit/validation'/name/'xcodebuild.log').read_text()
 assert 'Test run with 32 tests in 6 suites passed' in text and '** TEST SUCCEEDED **' in text
 assert 'warning: Metadata extraction skipped' in text
record('Debug/Release logs each confirm 32 passing regression tests and the reported tooling-warning limitation.')
(root/'audit/validation/final-results.txt').write_text('\n'.join(notes)+'\n')
print('\n'.join(notes))
