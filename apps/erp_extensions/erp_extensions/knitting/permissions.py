"""Pack permissions apply to native commands and generic Frappe routes alike."""
from contextlib import contextmanager
from contextvars import ContextVar

import frappe

CAPABILITIES = {
    "Knitting Manager": {"overview", "jobs", "new_job", "lifecycle", "materials", "production", "quality", "planning", "delivery", "billing", "financial_read", "factory", "reports", "configure"},
    "Knitting Operator": {"overview", "jobs", "production", "materials"},
    "Knitting Checker": {"overview", "jobs", "quality"},
    "Knitting Planner": {"overview", "jobs", "planning", "factory", "reports"},
    "Knitting Accountant": {"overview", "jobs", "delivery", "billing", "financial_read", "reports"},
}
FINANCIAL_EVENTS = ("invoice", "credit_invoice", "bill_yarn", "create_yarn_order", "set_lot_charge", "deliver", "deliver_batch", "migration_delivery_reference", "revise_job", "payment", "subcontract_bill", "estimate", "create_estimate", "cost")


def companies(user=None):
    user = user or frappe.session.user
    if user == "Guest" or not frappe.has_permission("Company", "read", user=user):
        return []
    return frappe.get_list("Company", fields=["name", "abbr", "default_currency"],
                           order_by="name", limit=1000, user=user)


def capabilities(user=None):
    user = user or frappe.session.user
    roles = set(frappe.get_roles(user))
    if user == "Administrator" or "System Manager" in roles:
        return set(CAPABILITIES["Knitting Manager"])
    return set().union(*(values for role, values in CAPABILITIES.items() if role in roles))


def profile(company, *, current=False):
    if not frappe.db.exists("DocType", "Workspace Industry Setup"):
        return None
    return frappe.db.get_value("Workspace Industry Setup", {"company": company}, ["name", "state", "settings", "revision"], as_dict=True, for_update=current)


def company_allowed(company, user=None):
    return company in {c.name for c in companies(user)}


def require(company, capability, history=False, *, current=False):
    if not company_allowed(company) or capability not in capabilities():
        frappe.throw("This account cannot perform that action in this business.", frappe.PermissionError)
    setup = profile(company, current=current)
    if not setup or not history and setup.state not in ("Active", "Closing"):
        frappe.throw("Knitting is not active for this business.", frappe.PermissionError)
    if setup.state == "Closing" and capability == "new_job":
        frappe.throw("This business is closing existing knitting work; new jobs are disabled.", frappe.PermissionError)
    return setup


@contextmanager
def service_write():
    previous = frappe.flags.get("knitting_service_write")
    frappe.flags.knitting_service_write = True
    try:
        yield
    finally:
        frappe.flags.knitting_service_write = previous


def is_pack(doctype):
    return doctype == "Workspace Industry Setup" or doctype.startswith("Knitting ")


def visible_type(doctype, company=None):
    if not is_pack(doctype):
        return True
    caps = capabilities()
    if doctype == "Workspace Industry Setup":
        return "configure" in caps
    if "jobs" not in caps:
        return False
    for item in companies():
        if company and item.name != company:
            continue
        setup = profile(item.name)
        if setup and (setup.state in ("Active", "Closing") or
                      frappe.db.exists("Knitting Job", {"company": item.name})):
            return True
    return False


def guard_write(doc, method=None):
    if not is_pack(doc.doctype):
        if doc.doctype in ("Stock Entry", "Sales Invoice", "Delivery Note", "Purchase Invoice", "Purchase Order", "Purchase Receipt", "Quotation"):
            current = doc.get("knitting_event") or doc.get("knitting_job")
            previous = frappe.db.get_value(doc.doctype, doc.name, "knitting_event") if doc.meta.has_field("knitting_event") and doc.name and not doc.is_new() else None
            if (current or previous) and not frappe.flags.get("knitting_service_write"):
                frappe.throw("Review this source-linked document through its knitting workflow.", frappe.PermissionError)
            if doc.doctype == "Sales Invoice" and current and method == "validate":
                from .posting import validate_tax_choice
                validate_tax_choice(doc)
        return
    if not frappe.flags.get("knitting_service_write"):
        frappe.throw("Use the reviewed knitting workflow to change this record.", frappe.PermissionError)
    if not company_allowed(doc.company):
        frappe.throw("The record belongs to another business.", frappe.PermissionError)


