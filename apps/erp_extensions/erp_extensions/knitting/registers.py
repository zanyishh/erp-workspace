"""Bounded, permission-scoped history pages and independent mill totals."""
from datetime import datetime, timedelta
from decimal import Decimal

import frappe
from frappe.utils import getdate

from . import domain, permissions

PAGE_SIZE = 100
BATCH_SIZE = 1000
JOB_ORDER_FIELD = {"IFNULL": ["job_date", "creation"], "as": "_job_order_date"}
JOB_ORDER = "_job_order_date desc, creation desc, name desc"
REGISTERS = {
    "estimates": ("Quotation", ["name", "modified", "transaction_date", "party_name", "status", "docstatus"]),
    "jobs": ("Knitting Job", ["name", "modified", "customer", "job_date", "source_reference", "source_record", "kind", "material_mode", "due_date", "status", "target_kg", "revision", "programme"]),
    "rolls": ("Knitting Roll", ["name", "job", "programme_line", "weight_kg", "state", "warehouse", "machine", "operator", "shift", "produced_at", "production", "delivery"]),
    "batches": ("Knitting Fabric Batch", ["name", "job", "programme_line", "quantity_kg", "rolls", "state", "source_reference", "captured_at", "specification", "production", "warehouse"]),
    "lots": ("Knitting Material Lot", ["name", "item", "party", "material_owner", "warehouse", "source_lot", "specification"]),
    "machines": ("Knitting Machine", ["name", "title", "dia", "gauge", "knit_type", "capacity_kg", "enabled"]),
    "plans": ("Knitting Plan", ["name", "job", "machine", "starts_at", "ends_at", "quantity_kg", "state", "programme_line", "produced_kg", "required_yarn_kg"]),
    "inspections": ("Knitting QC", ["name", "job", "roll", "checker", "decision", "remarks", "creation"]),
    "events": ("Knitting Event", ["name", "job", "kind", "occurred_at", "cancelled"]),
    "subcontracts": ("Knitting Subcontract", ["name", "job", "supplier", "target_kg", "status", "warehouse", "purchase_order"]),
    "components": ("Knitting Component", ["name", "machine", "component_type", "boundary_kg", "run_kg", "installed_at"]),
    "masters": ("Knitting Master", ["name", "category", "title", "enabled", "specification", "modified"]),
    "holidays": ("Knitting Holiday", ["name", "machine", "date", "description"]),
    "rates": ("Knitting Rate", ["name", "customer", "fabric", "yarn_count", "gauge", "rate", "effective_from"]),
}
STATES = {
    "estimates": ("status", {"Draft", "Open", "Replied", "Partially Ordered", "Ordered", "Lost", "Cancelled", "Expired"}),
    "batches": ("state", {"Awaiting review", "Released", "On Hold", "Cancelled"}),
    "jobs": ("status", {"Running", "Completed", "Cancelled"}),
    "rolls": ("state", {"Awaiting QC", "Released", "On Hold", "Rework", "Rejected", "Delivered", "Split", "Cancelled"}),
    "plans": ("state", {"Planned", "Started", "Completed", "Cancelled"}),
    "subcontracts": ("status", {"Open", "Completed", "Cancelled"}),
    "events": ("kind", {"Billing"}),
}
BILLING_KINDS = [
    'invoice', 'credit_invoice', 'bill_yarn', 'subcontract_bill',
    'migration_delivery_reference', 'migration_billing_initialization',
]
SEARCH_FIELDS = {"name", "title", "source_reference", "customer", "kind", "status", "item", "party", "source_lot", "material_owner",
                 "job", "machine", "operator", "shift", "state", "programme_line", "supplier", "category", "description",
                 "fabric", "yarn_count", "gauge", "dia", "knit_type", "component_type", "checker", "decision", "remarks", "party_name"}


def customer_names(rows):
    """Resolve only the current page's readable customer titles in one query."""
    names = {row.customer for row in rows if row.customer}
    titles = {}
    if names and frappe.has_permission("Customer", "read"):
        titles = {row.name: row.get("customer_name") for row in frappe.get_list("Customer",
            filters={"name": ["in", sorted(names)]}, fields=["name", "customer_name"], limit=len(names))}
    for row in rows:
        row.customer_name = titles.get(row.customer)
        row.is_imported = domain.is_imported_job(row)
        row.pop('source_record', None)
        row.pop("_job_order_date", None)


