#!/usr/bin/env python3
"""Provision a Mac's local-only evaluation account without logging its token."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
command=["docker","--context","colima-erp","compose","-f",str(root/"infrastructure/erpnext/compose.yaml"),
         "exec","-T","backend","bench","--site","native-test.localhost","execute","erp_extensions.local_workspace.provision"]
response=subprocess.run(command,capture_output=True)
if response.returncode:
    # The console call can return secret material. Never include its raw output.
    raise SystemExit("Local workspace provisioning failed. Verify that the native test site and setup fixtures are available.")
try:
    result=json.loads(response.stdout.strip().splitlines()[-1])
    expected = [("Meridian Trading", "local-general-owner@workspace.example.invalid", "general"),
                ("Kaveri Loomworks", "local-owner@workspace.example.invalid", "knitting")]
    workspaces = result["workspaces"]
    if not isinstance(workspaces, list) or len(workspaces) != len(expected):
        raise ValueError()
    for row, identity in zip(workspaces, expected):
        if (row["company"], row["account"], row["industry"]) != identity or row["site"] != "native-test.localhost":
            raise ValueError()
        if not all(isinstance(row[name], str) and re.fullmatch(r"[A-Za-z0-9_-]{12,128}", row[name]) for name in ("key", "secret")):
            raise ValueError()
    if any(result[name] != workspaces[0][name] for name in ("site", "company", "account", "key", "secret", "industry")):
        raise ValueError()
except (IndexError,KeyError,TypeError,ValueError):
    raise SystemExit("The isolated site did not return the expected workspace identity.") from None
folder=Path.home()/"Library/Containers/org.localerp.erpClient/Data/Library/Application Support/ERP Workspace"
folder.mkdir(parents=True,exist_ok=True,mode=0o700)
target=folder/"local-launch.json"
if target.exists():
    existing=json.loads(target.read_text())
    if existing.get('version')==2:
        from local_launch_profiles import merge, upgrade
        result=merge(existing,upgrade(result)['workspaces'])
with tempfile.NamedTemporaryFile(mode="w",dir=folder,delete=False) as f:
    try:
        os.fchmod(f.fileno(),0o600)
        json.dump(result,f)
        f.flush()
        os.fsync(f.fileno())
        os.replace(f.name,target)
    finally:
        Path(f.name).unlink(missing_ok=True)
print("Prepared separate General ERP (Meridian Trading) and Knitting (Kaveri Loomworks) demo companies for this Mac.")
