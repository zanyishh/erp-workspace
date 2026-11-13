#!/usr/bin/env python3
"""Launch a fresh native Mac app per sample and retain raw frame times."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path, help="ERP Workspace.app built with tool/profile_startup.dart")
parser.add_argument("output", type=Path, help="a new sample JSON file")
parser.add_argument("--cold-shaders", action="store_true",
                    help="request a Flutter graphics cache reset (profile mode only)")
parser.add_argument("--credentials", type=Path, help="owner-readable synthetic test credentials JSON from pilot_mill_fixture.py")
args = parser.parse_args()
if args.credentials and (args.credentials.stat().st_mode & 0o077):
    parser.error("Use an owner-readable credentials file.")
if args.output.exists():
    parser.error("Choose an unused sample path.")
with tempfile.TemporaryDirectory() as temp:
    out = Path(temp, "out")
    err = Path(temp, "err")
    out.touch()
    err.touch()
    command = ["open", "-n", "-W", "--stdout", str(out), "--stderr", str(err)]
    if args.credentials:
        command += ["--stdin", str(args.credentials.resolve()), "--env", "ERP_PROFILE_CONNECTED=1"]
    if args.cold_shaders:
        command += ["--env", "FLUTTER_ENGINE_SWITCHES=1",
                    "--env", "FLUTTER_ENGINE_SWITCH_1=purge-persistent-cache"]
    command += ["--env", f"ERP_PROFILE_LAUNCH_US={time.time_ns() // 1000}", str(args.app.resolve())]
    run = subprocess.run(command, capture_output=True, text=True, timeout=75)
    output = out.read_text()
    if run.returncode or "STARTUP_OK" not in output:
        raise SystemExit(f"Native profile failed ({run.returncode})\n{output}\n{err.read_text()}\n{run.stderr}")
rows = [json.loads(line.partition("STARTUP_PROFILE ")[2]) for line in output.splitlines()
        if "STARTUP_PROFILE " in line]
if len(rows) != 4:
    raise SystemExit("Expected startup, mill, illustrated mill and register samples.")
if args.cold_shaders and rows[0].get("mode") == "release":
    raise SystemExit("Use profile mode for Flutter's graphics cache reset switch.")
workload = next(json.loads(line.partition("STARTUP_WORKLOAD ")[2])
                for line in output.splitlines() if "STARTUP_WORKLOAD " in line)
for row in rows:
    row.update(workload)
args.output.write_text(json.dumps(rows, indent=2) + "\n")
for row in rows:
    print(row["scenario"], row["elapsed_ms"], "ms, worst raster",
          max(frame["raster_ms"] for frame in row["frames"]), "ms")