def literal_search_pattern(query):
    return "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def customer_name_matches(query, *, literal=False):
    if not query or not frappe.has_permission("Customer", "read"):
        return []
    return frappe.get_list("Customer", filters={"customer_name": ["like", literal_search_pattern(query) if literal else "%" + query + "%"]},
        pluck="name", limit=0)



def original_reference_matches(company, query):
    """Search verified saved labels only through readable jobs' exact original links."""
    if not query:
        return []
    from erp_extensions.migration import api as history, contracts, service
    from erp_extensions.migration.references import verified_job_reference
    scope = history._scope(company, required=False)
    if not scope:
        return []
    after, matches = '', []
    identity = ('source_key', 'company', 'source_company_id', 'source_book', 'namespace',
                'native_id', 'family', 'shared_cash', 'shared_reference')
    while True:
        jobs = frappe.get_list('Knitting Job', filters={'company': company,
            'source_record': ['is', 'set'], 'name': ['>', after]},
            fields=['name', 'source_record'], order_by='name asc', limit=PAGE_SIZE)
        if not jobs:
            return matches
        originals = frappe.get_all(service.RECORD, filters={'name': ['in', [row.source_record for row in jobs]],
            'source_scope': scope['name'], 'company': company, 'namespace': 'knitpack.job', 'family': 'job'},
            fields=['name', 'source_scope', 'record_data', 'data_sha256', *identity], limit=PAGE_SIZE)
        matched = set()
        for row in originals:
            record = service.record_from_row(row)
            key = contracts.sha({'instance': scope['source_instance'], 'namespace': record['namespace'],
                'company': record['source_company_id'], 'book': record['source_book'],
                'native_id': record['native_id'], 'parents': record['parent_scope']})
            if (record['company'] != company or record['namespace'] != 'knitpack.job' or record['family'] != 'job'
                    or record['shared_cash'] or record['shared_reference']
                    or scope['company_bindings'].get(record['source_company_id']) != company
                    or record['source_key'] != key or record['name'] != 'history-' + key
                    or any(row[field] != record[field] for field in identity)):
                frappe.throw('An original job reference has inconsistent identity.')
            label = verified_job_reference(record)
            if label is not None and query.casefold() in label.casefold():
                matched.add(record['name'])
        matches.extend(row.name for row in jobs if row.source_record in matched)
        if len(jobs) < PAGE_SIZE:
            return matches
        after = jobs[-1].name


def _estimates(rows, company):
    # Conversion state belongs to the readable estimate; hidden job identities do not.
    filters = {"company": company, "quotation": ["in", [row.name for row in rows]]}
    converted = set(frappe.get_all("Knitting Job", filters=filters, pluck="quotation", limit=PAGE_SIZE)) if rows else set()
    jobs = {row.quotation: row.name for row in frappe.get_list("Knitting Job", filters=filters,
        fields=["name", "quotation"], limit=PAGE_SIZE)} if rows else {}
    customers = [frappe._dict(customer=row.party_name) for row in rows]
    customer_names(customers)
    for row, customer in zip(rows, customers):
        row.customer_name = customer.customer_name
        row.converted = row.name in converted
        row.job = jobs.get(row.name)
        if "grand_total" in row:
            row.grand_total = domain.money(row.grand_total or 0)


def _scope(company, job):
    if not isinstance(company, str) or not company or len(company) > 140:
        frappe.throw("Choose a valid company.")
    permissions.require(company, "jobs", history=True)
    if job is not None:
        if not isinstance(job, str) or not job or len(job) > 140:
            frappe.throw("Choose a valid source job.")
        domain.reference("Knitting Job", job, company)


