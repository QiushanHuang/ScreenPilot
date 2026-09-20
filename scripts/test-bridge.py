#!/usr/bin/env python3
"""Read-only bridge checks; --native-roundtrip additionally rewrites the SAME native brightness."""
import json
import subprocess
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
bridge = root / '.build/native/DisplayBridge'
def call(*args, expected=0):
    p = subprocess.run([str(bridge), *map(str, args)], capture_output=True, text=True, timeout=6)
    assert p.returncode == expected, (p.returncode, p.stderr, p.stdout)
    return json.loads(p.stdout)
result = call('list')
assert result['ok'] is True
screens = result['displays']
assert len({d['id'] for d in screens}) == len(screens)
for d in screens:
    rejected = call('set', d['id'], 'invalid-uuid', d['location'], 'brightness', 50, expected=1)
    assert rejected['ok'] is False
if '--native-roundtrip' in sys.argv:
    for d in screens:
        if not d['builtIn']:
            continue
        before = call('probe', d['id'], d['uuid'], d['location'])['brightness']['current']
        reply = call('set', d['id'], d['uuid'], d['location'], 'brightness', before)
        assert type(reply['verified']) is bool and reply['verified']
        assert reply['current'] == before
print(f'Bridge identity rejection passed for {len(screens)} displays')