def has_permission(doc, ptype, user=None, **kwargs):
    if not is_pack(doc.doctype):
        return True
    if not company_allowed(doc.company, user):
        return False
    if doc.doctype == "Workspace Industry Setup":
        return "configure" in capabilities(user)
    if not profile(doc.company) or "jobs" not in capabilities(user):
        return False
    if not source_scope(doc, user, _creating_batch=ptype == "create" and frappe.flags.get("knitting_service_write")):
        return False
    if ptype not in ("read", "print", "export", "report", "select"):
        return bool(frappe.flags.get("knitting_service_write"))
    if doc.doctype == "Knitting Event" and doc.kind in FINANCIAL_EVENTS:
        return "financial_read" in capabilities(user)
    return True


_snapshot_links = ContextVar("knitting_snapshot_links", default=None)


@contextmanager
def snapshot_link_checks():
    """Share link decisions within one read-only snapshot, including list hooks."""
    if _snapshot_links.get() is not None:
        yield
        return
    token = _snapshot_links.set({})
    try:
        yield
    finally:
        _snapshot_links.reset(token)


def readable_link_names(doctype, user, name=None):
    # An unreadable linked type excludes its source rows. Access to other rows is independent.
    cache = _snapshot_links.get()
    key = (doctype, user, None if cache is not None else name)
    if cache is not None and key in cache:
        if name is None:
            return cache[key]
        return [name] if name in cache[key] else []
    names = []
    if frappe.has_permission(doctype, "read", user=user):
        names = frappe.get_list(doctype, filters={"name": name} if name is not None and cache is None else {},
                                pluck="name", limit=1 if name is not None and cache is None else 0, user=user)
    if cache is not None:
        cache[key] = frozenset(names)
        if name is not None:
            return [name] if name in cache[key] else []
    return names


def link_visible(doctype, name, user=None):
    user = user or frappe.session.user
    if not name or user == "Administrator":
        return True
    return bool(readable_link_names(doctype, user, name))


SOURCE_LINKS = (("warehouse", "Warehouse"), ("customer", "Customer"), ("party", "Customer"),
    ("machine", "Knitting Machine"),
    ("job", "Knitting Job"), ("target_job", "Knitting Job"), ("lot", "Knitting Material Lot"),
    ("roll", "Knitting Roll"), ("batch", "Knitting Fabric Batch"), ("billing_customer", "Customer"))
JSON_LINKS = {'customer':'Customer', 'party':'Customer', 'supplier':'Supplier',
    'machine':'Knitting Machine',
    'warehouse':'Warehouse', 'target_warehouse':'Warehouse', 'lot':'Knitting Material Lot',
    'source_lot':'Knitting Material Lot', 'roll':'Knitting Roll', 'parent_roll':'Knitting Roll',
    'batch':'Knitting Fabric Batch', 'job':'Knitting Job', 'target_job':'Knitting Job',
    'invoice':'Sales Invoice', 'quotation':'Quotation', 'purchase_order':'Purchase Order'}


def _json_links(value):
    if isinstance(value, dict):
        for field, target in JSON_LINKS.items():
            if value.get(field):
                yield target, value[field]
        for child in value.values():
            yield from _json_links(child)
    elif isinstance(value, list):
        for child in value:
            yield from _json_links(child)


def _source_rows(doctype, filters):
    """Load exactly the fields inspected by source_scope, without per-row Documents."""
    meta = frappe.get_meta(doctype)
    fields = ["name"] + [field for field, _ in SOURCE_LINKS if meta.has_field(field)]
    if doctype == "Knitting Event":
        fields += ["company", "kind", "payload", "result", "voucher_type", "voucher_name"]
    elif doctype == "Knitting Fabric Batch":
        fields += ["company", "production", "source_record"]
    elif doctype == "Knitting Roll":
        fields += ["company", "production"]
    rows = frappe.get_all(doctype, filters=filters, fields=fields)
    pending = {}
    cache = _snapshot_links.get()
    for row in rows:
        row["doctype"] = doctype
        if doctype == "Knitting Event":
            for field in ("payload", "result"):
                row[field] = frappe.parse_json(row.get(field) or '{}')
                for target, name in _json_links(row[field]):
                    if cache is not None and ("exists", target, name) not in cache:
                        pending.setdefault(target, set()).add(name)
    for target, names in pending.items():
        existing = set(frappe.get_all(target, filters={"name": ["in", list(names)]}, pluck="name"))
        for name in names:
            cache[("exists", target, name)] = name in existing
    if doctype in ("Knitting Fabric Batch", "Knitting Roll") and cache is not None:
        _batch_production_sources(rows)
    return rows


