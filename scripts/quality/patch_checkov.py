#!/usr/bin/env python3
"""Build a pinned local Checkov wheel using cryptography for public-key checks.

The upstream wheel and notices are retained. This replaces its two verification
adapters and dependency metadata; it does not disable external-check signatures.
"""
import argparse
import base64
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile


SOURCE_URL = "https://files.pythonhosted.org/packages/0d/1e/c8b0431a4318d964bb9a0c509d1f20eefb8fb90dfceb2206c88485aa0ada/checkov-3.4.5-py3-none-any.whl"
SOURCE_SHA256 = "64210c48a957ecb85dfb38057e00faa150b5e46e76b08e710d29beb687b7ced2"
VERSION = "3.4.5+erp.1"
CRYPTOGRAPHY_VERSION = "50.0.2"
PREFIX = "checkov/common/external_checks/verification/"
MODULE_HASHES = {
    "keys.py": "8c59677d0899b74ebc86c2d474858eb7d982790e08ba9d9e8fbfbec74271cb84",
    "verifier.py": "b79c50271f9354b840ac7b64dea315258294342a99ef6817954a4eeb07d43dba",
}


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("Reviewed Checkov source no longer matches the patch")
    return text.replace(old, new, 1)


def patch_module(name, data):
    if hashlib.sha256(data).hexdigest() != MODULE_HASHES[name]:
        raise ValueError(f"Unexpected source hash: {name}")
    text = data.decode()
    start = text.index("# ecdsa ships no py.typed marker;")
    end = text.index("\n\nfrom .", start)
    if name == "keys.py":
        text = text[:start] + "from cryptography.exceptions import UnsupportedAlgorithm\nfrom cryptography.hazmat.primitives import serialization\nfrom cryptography.hazmat.primitives.asymmetric import ec" + text[end:]
        text = text.replace("    UnexpectedDER,\n", "    UnsupportedAlgorithm,\n").replace("    MalformedPointError,\n", "")
        text = text.replace("VerifyingKey", "ec.EllipticCurvePublicKey")
        text = replace_once(text, "if vk.curve != NIST256p:", "if not isinstance(vk, ec.EllipticCurvePublicKey) or not isinstance(vk.curve, ec.SECP256R1):")
        text = replace_once(text, "vk = ec.EllipticCurvePublicKey.from_pem(pem)", "vk = serialization.load_pem_public_key(pem)")
        text = replace_once(text, "spki_der = validated.to_der()", "spki_der = validated.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)")
    else:
        text = text[:start] + "from cryptography.exceptions import InvalidSignature\nfrom cryptography.hazmat.primitives import hashes\nfrom cryptography.hazmat.primitives.asymmetric import ec, utils" + text[end:]
        text = replace_once(text, "import hashlib\n", "")
        text = replace_once(text, "_SECP256R1_N = NIST256p.order", "_SECP256R1_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551")
        text = text.replace("    BadSignatureError,\n", "    InvalidSignature,\n").replace("    UnexpectedDER,\n", "").replace("    MalformedPointError,\n", "")
        text = replace_once(text, "sigdecode_der(sig_der, _SECP256R1_N)", "utils.decode_dss_signature(sig_der)")
        text = replace_once(text, "sig_der, payload, hashfunc=hashlib.sha256, sigdecode=sigdecode_der,", "sig_der, payload, ec.ECDSA(hashes.SHA256()),")
    compile(text, name, "exec")
    return text.encode()


def build_wheel(source, destination):
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Official Checkov wheel checksum mismatch")
    old_info = "checkov-3.4.5.dist-info"
    new_info = f"checkov-{VERSION}.dist-info"
    with zipfile.ZipFile(source) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
        modes = {info.filename.replace(old_info, new_info).replace("checkov-3.4.5.data/", f"checkov-{VERSION}.data/"): info.external_attr for info in archive.infolist()}
    if any(name.endswith(("RECORD.jws", "RECORD.p7s")) for name in files):
        raise ValueError("Unexpected signed wheel; patch process needs review")
    for name in MODULE_HASHES:
        files[PREFIX + name] = patch_module(name, files[PREFIX + name])
    version = files["checkov/version.py"].decode()
    files["checkov/version.py"] = replace_once(version, "version = '3.4.5'", f"version = '{VERSION}'").encode()
    metadata = files[f"{old_info}/METADATA"].decode()
    metadata = replace_once(metadata, "Version: 3.4.5\n", f"Version: {VERSION}\n")
    dependency_lines = [line for line in metadata.splitlines(keepends=True) if line.startswith("Requires-Dist: ecdsa")]
    if len(dependency_lines) != 1:
        raise ValueError("Expected exactly one ecdsa requirement")
    metadata = replace_once(metadata, dependency_lines[0], f"Requires-Dist: cryptography=={CRYPTOGRAPHY_VERSION}\n")
    files[f"{old_info}/METADATA"] = metadata.encode()
    del files[f"{old_info}/RECORD"]
    files = {name.replace(old_info, new_info).replace("checkov-3.4.5.data/", f"checkov-{VERSION}.data/"): data for name, data in files.items()}
    files[f"{new_info}/local_security_patch.json"] = (json.dumps({
        "upstream": SOURCE_URL, "upstream_sha256": SOURCE_SHA256,
        "local_version": VERSION, "changed_on": "2026-11-16",
        "purpose": "Replace public-key ECDSA verification adapters with cryptography; remove unused private-key-capable python-ecdsa implementation.",
        "changed_modules": MODULE_HASHES, "original_licenses_preserved": True,
        "advisory": "https://github.com/tlsfuzzer/python-ecdsa/security/advisories/GHSA-wj6h-64fc-37mp",
        "note": "Upstream use was verification-only, explicitly unaffected by the advisory; package removal eliminates the affected implementation rather than suppressing its scanner finding.",
    }, indent=2) + "\n").encode()
    rows = [[name, "sha256=" + base64.urlsafe_b64encode(hashlib.sha256(data).digest()).decode().rstrip("="), str(len(data))] for name, data in sorted(files.items())]
    record_path = f"{new_info}/RECORD"
    rows.append([record_path, "", ""])
    record = io.StringIO(newline="")
    csv.writer(record).writerows(rows)
    files[record_path] = record.getvalue().encode()
    # Fixed archive metadata makes the local derivative reproducible.
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 16, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = modes.get(name, 0o644 << 16)
            archive.writestr(info, data)
    return {"wheel": str(destination), "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "source_sha256": SOURCE_SHA256, "version": VERSION}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool-home", required=True, type=Path)
    args = parser.parse_args()
    if not args.tool_home.is_absolute():
        parser.error("--tool-home must be absolute")
    folder = args.tool_home / "wheels"
    folder.mkdir(parents=True, exist_ok=True)
    source = folder / "checkov-3.4.5-py3-none-any.whl"
    if not source.exists():
        with tempfile.TemporaryDirectory(prefix="checkov-download-", dir=folder) as temporary:
            download = Path(temporary) / source.name
            subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--max-time", "120", "--output", str(download), SOURCE_URL], check=True)
            if hashlib.sha256(download.read_bytes()).hexdigest() != SOURCE_SHA256:
                raise ValueError("Downloaded Checkov checksum mismatch")
            download.replace(source)
    destination = folder / f"checkov-{VERSION}-py3-none-any.whl"
    result = build_wheel(source, destination)
    (folder / "checkov-security-patch.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
