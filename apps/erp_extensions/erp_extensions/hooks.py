# GPL-3.0; see LICENSE. Original ERPNext/Frappe source is unchanged.
app_name = "erp_extensions"
app_title = "ERP Workspace Native Interface"
app_publisher = "ERP Workspace contributors"
app_description = "Native Flutter document interface retaining ERPNext business rules"
app_email = ""
app_license = "gpl-3.0"
required_apps = ["erpnext"]
after_install = ["erp_extensions.invoices.install", "erp_extensions.operations.install"]
after_migrate = ["erp_extensions.invoices.install", "erp_extensions.operations.install", "erp_extensions.migration.install.install", "erp_extensions.migration.finance.install", "erp_extensions.migration.settlements.install"]

extend_doctype_class = {name: ["erp_extensions.migration.finance.FinanceBookMixin"]
    for name in ("Journal Entry", "Sales Invoice", "Purchase Invoice", "Payment Entry")}

has_permission = {"*": ["erp_extensions.knitting.permissions.has_permission", "erp_extensions.team_scope.has_permission", "erp_extensions.migration.service.has_permission", "erp_extensions.migration.finance.has_permission"]}
permission_query_conditions = {"*": ["erp_extensions.knitting.permissions.query_conditions", "erp_extensions.team_scope.query_conditions", "erp_extensions.migration.service.query_conditions", "erp_extensions.migration.finance.query_conditions"]}
auth_hooks = ["erp_extensions.team_scope.guard_request"]
doc_events = {"*": {
    "before_insert": ["erp_extensions.knitting.permissions.guard_write", "erp_extensions.migration.service.guard_write"],
    "validate": ["erp_extensions.knitting.permissions.guard_write", "erp_extensions.migration.service.guard_write"],
    "before_cancel": ["erp_extensions.knitting.permissions.guard_write", "erp_extensions.migration.service.guard_write"],
    "before_update_after_submit": ["erp_extensions.knitting.permissions.guard_write", "erp_extensions.migration.service.guard_write"],
    "on_trash": ["erp_extensions.knitting.permissions.guard_write", "erp_extensions.migration.service.guard_write"],
}, "Purchase Invoice": {"before_submit": "erp_extensions.knitting.procurement.clear_manual_receipt_account"},
"Historical Finance Book Binding": {key: "erp_extensions.migration.finance.guard_book_binding"
    for key in ("before_insert", "validate", "on_trash")},
"Historical Settlement Binding": {key: "erp_extensions.migration.settlements.guard_write"
    for key in ("before_insert", "validate", "on_trash")}}
