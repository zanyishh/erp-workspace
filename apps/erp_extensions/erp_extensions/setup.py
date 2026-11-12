"""Repeatable setup for the isolated local verification site only. GPL-3.0."""
import frappe

TEST_SITE = "native-test.localhost"
TEST_COMPANY = "ERP Native Verification"


def configure_test_site():
    if frappe.local.site != TEST_SITE:
        raise RuntimeError("This setup is restricted to native-test.localhost")
    if not frappe.db.exists("Company", TEST_COMPANY):
        from erpnext.setup.setup_wizard.operations.install_fixtures import install, install_company, install_defaults
        args = frappe._dict(company_name=TEST_COMPANY, company_abbr="NTEST", currency="INR",
            country="India", chart_of_accounts="Standard", fy_start_date="2026-04-01",
            fy_end_date="2027-03-31", fiscal_year="2026-2027")
        install("India")
        install_company(args)
        install_defaults(args)
    settings = frappe.get_doc("Print Settings")
    settings.pdf_generator = "wkhtmltopdf"
    settings.save()
    # The renderer must reach this site through the internal test gateway for assets.
    from frappe.installer import update_site_config
    update_site_config("host_name", "http://native-test-frontend:8080")
    frappe.conf.host_name = "http://native-test-frontend:8080"
    frappe.db.commit()
    return {"site":TEST_SITE,"company":TEST_COMPANY,"pdf_generator":"wkhtmltopdf"}