def _link_exists(doctype, name):
    cache = _snapshot_links.get()
    key = ("exists", doctype, name)
    if cache is not None and key in cache:
        return cache[key]
    return frappe.db.exists(doctype, name)


def _batch_production_sources(rows):
    cache = _snapshot_links.get().setdefault("batch_production_sources", {})
    missing = {row.get("production") for row in rows if row.get("production")} - cache.keys()
    if missing:
        cache.update({name: None for name in missing})
        cache.update({row.name: row for row in _source_rows("Knitting Event", {"name": ["in", list(missing)]})})
    return cache


def _batch_production_scope(doc, user):
    if not doc.get("production"):
        return bool(doc.get("source_record"))  # Only imported balances lack production provenance.
    source = _batch_production_sources([doc]).get(doc.production)
    result = frappe.parse_json(source.result or '{}') if source else {}
    if not isinstance(result, dict):
        return False
    snapshot = result.get("batch_snapshot") or {}
    if (not source or source.kind != "produce_batch" or source.company != doc.company or source.job != doc.job
            or result.get("batch") != doc.name or not isinstance(snapshot, dict)
            or snapshot.get("name") != doc.name or snapshot.get("production") != source.name
            or snapshot.get("job") != doc.job):
        return False
    # Aggregate production consumes lots, never another output batch (including cycles).
    if any(target == "Knitting Fabric Batch" and name != doc.name
            for value in (frappe.parse_json(source.payload or '{}'), result) for target, name in _json_links(value)):
        return False
    # Only the verified output's self-reference is exempt; every input remains scoped.
    return frappe.has_permission("Knitting Event", "read", user=user) and source_scope(source, user, _produced_batch=doc.name)


@snapshot_link_checks()
def source_scope(doc, user=None, *, _produced_batch=None, _creating_batch=False):
    """Apply linked record restrictions even when private JSON is projected by a service."""
    from .operators import visible
    from .machines import visible as machine_visible
    if not _creating_batch and (not visible(doc, user) or not machine_visible(doc, user)):
        return False
    if (user or frappe.session.user) == "Administrator":
        return True
    for field, doctype in SOURCE_LINKS:
        if doc.get(field) and not link_visible(doctype, doc.get(field), user):
            return False
    if doc.doctype == "Knitting Fabric Batch" and not _creating_batch and not _batch_production_scope(doc, user):
        return False
    if doc.doctype == 'Knitting Event':
        if doc.get("kind") == "produce_batch" and doc.get("result") and frappe.flags.get("knitting_service_write"):
            # The command checks its completed result before the event's save reaches SQL.
            _snapshot_links.get().setdefault("batch_production_sources", {})[doc.name] = doc
        for raw in (doc.payload, doc.result):
            value = frappe.parse_json(raw or '{}')
            def allowed(value):
                if isinstance(value, list):
                    return all(allowed(v) for v in value)
                if not isinstance(value, dict):
                    return True
                voucher_type, voucher = value.get("voucher_type"), value.get("voucher")
                if voucher and voucher_type in ("Stock Entry", "Sales Invoice", "Delivery Note", "Purchase Invoice",
                                                "Purchase Order", "Purchase Receipt", "Quotation"):
                    if not link_visible(voucher_type, voucher, user):
                        return False
                for key, target in JSON_LINKS.items():
                    name = value.get(key)
                    if target == "Knitting Fabric Batch" and name == _produced_batch:
                        continue
                    if name and _link_exists(target, name) and not link_visible(target, name, user):
                        return False
                # Aggregate production stores a roll count; roll-based events store IDs.
                for name in value.get('rolls', []) if isinstance(value.get('rolls'), list) else []:
                    if not link_visible('Knitting Roll', name, user):
                        return False
                return all(allowed(v) for v in value.values() if isinstance(v, (dict, list)))
            if not allowed(value):
                return False
        if doc.voucher_type and doc.voucher_name and not link_visible(doc.voucher_type, doc.voucher_name, user):
            return False
    return True


class SourceReconciliationError(frappe.PermissionError):
    def __init__(self, jobs):
        super().__init__("This reconciliation includes source records outside your access. Ask a manager with full source access.")
        self.jobs = jobs


