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
         "exec","-T","backend","bench","--site","native-test.localhost","execute","erp_extensions.local_workspace.provision_general"]
response=subprocess.run(command,capture_output=True)
if response.returncode:
    # The console call can return secret material. Never include its raw output.
    raise SystemExit("Local workspace provisioning failed. Verify that the native test site and setup fixtures are available.")
try:
    result=json.loads(response.stdout.strip().splitlines()[-1])
    if (result["site"], result["company"], result["account"], result["industry"]) != (
        "native-test.localhost", "Meridian Trading", "local-general-owner@workspace.example.invalid", "general"
    ):
        raise ValueError()
    if not all(isinstance(result[name], str) and re.fullmatch(r"[A-Za-z0-9_-]{12,128}", result[name])
               for name in ("key", "secret")):
        raise ValueError()
    profile = {name: result[name] for name in ("site", "company", "account", "key", "secret")}
    profile.update(id="demo-general", label="General ERP", origin="http://127.0.0.1:8081")
    result = {"version": 2, "selected_workspace": "demo-general", "workspaces": [profile]}
except (IndexError,KeyError,TypeError,ValueError):
    raise SystemExit("The isolated site did not return the expected workspace identity.") from None
folder=Path.home()/"Library/Containers/org.localerp.erpClient/Data/Library/Application Support/ERP Workspace"
folder.mkdir(parents=True,exist_ok=True,mode=0o700)
target=folder/"general-launch.json"
with tempfile.NamedTemporaryFile(mode="w",dir=folder,delete=False) as f:
    try:
        os.fchmod(f.fileno(),0o600)
        json.dump(result,f)
        f.flush()
        os.fsync(f.fileno())
        os.replace(f.name,target)
    finally:
        Path(f.name).unlink(missing_ok=True)
print("Prepared the General ERP workspace for Meridian Trading.")
