#!/bin/zsh
# Mount only the external tool image selected for this workspace.
set -eu
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "mount" ]]; then
  printf 'Usage: scripts/quality-storage.command mount\n'
  exit 0
fi
python3 - <<'PY'
import json, os, pathlib, plistlib, subprocess
location = json.loads(pathlib.Path('.local/quality/location.json').read_text())
mount = location['mountpoint']
if os.path.ismount(mount):
    print(f'Checking mounted tool storage at {mount}')
else:
    image = pathlib.Path(location['disk_image'])
    if not image.is_dir():
        raise SystemExit('Connect the infact drive first; its tool storage image is unavailable.')
    subprocess.run(['hdiutil', 'attach', str(image), '-nobrowse', '-mountpoint', mount], check=True)
details = plistlib.loads(subprocess.check_output(['diskutil', 'info', '-plist', mount], timeout=120))
if details.get('VolumeUUID') != location.get('volume_uuid'):
    raise SystemExit('A different volume is mounted at the selected path; refusing to use it.')
print('Selected external tool storage is mounted and identified.')
PY
