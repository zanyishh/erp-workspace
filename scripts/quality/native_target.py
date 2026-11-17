#!/usr/bin/env python3
"""Resolve the active, localhost-only synthetic deployment before test writes."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT/'.local/quality/secure-native'
SITE = 'native-test.localhost'
DOCKER = ['docker','--context','colima-erp']
PYTHON = '/home/frappe/frappe-bench/env/bin/python'


def _query(*arguments):
    return subprocess.check_output(DOCKER+list(arguments), text=True, stderr=subprocess.PIPE, timeout=30).strip()


def _inspect_service(project, service):
    identifiers = _query('ps','-q','--no-trunc','--filter','label=com.docker.compose.project='+project,
                         '--filter','label=com.docker.compose.service='+service).split()
    if len(identifiers)!=1 or not re.fullmatch(r'[0-9a-f]{64}',identifiers[0]):
        raise RuntimeError('Require exactly one running synthetic '+service)
    template = '{"id":{{json .Id}},"image":{{json .Image}},"labels":{{json .Config.Labels}},"running":{{json .State.Running}},"ports":{{json .HostConfig.PortBindings}}}'
    return json.loads(_query('container','inspect','--format',template,identifiers[0]))


def _state(name):
    path=STATE/name
    if STATE.is_symlink() or path.is_symlink():
        raise RuntimeError('Refusing linked synthetic deployment state')
    value=json.loads(path.read_text())
    if value.get('project')!='erp-secure-native' or value.get('site')!=SITE:
        raise RuntimeError('Unexpected synthetic deployment scope')
    return value


def selected_backend():
    project, configuration, image = 'erp-baseline','compose.yaml',None
    if STATE.is_symlink() or (STATE/'activation.json').is_symlink():
        raise RuntimeError('Refusing linked synthetic deployment state')
    if (STATE/'activation.json').exists():
        activation=_state('activation.json')
        if activation.get('status')!='active':
            raise RuntimeError('Synthetic security deployment is not active; no fallback is allowed')
        prepared=_state('prepared.json')
        image=prepared.get('images',{}).get('ERP_SECURE_IMAGE','')
        if not re.fullmatch(r'sha256:[0-9a-f]{64}',image):
            raise RuntimeError('Require the prepared immutable candidate image')
        project, configuration='erp-secure-native','compose.security-native.yaml'
    expected_config=str(ROOT/'infrastructure/erpnext'/configuration)
    selected={}
    for service in ('native-test-backend','native-test-frontend'):
        item=_inspect_service(project,service)
        labels=item.get('labels') or {}
        if (not item.get('running') or not re.fullmatch(r'[0-9a-f]{64}',item.get('id',''))
                or labels.get('com.docker.compose.project')!=project
                or labels.get('com.docker.compose.service')!=service
                or labels.get('com.docker.compose.project.config_files')!=expected_config):
            raise RuntimeError('Container differs from the exact synthetic deployment scope')
        if image and item.get('image')!=image:
            raise RuntimeError('Candidate image differs from the prepared image')
        if service=='native-test-frontend':
            if item.get('ports')!={'8080/tcp':[{'HostIp':'127.0.0.1','HostPort':'8081'}]}:
                raise RuntimeError('Synthetic frontend must publish only localhost8081')
        else:
            selected={**item,'project':project,'site':SITE}
    return selected


def python_command(*arguments):
    selected=selected_backend()
    return DOCKER+['exec','-i','-e','NATIVE_TEST_SITE='+SITE,selected['id'],PYTHON,*arguments]


def admin_password():
    selected=selected_backend()
    if selected['project']=='erp-secure-native':
        path=STATE/'secrets/site-admin'
        if path.is_symlink() or path.parent.is_symlink():
            raise RuntimeError('Refusing linked synthetic credentials')
        password=path.read_text().strip()
        if not password:
            raise RuntimeError('Synthetic administrator credential is missing')
        return password
    return os.environ.get('ERP_LOCAL_PILOT_PASSWORD','admin')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site',choices=[SITE],required=True)
    parser.parse_args()
    command=python_command('-m','unittest','discover','-s',
                           '/home/frappe/frappe-bench/apps/erp_extensions/erp_extensions/tests',
                           '-p','test_*.py','-v')
    return subprocess.run(command,cwd=ROOT,check=False).returncode


if __name__=='__main__':
    raise SystemExit(main())
