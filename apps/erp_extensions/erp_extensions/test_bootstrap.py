"""Console-only setup for synthetic Windows tester workspaces. GPL-3.0."""
import os

import frappe


def provision_windows_test():
    from erp_extensions import local_workspace, setup
    from erp_extensions.knitting import demo, install
    from frappe.utils.password import update_password

    # Run this guard before reading credentials or changing any site data.
    local_workspace._require_console()
    passwords = {
        local_workspace.GENERAL_ACCOUNT: os.environ.get("ERP_TEST_GENERAL_PASSWORD", ""),
        local_workspace.ACCOUNT: os.environ.get("ERP_TEST_KNITTING_PASSWORD", ""),
    }
    if any(not 20 <= len(password) <= 128 for password in passwords.values()):
        raise RuntimeError("Provide both generated local tester passwords (20–128 characters).")
    setup.configure_test_site()
    install.install()
    demo.seed()
    local_workspace.provision()
    for account, password in passwords.items():
        update_password(account, password)
    frappe.db.commit()
    # API keys, secrets and passwords must never appear in bench output.
    return {"site": local_workspace.SITE, "companies": [
        local_workspace.GENERAL_COMPANY, local_workspace.COMPANY,
    ]}