def _parameters(collection, start, query, state, production_date, from_date=None, to_date=None, customer=None, category=None):
    if not isinstance(collection, str) or collection not in REGISTERS:
        frappe.throw("Choose a supported knitting register.")
    if isinstance(start, str) and 1 <= len(start) <= 7 and start.isascii() and start.isdecimal():
        start = int(start)
    if isinstance(start, bool) or not isinstance(start, int) or not 0 <= start <= 1000000:
        frappe.throw("Choose a valid register page.")
    if not isinstance(query, str) or len(query) > 120:
        frappe.throw("Use up to 120 characters to search this register.")
    if state is not None and (collection not in STATES or not isinstance(state, str) or state not in STATES[collection][1]):
        frappe.throw("Choose a supported register state.")
    if customer is not None and (collection != "jobs" or not isinstance(customer, str)
            or not customer or len(customer) > 140 or '\x00' in customer):
        frappe.throw("Choose a valid customer for the job register.")
    if category is not None:
        from .factory import MASTER_CATEGORIES
        if collection != "masters" or not isinstance(category, str) or category not in MASTER_CATEGORIES:
            frappe.throw("Choose a supported industry master category.")
    if from_date is not None or to_date is not None:
        if collection not in ("estimates", "jobs"):
            frappe.throw("Choose a job or estimate register for a date range.")
        for value in (from_date, to_date):
            if value is None:
                continue
            if not isinstance(value, str) or len(value) != 10:
                frappe.throw("Use register dates in YYYY-MM-DD format.")
            try:
                if str(datetime.strptime(value, "%Y-%m-%d").date()) != value:
                    raise ValueError()
            except ValueError:
                frappe.throw("Use valid register dates in YYYY-MM-DD format.")
        if from_date and to_date and from_date > to_date:
            frappe.throw("The register end date must be on or after its start date.")
    if production_date is not None:
        if collection != "events" or not isinstance(production_date, str) or len(production_date) != 10:
            frappe.throw("Choose a production date for the activity register.")
        try:
            day = datetime.strptime(production_date, "%Y-%m-%d").date()
            if str(day) != production_date or production_date == "9999-12-31":
                raise ValueError()
        except ValueError:
            frappe.throw("Use a valid production date in YYYY-MM-DD format.")
    return int(start), query.strip()


def _batch_rows(doctype, filters, fields, *, permitted=True):
    """Read fixed-size batches without retaining a company's full history."""
    after = None
    read = frappe.get_list if permitted else frappe.get_all
    while True:
        rows = read(doctype, filters={**filters, **({"name": [">", after]} if after else {})},
                    fields=list(dict.fromkeys(["name", *fields])), order_by="name asc", limit=BATCH_SIZE)
        yield from rows
        if len(rows) < BATCH_SIZE:
            return
        after = rows[-1].name


def _events(filters):
    """Private event JSON is loaded only for IDs returned by permission checks."""
    after = None
    while True:
        rows = frappe.get_list("Knitting Event", filters={**filters, **({"name": [">", after]} if after else {})},
            fields=["name", "kind", "occurred_at"], order_by="name asc", limit=BATCH_SIZE)
        if rows:
            results = dict(frappe.get_all("Knitting Event", filters={"name": ["in", [row.name for row in rows]]},
                fields=["name", "result"], as_list=True))
            for row in rows:
                row.result = domain.json_value(results.get(row.name), {})
                yield row
        if len(rows) < BATCH_SIZE:
            return
        after = rows[-1].name


def _lot_page(company, job, fields, query, start, *, aggregate_checked=False):
    # Scope checks include each allocated lot. Filter its grouped physical balance
    # in SQL before paging, so an older allocated lot cannot disappear behind general stock.
    if not aggregate_checked:
        permissions.require_aggregate_scope(company, job)
    criteria = "lot.company=%s"
    values = [company, job, company]
    if query:
        columns = [field for field in fields if field in SEARCH_FIELDS]
        criteria += " and (" + " or ".join(f"lot.`{field}` like %s" for field in columns) + ")"
        values.extend(["%" + query + "%"] * len(columns))
    source = """from `tabKnitting Material Lot` lot join (
        select lot from `tabKnitting Ledger Entry` where company=%s and job=%s and custodian='Warehouse'
        group by lot having sum(cast(quantity_kg as decimal(24,3)))<>0
            or sum(cast(coalesce(nullif(units,''),'0') as decimal(24,3)))<>0
        ) allocation on allocation.lot=lot.name where """ + criteria
    total = frappe.db.sql("select count(*) " + source, values)[0][0]
    names = [row[0] for row in frappe.db.sql("select lot.name " + source +
        " order by lot.creation desc, lot.name desc limit %s offset %s", [*values, PAGE_SIZE + 1, start])]
    rows = frappe.get_list("Knitting Material Lot", filters={"company": company, "name": ["in", names]},
        fields=fields, order_by="creation desc, name desc", limit=PAGE_SIZE + 1) if names else []
    if len(rows) != len(names):
        frappe.throw("This lot reconciliation includes records outside your access.", frappe.PermissionError)
    return rows, int(total)


