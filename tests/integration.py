#!/usr/bin/env python3
"""Exercise the real backend in a disposable process, never inside Dock."""
import json
import math
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import signal
import errno

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
RUNTIME = Path(f"/tmp/window-effects-test-{os.getuid()}")
SOCKET = RUNTIME / "control.sock"


def cli(*args, ok=True):
    result = subprocess.run([str(BUILD / "test-client"), *map(str, args)],
                            capture_output=True, text=True, timeout=8)
    assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
    return json.loads(result.stdout)


def request(value):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(4)
        connection.connect(str(SOCKET))
        connection.sendall(json.dumps(value).encode() + b"\n")
        data = b""
        while b"\n" not in data:
            chunk = connection.recv(4096)
            assert chunk, "backend closed without a response"
            data += chunk
        return json.loads(data)


def appearance(wid):
    return cli("inspect", wid)["appearance"]


def same(a, b):
    return math.isclose(a["opacity"], b["opacity"], abs_tol=.005) and a["shadow"] == b["shadow"]


if SOCKET.exists():
    with socket.socket(socket.AF_UNIX) as probe:
        if probe.connect_ex(str(SOCKET)) == 0:
            raise SystemExit("Another integration test is running")

suffix = '-arm64e' if os.environ.get('WE_TEST_ARCH') == 'arm64e' else ''
env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(BUILD / f"test-payload{suffix}.dylib"))
fixture = subprocess.Popen([str(BUILD / f"fixture{suffix}")], stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, text=True, env=env)
try:
    wid = int(fixture.stdout.readline())
    for _ in range(100):
        try:
            if request({"protocol": 1, "op": "status"})["ok"]:
                break
        except (OSError, AssertionError):
            pass
        time.sleep(.02)
    else:
        raise AssertionError("Backend did not start")

    original = appearance(wid)
    assert original["shadow"], original
    # A normal host can change its own alpha but cannot set Dock's no-shadow tag.
    # Test the rejection and rollback honestly; do not substitute a fake setter.
    rejected = cli("set", wid, ".63", "off", ok=False)
    assert rejected["rolledBack"]
    assert same(appearance(wid), original)
    cli("restore")
    assert cli("set", wid, ".63", "on")["changed"]
    assert same(appearance(wid), {"opacity": .63, "shadow": True})
    assert not cli("set", wid, ".63", "on")["changed"]
    assert cli("doctor")["backend"]["savedWindows"] == 1
    # Original value is preserved across repeated effects and separate clients.
    cli("set", wid, ".82", "on")
    assert same(appearance(wid), {"opacity": .82, "shadow": True})
    assert cli("restore", wid)["restored"] == 1
    assert same(appearance(wid), original)
    assert cli("restore")["restored"] == 0

    # Raw requests exercise validation independently of the CLI's checks.
    for value in [
        {"op": "status"},
        {"protocol": True, "op": "status"},
        {"protocol": 2, "op": "status"},
        {"protocol": 1.5, "op": "status"},
        {"protocol": 1, "op": "execute", "window": wid},
        {"protocol": 1, "op": "set", "window": True, "opacity": .5, "shadow": False},
        {"protocol": 1, "op": "set", "window": wid, "opacity": "0.5", "shadow": False},
        {"protocol": 1, "op": "set", "window": wid, "opacity": 0, "shadow": False},
        {"protocol": 1, "op": "set", "window": wid, "opacity": 1.1, "shadow": False},
        {"protocol": 1, "op": "set", "window": wid, "opacity": .5, "shadow": 0},
    ]:
        assert not request(value)["ok"], value
    assert same(appearance(wid), original)
    for args in [("inspect", "-1"), ("inspect", "4294967296"), ("set", wid, "nan", "off"),
                 ("set", wid, ".5", "false"), ("restore", "1oops")]:
        cli(*args, ok=False)
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "config.json"
        for bad in [{"typo": 1}, {"shadows": 0}, {"inactiveOpacity": True}, {"excludedApps": [42]}, []]:
            path.write_text(json.dumps(bad))
            cli("check-config", path, ok=False)
        path.write_text('{"inactiveOpacity":0.8,"excludedApps":["com.apple.finder"]}')
        assert cli("check-config", path)["config"]["inactiveOpacity"] == .8

    # Oversized and non-object messages do not crash the listener.
    for data in [b"[]\n", b"x" * 65537 + b"\n"]:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(4)
            connection.connect(str(SOCKET))
            try:
                connection.sendall(data)
                connection.recv(1024)
            except OSError as error:
                if error.errno not in (errno.EPIPE, errno.ECONNRESET, errno.ENOTCONN):
                    raise
    assert cli("doctor")["backend"]["ok"]

    cli("set", wid, ".7", "on")
    journal = json.loads((RUNTIME / "originals.json").read_text())
    assert same(journal[str(wid)], original)
    assert cli("restore")["restored"] == 1
    assert json.loads((RUNTIME / "originals.json").read_text()) == {}
    print("PASS: real appearance/readback, restoration, journaling, validation, listener resilience")

    with tempfile.TemporaryDirectory() as temp:
        fake = Path(temp) / 'aerospace'
        marker = Path(temp) / 'subscriptions'
        fake.write_text('''#!/usr/bin/env python3
import sys, time
from pathlib import Path
if sys.argv[1] == 'subscribe':
    with Path(__file__).with_name('subscriptions').open('a') as f: f.write('start\\n')
    print('{"_event":"focus-changed"}', flush=True)
    time.sleep(.1)
elif '--all' in sys.argv: print('[]')
else: sys.exit(1)
''')
        fake.chmod(0o755)
        watcher = subprocess.Popen([str(BUILD / 'test-client'), 'watch'],
                                   env=dict(os.environ, WE_TEST_AEROSPACE=str(fake)),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            for _ in range(150):
                if marker.exists() and len(marker.read_text().splitlines()) >= 2: break
                assert watcher.poll() is None, 'watch exited unexpectedly'
                time.sleep(.02)
            else: raise AssertionError('watch did not reconnect')
            duplicate = subprocess.run([str(BUILD / 'test-client'), 'watch'],
                                       env=dict(os.environ, WE_TEST_AEROSPACE=str(fake)),
                                       capture_output=True, text=True, timeout=5)
            assert duplicate.returncode == 1 and 'already running' in duplicate.stdout
        finally:
            watcher.send_signal(signal.SIGTERM)
            out, err = watcher.communicate(timeout=8)
            assert watcher.returncode == 0, (out, err)
        print('PASS: AeroSpace disconnect/reconnect, single watcher, signal shutdown')

    cli('set', wid, '.7', 'on')
    fixture.stdin.write('c\n')
    fixture.stdin.flush()
    assert fixture.stdout.readline().strip() == 'closed'
    assert cli('restore', wid)['failed'] == []
    assert cli('doctor')['backend']['savedWindows'] == 0
    assert json.loads((RUNTIME / 'originals.json').read_text()) == {}
    print('PASS: closed windows are pruned from restoration state')
finally:
    fixture.terminate()
    fixture.wait(timeout=5)

# Production client reports missing backend without crashing or claiming success.
result = subprocess.run([str(BUILD / "window-effects"), "check-config"], capture_output=True, text=True)
assert result.returncode == 0, result.stderr
print("PASS: production configuration defaults")
