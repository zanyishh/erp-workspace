#!/usr/bin/env python3
"""Prepare an owner-only local launch profile without exposing credentials."""
import json,os,re,subprocess,tempfile
from pathlib import Path

root=Path(__file__).resolve().parents[1]
command=['docker','--context','colima-erp','compose','-f',str(root/'infrastructure/erpnext/compose.yaml'),
    'exec','-T','backend','bench','--site','customer-migration.localhost','execute','erp_extensions.migration.bootstrap.local_profile']
response=subprocess.run(command,capture_output=True)
if response.returncode:raise SystemExit('Customer profile preparation failed; existing local profiles were preserved.')
try:
    profile=json.loads(response.stdout.strip().splitlines()[-1])
    if (profile['id'],profile['site'],profile['origin'])!=('customer','customer-migration.localhost','http://127.0.0.1:8082'):raise ValueError()
    if not all(isinstance(profile[k],str) and re.fullmatch(r'[A-Za-z0-9_-]{12,128}',profile[k]) for k in ('key','secret')):raise ValueError()
except (KeyError,IndexError,ValueError,TypeError):raise SystemExit('Customer profile identity did not pass verification.') from None
folder=Path.home()/'Library/Containers/org.localerp.mill.customer/Data/Library/Application Support/ERP Workspace'
target=folder/'local-launch.json'
folder.mkdir(parents=True,exist_ok=True,mode=0o700)
result={'version':2,'selected_workspace':'customer','workspaces':[profile]}
with tempfile.NamedTemporaryFile(mode='w',dir=folder,delete=False) as stream:
    try:
        os.fchmod(stream.fileno(),0o600);json.dump(result,stream);stream.flush();os.fsync(stream.fileno())
        os.replace(stream.name,target)
    finally:Path(stream.name).unlink(missing_ok=True)
print('Prepared the separate knitting customer profile.')