def _lots(rows, company, jobs, scope_job):
    if not rows:
        return
    allocated, units = {}, {}
    for row in _batch_rows("Knitting Ledger Entry", {"company": company,
            "lot": ["in", [lot.name for lot in rows]], "custodian": "Warehouse",
            **({"job": scope_job} if scope_job else {})},
            ["lot", "job", "quantity_kg", "units"], permitted=False):
        key = (row.lot, row.job or None)
        allocated[key] = allocated.get(key, Decimal(0)) + Decimal(row.quantity_kg)
        units[key] = units.get(key, Decimal(0)) + Decimal(row.units or "0")
    by_lot = {}
    for (lot, job), quantity in allocated.items():
        physical = units[(lot, job)]
        if job in jobs and (quantity or physical):
            by_lot.setdefault(lot, []).append({"job": job, "quantity_kg": domain.kg(quantity), "units": str(physical)})
    for lot in rows:
        lot.allocations = by_lot.get(lot.name, [])
        lot.general_kg = None if scope_job else domain.kg(allocated.get((lot.name, None), 0))
        lot.general_units = None if scope_job else str(units.get((lot.name, None), 0))


def _page(company, collection, job=None, start=0, query="", state=None, production_date=None, from_date=None, to_date=None, customer=None, category=None, *, allocation_jobs=(), aggregate_checked=False):
    from .api import project
    start, query = _parameters(collection, start, query, state, production_date, from_date, to_date, customer, category)
    finance = "financial_read" in permissions.capabilities()
    if collection == "rates" and not finance:
        frappe.throw("This account cannot view agreed rates.", frappe.PermissionError)
    doctype, base_fields = REGISTERS[collection]
    fields = [*base_fields, *(["rate", "service_item"] if collection == "jobs" and finance else [])]
    filters = {"company": company}
    if category is not None:
        filters["category"] = category
    if customer is not None:
        domain.reference("Customer", customer)
        filters["customer"] = customer
    if collection in ("estimates", "jobs"):
        date_field = "job_date" if collection == "jobs" else "transaction_date"
        if from_date and to_date:
            filters[date_field] = ["between", [from_date, to_date]]
        elif from_date:
            filters[date_field] = [">=", from_date]
        elif to_date:
            # MariaDB legacy missing Date values can be zero dates rather than NULL.
            filters[date_field] = ["between", ["0001-01-01", to_date]] if collection == "jobs" else ["<=", to_date]
    if collection == "estimates":
        # factory.create_estimate owns this marker; ordinary ERP quotations lack it.
        filters.update(quotation_to="Customer", knitting_event=["is", "set"])
        if finance:
            fields.extend(["grand_total", "currency"])
    if job:
        if collection == "jobs":
            filters["name"] = job
        elif collection == "estimates":
            filters["name"] = frappe.db.get_value("Knitting Job", job, "quotation") or ""
        elif frappe.get_meta(doctype).has_field("job"):
            filters["job"] = job
    if collection == 'events' and state == 'Billing':
        filters['kind'] = ['in', BILLING_KINDS]
    elif state is not None:
        filters[STATES[collection][0]] = state
    if production_date is not None:
        begin = datetime.strptime(production_date, "%Y-%m-%d")
        filters.update(kind=["in", ["produce", "produce_bulk", "produce_batch"]], cancelled=0,
                       occurred_at=["between", [begin, begin + timedelta(days=1) - timedelta(microseconds=1)]])
    if collection == "lots" and job:
        rows, total = _lot_page(company, job, fields, query, start, aggregate_checked=aggregate_checked)
    else:
        if collection == "estimates":
            # party_name is a Dynamic Link, so Frappe does not apply Customer row permissions itself.
            if frappe.has_permission("Customer", "read"):
                customers = frappe.get_list("Customer", fields=["name"], limit=0, run=False)
                quotation_customers = frappe.get_list("Customer", fields=["name"], limit=0,
                    reference_doctype="Quotation", run=False)
                party = frappe.qb.DocType("Quotation").party_name
                filters = [filters, party.isin(customers), party.isin(quotation_customers)]
            else:
                filters["name"] = ""
        pattern = literal_search_pattern(query) if collection == "jobs" else "%" + query + "%"
        options = {"filters": filters, "or_filters": [[field, "like", pattern]
            for field in fields if field in SEARCH_FIELDS] if query else None}
        if collection in ("jobs", "estimates"):
            matches = customer_name_matches(query, literal=collection == "jobs")
            if matches:
                options["or_filters"].append(["party_name" if collection == "estimates" else "customer", "in", matches])
            if collection == "jobs":
                references = original_reference_matches(company, query)
                if references:
                    options["or_filters"].append(["name", "in", references])
                fields = [*fields, JOB_ORDER_FIELD]
        rows = frappe.get_list(doctype, **options, fields=fields,
            order_by=JOB_ORDER if collection == "jobs" else "creation desc, name desc", offset=start, limit=PAGE_SIZE + 1)
        total = int(frappe.get_list(doctype, **options, fields=[{"COUNT": "*", "as": "total"}], limit=1)[0].total)
    has_more = len(rows) > PAGE_SIZE
    rows = rows[:PAGE_SIZE]
    if collection == "estimates":
        _estimates(rows, company)
    elif collection == "jobs":
        customer_names(rows)
        for row in rows:
            row.programme = domain.json_value(row.programme, [])
            if finance:
                row.rate = domain.money(row.rate or 0)
            if job:
                row.workflow = {}
                try:
                    row.balances = domain.balances(row.name, workflow=row.workflow, programme=row.programme)
                except permissions.SourceReconciliationError:
                    row.balances = None
                    row.reconciliation_available = False
                    row.pop("workflow")
        if not job and rows:
            try:
                balances = domain.register_balances(company, rows)
            except permissions.SourceReconciliationError as error:
                balances = domain.register_balances(company, [row for row in rows if row.name not in error.jobs])
            for row in rows:
                row.balances = balances.get(row.name)
                if row.balances is None:
                    row.reconciliation_available = False
    elif collection == "lots":
        if not job and not aggregate_checked:
            permissions.require_aggregate_scope(company)
        _lots(rows, company, {job} if job else set(allocation_jobs), job)
    elif collection == "events" and rows:
        results = dict(frappe.get_all("Knitting Event", filters={"name": ["in", [row.name for row in rows]]},
            fields=["name", "result"], as_list=True))
        for row in rows:
            row.result = project(domain.json_value(results.get(row.name), {}), financial_read=finance)
    elif collection == "components":
        for row in rows:
            row.remaining_kg = domain.kg(Decimal(row.boundary_kg) - Decimal(row.run_kg or "0"))
    elif collection == "rates":
        for row in rows:
            row.rate = domain.money(row.rate or 0)
    if collection in ("jobs", "batches"):
        from erp_extensions.migration import dimensions
        if collection == "jobs":
            dimensions.programmes(company, rows)
        else:
            dimensions.specifications(company, rows)
    return {"version": 1, "company": company, "collection": collection, "scope_job": job,
        "query": query, "state": state, "rows": rows,
        **({"from_date": from_date, "to_date": to_date} if collection in ("estimates", "jobs") else {}),
        **({"customer": customer} if collection == "jobs" else {}),
        **({"category": category} if collection == "masters" else {}),
        "page": {"start": start, "limit": PAGE_SIZE, "has_more": has_more, "total": total}}


