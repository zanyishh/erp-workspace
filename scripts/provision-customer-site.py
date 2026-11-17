#!/usr/bin/env python3
"""Create/resume one empty local customer site; never reset an existing database."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SITE = "customer-migration.localhost"


def write_private(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    configuration = ROOT / ".local/customer-workspace/site-credentials.json"
    if configuration.exists():
        config = json.loads(configuration.read_text())
        if config.get("site") != SITE or not isinstance(config.get("admin_password"), str):
            raise SystemExit("Existing customer configuration has a different identity; preserved unchanged.")
    else:
        config = {"site": SITE, "admin_password": secrets.token_urlsafe(32)}
        write_private(configuration, config)
    # Secrets arrive over stdin, never command arguments or tool output.
    program = '''
import json,os,sys
from pathlib import Path
config=json.load(sys.stdin)
assert config['site']=='customer-migration.localhost'
os.chdir('/home/frappe/frappe-bench/sites')
import frappe
from frappe.installer import _new_site, install_app
site=config['site']
if not Path(site).exists():
    frappe.init(site,new_site=True)
    _new_site(None,site,db_root_username='root',db_root_password='admin',
        admin_password=config['admin_password'],install_apps=['erpnext','erp_extensions'],
        mariadb_user_host_login_scope='%')
    frappe.destroy()
frappe.init(site=site)
frappe.connect()
frappe.set_user('Administrator')
for app in ('erpnext','erp_extensions'):
    if app not in frappe.get_installed_apps(): install_app(app)
from frappe.installer import update_site_config
update_site_config('pause_scheduler',1)
update_site_config('mute_emails',1)
update_site_config('erp_customer_migration_enabled',1)
frappe.db.commit()
print('Customer site ready; no companies or customer records created by provisioning.')
frappe.destroy()
'''
    command = ["docker", "--context", "colima-erp", "compose", "-f",
               str(ROOT / "infrastructure/erpnext/compose.yaml"), "exec", "-T", "backend",
               "/home/frappe/frappe-bench/env/bin/python", "-c", program]
    log = ROOT / ".local/customer-workspace/site-provision.log"
    with log.open("ab") as stream:
        os.fchmod(stream.fileno(), 0o600)
        result = subprocess.run(command, input=json.dumps(config).encode(), stdout=stream, stderr=stream)
    if result.returncode:
        raise SystemExit("Customer site setup stopped. Existing data is retained; inspect the private provisioning log.")
    print("Separate customer site is ready; existing ERP and demo data retained.")


if __name__ == "__main__":
    main()
