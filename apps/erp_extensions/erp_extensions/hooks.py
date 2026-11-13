# GPL-3.0; see LICENSE. Original ERPNext/Frappe source is unchanged.
app_name = "erp_extensions"
app_title = "ERP Workspace Native Interface"
app_publisher = "ERP Workspace contributors"
app_description = "Native Flutter document interface retaining ERPNext business rules"
app_email = ""
app_license = "gpl-3.0"
required_apps = ["erpnext"]

has_permission = {"*": "erp_extensions.knitting.permissions.has_permission"}
permission_query_conditions = {"*": "erp_extensions.knitting.permissions.query_conditions"}
doc_events = {"*": {
    "before_insert": "erp_extensions.knitting.permissions.guard_write",
    "validate": "erp_extensions.knitting.permissions.guard_write",
    "before_cancel": "erp_extensions.knitting.permissions.guard_write",
    "on_trash": "erp_extensions.knitting.permissions.guard_write",
}}