def page(company, collection, job=None, start=0, query="", state=None, production_date=None, from_date=None, to_date=None, customer=None, category=None):
    _scope(company, job)
    return _page(company, collection, job, start, query, state, production_date, from_date, to_date, customer, category)


def snapshot(company, job=None):
    _scope(company, job)
    finance = "financial_read" in permissions.capabilities()
    result = {"version": 1, "company": company, "scope_job": job, "financial_read": finance, "pagination": {}}
    for collection in REGISTERS:
        if collection == "rates" and not finance:
            continue
        if collection == "estimates" and not frappe.has_permission("Quotation", "read"):
            continue
        value = _page(company, collection, job, allocation_jobs=[row.name for row in result.get("jobs", [])],
            aggregate_checked=collection != "jobs" and (job is None or bool(result.get("jobs"))))
        result[collection] = value["rows"]
        result["pagination"][collection] = value["page"]
    result["integrations"] = [{"name": name, "status": "Not configured"} for name in ("E-Invoice", "E-Way Bill", "Payment gateway")]
    return result


def _counts(doctype, company, field):
    return {row[field]: int(row.total) for row in frappe.get_list(doctype, filters={"company": company},
        fields=[field, {"COUNT": "*", "as": "total"}], group_by=field, limit=100)}


def overview(company):
    _scope(company, None)
    permissions.require_aggregate_scope(company)
    jobs = _counts("Knitting Job", company, "status")
    rolls = _counts("Knitting Roll", company, "state")
    plans = _counts("Knitting Plan", company, "state")
    yarn = sum((Decimal(row.quantity_kg) for row in _batch_rows("Knitting Ledger Entry",
        {"company": company, "custodian": "Warehouse", "job": ["is", "set"]}, ["quantity_kg"])), Decimal(0))
    running_yarn = sum((Decimal(row.quantity_kg) for row in _batch_rows("Knitting Ledger Entry",
        {"company": company, "custodian": "Warehouse", "job.company": company,
         "job.status": "Running"}, ["quantity_kg"])), Decimal(0))
    unbilled = None
    if "financial_read" in permissions.capabilities():
        signs = {"deliver": 1, "deliver_batch": 1, "return_fabric": -1, "return_batch": -1,
            "invoice": -1, "credit_invoice": 1, "migration_billing_initialization": 1}
        financial = {"company": company, "job": ["is", "set"], "cancelled": 0, "kind": ["in", list(signs)]}
        amount, visible = Decimal(0), 0
        for row in _events(financial):
            quantity = "captured_unbilled_kg" if row.kind == "migration_billing_initialization" else "quantity_kg"
            amount += signs[row.kind] * Decimal(row.result.get(quantity) or "0")
            visible += 1
        # A hidden linked voucher must not make an outstanding balance look smaller.
        if visible == frappe.db.count("Knitting Event", financial):
            unbilled = domain.kg(amount)
    production_filters = {"company": company, "cancelled": 0, "kind": ["in", ["produce", "produce_bulk", "produce_batch"]]}
    visible_production = int(frappe.get_list("Knitting Event", filters=production_filters,
        fields=[{"COUNT": "*", "as": "total"}], limit=1)[0].total)
    complete_production = visible_production == frappe.db.count("Knitting Event", production_filters)
    # A company chart is unavailable if even an older active source is restricted.
    # Do not use a restricted source's date to choose or label the visible period.
    latest = frappe.get_list("Knitting Event", filters=production_filters,
        fields=["occurred_at"], order_by="occurred_at desc, name desc", limit=1) if complete_production else []
    production = {}
    if latest and latest[0].occurred_at:
        end = getdate(latest[0].occurred_at)
        begin = end - timedelta(days=6)
        production = {str(begin + timedelta(days=i)): {"quantity": Decimal(0), "count": 0} for i in range(7)}
        for row in _events({**production_filters, "occurred_at": ["between", [str(begin), str(end + timedelta(days=1))]]}):
            entry = production.get(str(getdate(row.occurred_at)))
            if entry is not None:
                entry["quantity"] += Decimal(row.result.get("quantity_kg") or "0")
                entry["count"] += 1
    return {"version": 1, "company": company, "jobs": {"total": sum(jobs.values()), "running": jobs.get("Running", 0)},
        "rolls": {state: rolls.get(state, 0) for state in ("Awaiting QC", "On Hold", "Released")},
        "plans": {"Planned": plans.get("Planned", 0)}, "balances": {"yarn_kg": domain.kg(yarn),
            "running_yarn_kg": domain.kg(running_yarn), "unbilled_kg": unbilled},
        "production": [{"date": day, "quantity_kg": domain.kg(values["quantity"]), "count": values["count"]}
            for day, values in production.items()] if complete_production else None}


def roll(company, job, name):
    _scope(company, job)
    if not job or not isinstance(name, str) or not name or len(name) > 140:
        frappe.throw("Choose the roll's source job.")
    record = domain.reference("Knitting Roll", name, company)
    if record.job != job:
        frappe.throw("This roll belongs to another job.", frappe.PermissionError)
    return {"company": company, **{field: record.get(field) for field in REGISTERS["rolls"][1]}}
