#!/usr/bin/env python3
"""Local source fingerprint for rebuild/reload decisions. GPL-3.0."""
import hashlib
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
mode = sys.argv[1] if len(sys.argv) == 2 else ""
if mode == "client":
    paths = [root / "apps/erp_client" / name for name in ("lib", "assets", "macos/Runner", "macos/Runner.xcodeproj/project.pbxproj", "macos/Podfile", "pubspec.yaml", "pubspec.lock")]
elif mode == "server":
    paths = [root / "apps/erp_extensions/erp_extensions"]
else:
    raise SystemExit("Choose client or server")
files = sorted({p for path in paths for p in (path.rglob("*") if path.is_dir() else [path]) if p.is_file() and not any(part in ("__pycache__", ".DS_Store", "tests") for part in p.parts)})
digest = hashlib.sha256()
for path in files:
    digest.update(str(path.relative_to(root)).encode())
    digest.update(path.read_bytes())
print(digest.hexdigest())
