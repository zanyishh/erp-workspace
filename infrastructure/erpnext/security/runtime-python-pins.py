#!/usr/bin/env python3
"""Update the derived image's Frappe dependency contract before reinstalling it.

The official reference checkout is never a target. Installing new packages alone
would leave Frappe's distribution metadata requiring the vulnerable versions.
"""
from pathlib import Path


REPLACEMENTS = {
    '"GitPython~=3.1.45"': '"GitPython==3.2.1"',
    '"pypdf==6.19.0"': '"pypdf==6.21.4"',
}


def patched_manifest(source):
    for old, new in REPLACEMENTS.items():
        if source.count(new) == 1 and old not in source:
            continue
        if source.count(old) != 1 or new in source:
            raise ValueError(f"Unexpected dependency contract: {old}")
        source = source.replace(old, new)
    return source


if __name__ == '__main__':
    target = Path('/home/frappe/frappe-bench/apps/frappe/pyproject.toml')
    original = target.read_text()
    target.write_text(patched_manifest(original))
