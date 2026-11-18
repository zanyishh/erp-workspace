#!/usr/bin/env python3
"""Explicitly start/stop the isolated native MobSF service; never upload or scan."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from install_containers import require_storage
from install_mobsf import environment
from install_native import plain_path

ROOT = Path(__file__).resolve().parents[2]
LOCATION = ROOT / ".local/quality/location.json"
PIDFILE = ROOT / ".local/quality/mobsf-service.json"
LISTEN = "127.0.0.1:8009"
OUTBOUND_DENY_POLICY = '(version 1) (allow default) (deny network-outbound)'


def identity(pid):
    if not isinstance(pid, int) or pid <= 1:
        return None
    try:
        birth = subprocess.check_output(["/bin/ps", "-p", str(pid), "-o", "lstart="],
                                        text=True, env={"LC_ALL": "C"}, stderr=subprocess.DEVNULL).strip()
        library = ctypes.CDLL("/usr/lib/libproc.dylib")
        library.proc_pidpath.argtypes = (ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32)
        library.proc_pidpath.restype = ctypes.c_int
        executable = ctypes.create_string_buffer(4096)
        length = library.proc_pidpath(pid, executable, ctypes.sizeof(executable))
        group = os.getpgid(pid)
        if not birth or length <= 0 or group != pid:
            return None
        return {"started": birth, "process_executable": executable.value.decode(), "process_group": group}
    except (OSError, subprocess.CalledProcessError):
        return None


def group_active(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("plan", "start", "stop", "status"), nargs="?", default="plan")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--offline-outbound", action="store_true",
                        help="Block outbound networking in the service and its child processes")
    args = parser.parse_args()
    if args.action == "plan" or (args.action in ("start", "stop") and not args.execute):
        print(f"Plan only: native MobSF uses {LISTEN}. Start/stop requires --execute. No service or scan started.")
        return
    plain_path(PIDFILE)
    record = json.loads(PIDFILE.read_text()) if PIDFILE.is_file() else {}
    current = identity(record.get("pid"))
    live = bool(current and all(record.get(key) == value for key, value in current.items()))
    if args.action == "status":
        print(f"Native MobSF process is active; configured endpoint is {LISTEN}, listener not verified." if live else "No active native MobSF launcher process is recorded.")
        return
    if args.action == "stop":
        if not live:
            print("No matching native MobSF process to stop; no other process was changed.")
            return
        os.killpg(current["process_group"], signal.SIGTERM)
        for _ in range(150):
            if not group_active(current["process_group"]):
                PIDFILE.unlink()
                print("Stopped native MobSF; its database, artifacts and logs were retained.")
                return
            time.sleep(0.2)
        raise RuntimeError("MobSF received the stop request and is still shutting down; its data was retained")
    if live:
        print(f"Native MobSF process is already active; configured endpoint is {LISTEN}.")
        return
    location = json.loads(LOCATION.read_text())
    home = plain_path(Path(location["tool_home"]).expanduser().absolute())
    require_storage(home)
    executable = home / "venvs/mobsf/bin/mobsf"
    if not executable.is_file() or not (home / "state/mobsf/db.sqlite3").is_file():
        raise RuntimeError("Prepare native MobSF before starting it")
    command = [str(executable), LISTEN]
    if args.offline_outbound:
        if not Path("/usr/bin/sandbox-exec").is_file():
            raise RuntimeError("The outbound-denial launcher is unavailable")
        command = ["/usr/bin/sandbox-exec", "-p", OUTBOUND_DENY_POLICY, *command]
    log = plain_path(home / "logs/mobsf-service.log")
    plain_path(PIDFILE.parent).mkdir(parents=True, exist_ok=True)
    with log.open("a") as output:
        log.chmod(0o600)
        process = subprocess.Popen(command, cwd=home, env=environment(home),
                                   stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True, umask=0o077)
    time.sleep(0.5)
    if process.poll() is not None:
        raise RuntimeError(f"MobSF exited during startup; see {log}")
    started = identity(process.pid)
    if not started:
        os.killpg(process.pid, signal.SIGTERM)
        raise RuntimeError("Could not record the MobSF process identity; startup was stopped")
    pending = plain_path(PIDFILE.with_suffix(".json.partial"))
    try:
        pending.write_text(json.dumps({"pid": process.pid, **started, "listen": LISTEN,
                                      "executable": str(executable),
                                      "outbound_policy": OUTBOUND_DENY_POLICY if args.offline_outbound else None}, indent=2) + "\n")
        pending.replace(PIDFILE)
    except OSError:
        os.killpg(process.pid, signal.SIGTERM)
        raise
    print(f"Started native MobSF process; configured endpoint: {LISTEN}; log: {log}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"MobSF service action failed: {error}", file=sys.stderr)
        sys.exit(1)
