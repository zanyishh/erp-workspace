#!/usr/bin/env python3
"""Commit only an owned successful candidate, restoring the full pinned Config."""
import argparse
import http.client
import json
from pathlib import Path
import re
import socket
import subprocess
from urllib.parse import urlencode

BASE = 'frappe/erpnext@sha256:32145acc7f699dc598ca141018a95ebf8e56f516d4a0e76beb7287ae68b303b8'
DOCKER = ['docker', '--context', 'colima-erp']


def command(*args):
    return subprocess.check_output(DOCKER+list(args), text=True, timeout=60).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True); parser.add_argument('--owner', required=True)
    parser.add_argument('--tag', required=True); parser.add_argument('--iidfile', type=Path, required=True)
    args = parser.parse_args()
    if (not re.fullmatch('[0-9a-f]{64}', args.container) or not re.fullmatch('[0-9a-f]{32}', args.owner)
            or not re.fullmatch(r'[0-9]{8}t[0-9]{6}\.[0-9]{6}z', args.tag)):
        raise ValueError('Unexpected candidate identity')
    base = json.loads(command('image', 'inspect', '--format', '{{json .}}', BASE))
    candidate = json.loads(command('inspect', '--format', '{{json .}}', args.container))
    if (candidate['Image'] != base['Id'] or candidate['Name'] != '/erp-quality-assembly-candidate-'+args.owner
            or candidate['Config']['Labels'] != base['Config']['Labels']
            or candidate['Config'].get('Volumes') != base['Config'].get('Volumes')
            or candidate['State']['Running'] or candidate['State']['ExitCode'] != 0
            or candidate['HostConfig']['NetworkMode'] != 'none'):
        raise ValueError('Candidate is not the owned successful offline assembly')
    scratch = '/tmp/erp-quality-assembly-'+args.owner
    expected = {'/security-input': (scratch+'/inputs', False),
        '/home/frappe/frappe-bench/sites': (scratch+'/sites', True),
        '/home/frappe/frappe-bench/logs': (scratch+'/logs', True)}
    if (any(item['Type'] != 'bind' for item in candidate['Mounts'])
            or {item['Destination']: (item['Source'], item['RW']) for item in candidate['Mounts']} != expected):
        raise ValueError('Candidate does not have the exact owned scratch mounts')
    endpoint = json.loads(command('context', 'inspect', 'colima-erp', '--format', '{{json .Endpoints.docker.Host}}'))
    if not endpoint.startswith('unix://'): raise ValueError('Only the explicit local ERP Docker socket is accepted')
    version = command('version', '--format', '{{.Server.APIVersion}}')
    if not re.fullmatch(r'1\.\d+', version): raise ValueError('Unexpected Docker API version')
    class Connection(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(self.timeout); self.sock.connect(endpoint.removeprefix('unix://'))
    connection = Connection('localhost', timeout=900)
    try:
        query = urlencode({'container': args.container, 'repo': 'erp-secure-native/runtime',
                           'tag': args.tag, 'pause': 'true'})
        # Engine's documented commit body is the complete ContainerConfig.
        connection.request('POST', '/v'+version+'/commit?'+query,
            body=json.dumps(base['Config']), headers={'Content-Type': 'application/json'})
        response = connection.getresponse(); data = response.read()
        if response.status != 201: raise RuntimeError('Owned image commit failed: '+data.decode()[:1000])
        image = json.loads(data)['Id']
    finally: connection.close()
    if not re.fullmatch('sha256:[0-9a-f]{64}', image): raise ValueError('Invalid committed image ID')
    actual = json.loads(command('image', 'inspect', '--format', '{{json .Config}}', image))
    if actual != base['Config']: raise ValueError('Committed image Config differs from the pinned base')
    args.iidfile.write_text(image+'\n')
    print(json.dumps({'image_id': image, 'config_matches_base': True}))


if __name__ == '__main__': main()
