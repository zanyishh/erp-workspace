# GPL-3.0; see LICENSE. Original ERPNext/Frappe source is unchanged.
app_name = "erp_extensions"
app_title = "ERP Workspace Native Interface"
app_publisher = "ERP Workspace contributors"
app_description = "Native Flutter document interface retaining ERPNext business rules"
app_email = ""
app_license = "gpl-3.0"
required_apps = ["erpnext"]

has_permission = {"*": ["erp_extensions.knitting.permissions.has_permission", "erp_extensions.team_scope.has_permission"]}
permission_query_conditions = {"*": ["erp_extensions.knitting.permissions.query_conditions", "erp_extensions.team_scope.query_conditions"]}
auth_hooks = ["erp_extensions.team_scope.guard_request"]
doc_events = {"*": {
    "before_insert": "erp_extensions.knitting.permissions.guard_write",
    "validate": "erp_extensions.knitting.permissions.guard_write",
    "before_cancel": "erp_extensions.knitting.permissions.guard_write",
    "before_update_after_submit": "erp_extensions.knitting.permissions.guard_write",
    "on_trash": "erp_extensions.knitting.permissions.guard_write",
}, "Purchase Invoice": {"before_submit": "erp_extensions.knitting.procurement.clear_manual_receipt_account"}}
