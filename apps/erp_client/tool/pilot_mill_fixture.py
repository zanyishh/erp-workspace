"""Provision one company-scoped mill rehearsal user on native-test.localhost."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts/quality'))
from native_target import python_command


PROVISION = """
import os
import frappe

os.chdir("/home/frappe/frappe-bench/sites")
frappe.init(site="native-test.localhost", sites_path=".")
frappe.connect()
frappe.set_user("Administrator")
company = "ERP Native Verification"
if frappe.local.site != "native-test.localhost" or not frappe.db.exists("Company", company):
    raise RuntimeError("This fixture requires the isolated native verification site.")
frappe.get_doc({
    "doctype": "User", "email": identity["user"], "first_name": "Mill Pilot",
    "user_type": "System User", "send_welcome_email": 0, "new_password": identity["password"],
    "roles": [{"role": role} for role in ("Knitting Manager", "Accounts User", "Sales User", "Stock User")],
}).insert()
frappe.get_doc({
    "doctype": "User Permission", "user": identity["user"], "allow": "Company",
    "for_value": company, "is_default": 1, "apply_to_all_doctypes": 1,
}).insert()
frappe.db.commit()
"""


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Pass a new output directory under the project's ignored .local folder.")
    root = Path(__file__).resolve().parents[3]
    folder = Path(sys.argv[1]).resolve()
    if not folder.is_relative_to(root / ".local"):
        raise SystemExit("Store pilot credentials in the project's ignored .local folder.")
    folder.mkdir(parents=True, exist_ok=True)
    output = folder / "mill-credentials.json"
    identity = {
        "user": f"mill-pilot-{secrets.token_hex(6)}@example.invalid",
        "password": secrets.token_urlsafe(27),
    }
    with os.fdopen(os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
        json.dump(identity, stream)
    command = python_command('-')
    result = subprocess.run(command, cwd=root, input=f"identity = {identity!r}\n{PROVISION}",
                            text=True, capture_output=True)
    if result.returncode:
        raise SystemExit((result.stdout + result.stderr).replace(identity["password"], "<redacted>"))
    print(f"Created the mill rehearsal user {identity['user']}.")


if __name__ == "__main__":
    main()