@snapshot_link_checks()
def require_event_sources(events):
    """Read projections need every linked source, without requiring commercial event visibility."""
    restricted = set()
    names = {row.name for row in events}
    if not names:
        return
    if frappe.session.user == "Administrator" or frappe.flags.get("knitting_service_write"):
        from .operators import visible
        from .machines import visible as machine_visible
        rows = events if all(isinstance(row, dict) and {'company', 'payload', 'result'} <= row.keys() for row in events) else frappe.get_all(
            'Knitting Event', filters={'name': ['in', list(names)]}, fields=['name', 'company', 'job', 'payload', 'result'])
        if {row.name for row in rows} != names:
            raise SourceReconciliationError(set())
        for row in rows:
            if not visible(frappe._dict({**row, 'doctype': 'Knitting Event'})) or not machine_visible(frappe._dict({**row, 'doctype': 'Knitting Event'})):
                raise SourceReconciliationError({row.job} if row.get('job') else set())
        return
    source_events = _source_rows("Knitting Event", {"name": ["in", list(names)]})
    if {row.name for row in source_events} != names:
        raise SourceReconciliationError(set())
    from .operators import visible
    from .machines import visible as machine_visible
    for row in source_events:
        if not visible(row) or not machine_visible(row):
            raise SourceReconciliationError({row.job} if row.get('job') else set())
    for event in source_events:
        if not source_scope(event):
            restricted.update(job for job in (event.job, event.target_job) if job)
            # Company-level events have no job but must still fail a report.
            restricted.add(None)
    if restricted:
        raise SourceReconciliationError(restricted - {None})


@snapshot_link_checks()
def require_aggregate_scope(company, job=None):
    """A reconciliation is either complete and authorised, or unavailable.

    Silently excluding a restricted godown would turn a correct ledger into
    an incorrect available balance. Internal authoritative reads remain full.
    """
    if frappe.session.user == "Administrator":
        return
    for doctype in ("Knitting Job", "Knitting Ledger Entry", "Knitting Roll", "Knitting Fabric Batch", "Knitting Subcontract"):
        filters = {"company": company, **({"name" if doctype == "Knitting Job" else "job": job} if job else {})}
        for doc in _source_rows(doctype, filters):
            if not source_scope(doc) or not link_visible(doctype, doc.name):
                frappe.throw("This reconciliation includes source records outside your access. Ask a manager with full source access.", frappe.PermissionError)


def require_event_scope(event):
    event.check_permission("read")
    if not source_scope(event):
        frappe.throw('This action includes source records outside your access.', frappe.PermissionError)
    if event.job:
        require_aggregate_scope(event.company, event.job)
    if event.target_job:
        require_aggregate_scope(event.company, event.target_job)
    for row in frappe.get_all("Knitting Ledger Entry", filters={"event": event.name}, fields=["name"]):
        frappe.get_doc("Knitting Ledger Entry", row.name).check_permission("read")


@snapshot_link_checks()
def query_conditions(user=None, doctype=None):
    if not doctype or not is_pack(doctype):
        return ""
    caps = capabilities(user)
    if not caps or doctype == "Workspace Industry Setup" and "configure" not in caps:
        return "1=0"
    allowed = [c.name for c in companies(user) if profile(c.name)]
    if not allowed:
        return "1=0"
    condition = f"`tab{doctype}`.`company` in ({','.join(frappe.db.escape(c) for c in allowed)})"
    if doctype == "Knitting Event" and "financial_read" not in caps:
        condition += " and `kind` not in (" + ",".join(frappe.db.escape(k) for k in FINANCIAL_EVENTS) + ")"
    for field, target in SOURCE_LINKS:
        if frappe.get_meta(doctype).has_field(field):
            names = readable_link_names(target, user or frappe.session.user)
            values = ",".join(frappe.db.escape(n) for n in names) or "NULL"
            condition += f" and (coalesce(`tab{doctype}`.`{field}`, '')='' or `tab{doctype}`.`{field}` in ({values}))"
    if doctype in ('Knitting Event', 'Knitting Fabric Batch'):
        # JSON sources are not covered by Frappe's Link-field User Permission
        # joins. Generic Desk/API lists must enforce the same source checks.
        filters = {"company": ["in", allowed]}
        if doctype == 'Knitting Event' and "financial_read" not in caps:
            filters["kind"] = ["not in", FINANCIAL_EVENTS]
        names = [row.name for row in _source_rows(doctype, filters) if source_scope(row, user)]
        condition += f' and `tab{doctype}`.`name` in (' + (','.join(frappe.db.escape(n) for n in names) or 'NULL') + ')'
    return condition
