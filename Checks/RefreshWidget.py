"""Run with: python3 Checks/RefreshWidget.py; no system registration is changed."""
from pathlib import Path
import subprocess
import shlex

source = (Path(__file__).resolve().parents[1] / 'scripts/refresh-widget.sh').read_text()
start = source.index('                if removal=')
end = source.index('\n                fi', start) + len('\n                fi')
handler = source[start:end].replace('/usr/bin/pluginkit', 'mock_plugin')
bundle = '/tmp/Test Calendar.app/Contents/PlugIns/Calendar.appex'
for code, message, should_continue in [
    (0, '', True),
    (1, f'remove: no plugin at {bundle}', True),
    (1, 'remove: Connection invalid', False),
    (1, 'remove: permission denied', False),
    (1, 'remove: no plugin at /another/plugin.appex', False),
]:
    script = f'''set -euo pipefail
bundle={shlex.quote(bundle)}
mock_plugin() {{ printf '%s\\n' {shlex.quote(message)} >&2; return {code}; }}
{handler}
echo CONTINUED
'''
    result = subprocess.run(['/bin/bash', '-c', script], text=True, capture_output=True)
    assert (result.returncode == 0) == should_continue, (message, result)
    assert ('CONTINUED' in result.stdout) == should_continue
    if not should_continue:
        assert message in result.stderr
print('PASS: registered removal, absent plugin, paths with spaces, connection/permission errors preserved')
