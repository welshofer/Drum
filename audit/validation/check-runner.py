"""Exercise check-project's control flow with fake build tools, never a real build."""
from pathlib import Path
import os, subprocess
root=Path.cwd(); area=root/'audit/validation/r3-fixtures'; bin_dir=area/'bin'; bin_dir.mkdir(parents=True,exist_ok=True)
for name,source in {
 'metal':'#!/bin/bash\nexit 0\n',
 'xcrun':'#!/bin/bash\n[[ "${FAKE_MISSING_METAL:-0}" != 1 ]] || exit 1\nprintf "%s\\n" "$(dirname "$0")/metal"\n',
 'xcodebuild':'''#!/bin/bash
if [[ "$1" == -version ]]; then echo 'Xcode fixture'; exit 0; fi
printf '%s\\n' "$@" > "$FAKE_ARGS"
[[ "${FAKE_WARNING:-0}" != 1 ]] || echo 'tool: warning: fixture warning'
exit "${FAKE_STATUS:-0}"
'''
}.items():
 p=bin_dir/name;p.write_text(source);p.chmod(0o755)
results=[]
def run(label,args,expected,**options):
 out=area/label; env=dict(os.environ,PATH=str(bin_dir)+':'+os.environ['PATH'],FAKE_ARGS=str(area/'args'),**options)
 p=subprocess.run(['scripts/check-project.sh',*args,'--output-dir',str(out)],env=env,text=True,capture_output=True)
 assert p.returncode==expected,(label,p.returncode,p.stdout,p.stderr)
 results.append(f'{label}: expected exit {expected}; matched')
run('bad-action',['invalid','Debug'],2)
run('bad-configuration',['build','Invalid'],2)
run('missing-metal',['build','Debug'],2,FAKE_MISSING_METAL='1')
run('failed-build',['build','Debug'],65,FAKE_STATUS='65')
run('warning',['build','Debug'],3,FAKE_WARNING='1')
run('good-test',['test','Release'],0)
args=(area/'args').read_text();assert 'ENABLE_TESTABILITY=YES' in args and '-skip-testing:DrumTests/TerminalPerformanceTests' in args and '-skipPackagePluginValidation' not in args
run('explicit-plugin',['build','Debug','--allow-reviewed-plugin'],0)
assert '-skipPackagePluginValidation' in (area/'args').read_text()
run('good-test',['test','Release'],2) # Existing log must not be overwritten.
(area/'results.txt').write_text('\n'.join(results)+'\n');print('\n'.join(results))
