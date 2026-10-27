#!/usr/bin/env python3
"""Explicit live Dock test: change only a disposable window, then restore it."""
import json
import math
from pathlib import Path
import subprocess

build = Path(__file__).resolve().parent.parent / 'build'


def cli(*args):
    result = subprocess.run([str(build / 'window-effects'), *map(str, args)],
                            capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return json.loads(result.stdout)


cli('doctor')
fixture = subprocess.Popen([str(build / 'fixture'), '--regular'], stdout=subprocess.PIPE, text=True)
wid = None
try:
    wid = int(fixture.stdout.readline())
    before = cli('inspect', wid)['appearance']
    if not before['shadow'] or not math.isclose(before['opacity'], 1, abs_tol=.005):
        raise RuntimeError('Fixture already has effects. Stop other appearance controllers and retry.')
    cli('set', wid, '.63', 'off')
    after = cli('inspect', wid)['appearance']
    assert not after['shadow'] and math.isclose(after['opacity'], .63, abs_tol=.005), after
    cli('restore', wid)
    restored = cli('inspect', wid)['appearance']
    assert restored['shadow'] == before['shadow'] and math.isclose(restored['opacity'], before['opacity'], abs_tol=.005)
    print('PASS: real Dock backend changed and restored a separate process window')
    cli('set', wid, '.63', 'off')
    fixture.terminate()
    fixture.wait(timeout=5)
    assert cli('restore', wid)['failed'] == []
    assert wid not in cli('doctor')['backend']['windows']
    print('PASS: destroyed foreign windows leave no stale restoration entry')
    print(json.dumps(cli('doctor'), indent=2))
finally:
    try:
        if wid is not None:
            cli('restore', wid)
    finally:
        fixture.terminate()
        fixture.wait(timeout=5)
