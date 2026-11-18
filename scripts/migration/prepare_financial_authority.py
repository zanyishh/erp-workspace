"""Offline native-amount bridge inputs; immutable private evidence, never site writes."""
import argparse
from collections import Counter, defaultdict
from datetime import date
from decimal import Decimal, ROUND_HALF_EVEN, localcontext
from hashlib import sha256
import json
import importlib.util
import os
from pathlib import Path


def identity(value):
    if isinstance(value, bool) or value is None:
        raise ValueError("A native identifier is required.")
    text = str(value)
    number = Decimal(text)
    if not number.is_finite() or number != number.to_integral_value() or number < 0:
        raise ValueError("Use the original integral native identifier.")
    return str(int(number))


def money(value):
    if value is None or value == "" or isinstance(value, (bool, float)):
        raise ValueError("An exact native amount is required.")
    result = Decimal(str(value))
    if not result.is_finite():
        raise ValueError("An exact finite amount is required.")
    return result


def financial_record(header, invoice_link=None):
    company, native_id, book, party = (identity(header[k]) for k in ("companymas_id", "id", "sec_acc", "party_id"))
    if company not in ("1", "2", "3", "4") or book not in ("0", "1", "2") or party == "0":
        raise ValueError("The financial native scope is invalid.")
    amount = money(header.get("amt"))
    if amount < 0 or amount != amount.quantize(Decimal("0.01")):
        raise ValueError("The native amount cannot be posted exactly at currency precision.")
    if str(header.get("cancelled")) not in ("0", "1") or header.get("entry_type") not in ("debit", "credit"):
        raise ValueError("Native cancellation and posting direction must be explicit.")
    financial = {"amount": format(amount, "f"), "currency": "INR", "entry_type": header["entry_type"],
        "voucher_type": header["acc_type"], "accounting_party_id": party,
        "source_reference": str(header.get("v_no") or native_id), "cancelled": str(header["cancelled"]) == "1"}
    for target, source in (("general_ledger_id", "acc_code1"), ("cash_ledger_id", "cash_ledger")):
        if header.get(source) not in (None, ""):
            financial[target] = identity(header[source])
    for target, source in (("source_adjusted_amount", "adj_val"), ("source_pending_amount", "pend_amt"),
            ("taxable_amount", "taxable_value"), ("cgst_amount", "cgst_value"), ("sgst_amount", "sgst_value"), ("igst_amount", "igst_value")):
        if header.get(source) not in (None, ""):
            financial[target] = format(money(header[source]), "f")
    if header.get("payment_mode") is not None:
        financial["payment_mode"] = str(header["payment_mode"])
    if header["acc_type"] == "sales":
        namespace = {"kpinvoice": "regular", "kpgeninvoice": "general"}.get(header.get("acc_ref_type"))
        if not namespace or not invoice_link or list(map(identity, invoice_link["voucher_key"])) != [company, native_id, book]:
            raise ValueError("Sales require their exact corroborated native invoice link.")
        invoice_id = identity(header.get("acc_ref_code"))
        if invoice_link["invoice_key"] != [namespace, company, invoice_id, book]:
            raise ValueError("The invoice belongs to a different native scope.")
        financial.update(invoice_namespace=header["acc_ref_type"], invoice_native_id=invoice_id,
            invoice_party_id=identity(invoice_link["original_invoice_party_id"]))
        for field in ("original_invoice_value", "original_r_invoice_value"):
            value = invoice_link.get(field)
            if value not in (None, ""):
                financial[field] = format(money(value), "f")
    return {"namespace": "accv2.opening" if header["acc_type"] == "opening-balance" else "accv2.voucher",
        "source_company_id": company, "source_book": book, "native_id": native_id,
        "original_date_raw": header.get("v_date"), "financial": financial}


def compare_party_controls(headers, controls, opening_date):
    date.fromisoformat(opening_date)
    groups, seen = defaultdict(list), set()
    for header in headers:
        source = tuple(identity(header[k]) for k in ("companymas_id", "id", "sec_acc"))
        namespace = "opening" if header["acc_type"] == "opening-balance" else "voucher"
        if (namespace, source) in seen:
            raise ValueError("Duplicate native financial identity.")
        seen.add((namespace, source))
        if str(header.get("cancelled")) not in ("0", "1") or header.get("entry_type") not in ("debit", "credit"):
            raise ValueError("Explicit native cancellation and direction are required.")
        if str(header["cancelled"]) == "1":
            continue
        original = header.get("v_date")
        effective = opening_date if namespace == "opening" and original in (None, "", "0", "0000-00-00", "0000-00-00 00:00:00") else original
        if not isinstance(effective, str) or date.fromisoformat(effective).isoformat() != effective:
            raise ValueError("Preserve a valid original date or the approved undated opening date.")
        value = money(header.get("amt"))
        sign = 1 if header["entry_type"] == "debit" else -1
        key = (source[0], identity(header["party_id"]), source[2])
        groups[key].append((effective, value * sign, (value if namespace == "opening" else value.quantize(Decimal(1), rounding=ROUND_HALF_EVEN)) * sign, namespace))
    counts, rows = Counter(), []
    with localcontext() as context:
        context.prec = 50
        for control in controls:
            if control["kind"] != "party":
                continue
            key = tuple(identity(control[k]) for k in ("source_company_id", "source_ledger_id", "requested_book"))
            comparisons = {}
            for label, cutoff in (("opening", control["from_date"]), ("closing", control["to_date"])):
                values = [row for row in groups[key] if row[0] < cutoff or (row[0] == cutoff and (label == "closing" or row[3] == "opening"))]
                exact, projection = sum((r[1] for r in values), Decimal(0)), sum((r[2] for r in values), Decimal(0))
                supplied = control.get(label + "_net")
                target = None if supplied in (None, "") else money(supplied)
                equal = None if target is None else projection == target
                comparisons[label] = {"native_signed_amount": format(exact, "f"), "legacy_projection": format(projection, "f"),
                    "source_control": None if target is None else format(target, "f"),
                    "native_delta": None if target is None else format(exact - target, "f"),
                    "projection_delta": None if target is None else format(projection - target, "f"),
                    "native_equal": None if target is None else exact == target, "projection_equal": equal}
                counts[label + ("_unknown" if equal is None else "_projection_equal" if equal else "_projection_different")] += 1
            rows.append({"source_key": key, "from_date": control["from_date"], "to_date": control["to_date"],
                "path": control["path"], "native_header_count": len(groups[key]), "comparisons": comparisons})
    return {"approved_opening_date": opening_date, "counts": dict(counts), "partitions": rows,
        "projection_basis": "Observed source report whole-unit HALF_EVEN voucher movements; exact native openings. No amounts changed and no rounding journals.",
        "zero_population_basis": "Supplied complete native header inventory only; missing control remains unknown."}


def party_role(customer_type, voucher_type):
    roles = {r.strip() for r in str(customer_type).split(",")}
    customer, supplier = "party" in roles, bool(roles & {"supplier", "subcontractor"})
    if supplier and not customer:
        return "Supplier", "single_source_supplier_role"
    if customer and not supplier:
        return "Customer", "single_source_customer_role"
    if customer and supplier:
        if voucher_type in ("purchase", "payment", "debitnote"):
            return "Supplier", "source_supplier_role_and_document_kind"
        if voucher_type in ("sales", "receipt", "tdsrecieve", "creditnote"):
            return "Customer", "source_customer_role_and_document_kind"
        return "Customer", "approved_unified_party_fallback"
    raise ValueError("The native master has no supported customer or supplier role.")


def mapping_plan(records, parties, general_masters, cash_masters):
    """Caller resolves account keys into real company accounts before native posting."""
    specs = {"receivable": {"account_name": "Legacy Receivables", "root_type": "Asset", "account_type": "Receivable"},
        "payable": {"account_name": "Legacy Payables", "root_type": "Liability", "account_type": "Payable"},
        "opening_equity": {"account_name": "Legacy Opening Balance", "root_type": "Equity", "account_type": ""},
        "sales_control": {"account_name": "Legacy Sales Control", "root_type": "Asset", "account_type": "",
            "basis": "Gross original sales counterpart control; does not claim a reconstructed statutory tax or income split."}}
    for master in general_masters:
        native_id = identity(master["id"])
        label = str(master.get("ledger_type") or "").lower()
        root_type = "Expense" if "expense" in label else "Income" if "income" in label else "Asset"
        specs["general:" + native_id] = {"account_name": "Legacy Source Ledger " + native_id, "root_type": root_type, "account_type": "",
            "source_ledger_id": native_id, "source_ledger_name": master.get("ledger_name"), "source_ledger_type": master.get("ledger_type"),
            "basis": "Source named expense/income category" if root_type != "Asset" else "Unclassified source category retained as a legacy control account, not an invented income/tax split"}
    postings, suppliers, counts = [], set(), Counter()
    for record in records:
        f = record["financial"]
        party_id = f["accounting_party_id"]
        if party_id not in parties:
            raise ValueError("A financial party is absent from the native master inventory.")
        role, role_basis = party_role(parties[party_id].get("customer_type"), f["voucher_type"])
        if role == "Supplier":
            suppliers.add(party_id)
        mapping = {"source_company_id": record["source_company_id"], "source_book": record["source_book"],
            "currency": "INR", "party_type": role, "party": ("KP-PARTY-" if role == "Customer" else "KP-SUPPLIER-") + party_id,
            "accounting_party_id": party_id}
        if f["voucher_type"] == "opening-balance":
            counter, basis = "opening_equity", "approved_opening_equity"
        elif f.get("general_ledger_id") not in (None, "", "0"):
            counter, basis = "general:" + f["general_ledger_id"], "native_general_account"
            mapping["general_ledger_id"] = f["general_ledger_id"]
        elif f["voucher_type"] == "sales":
            counter, basis = "sales_control", "native_document_type"
        else:
            raise ValueError("The native voucher has no corroborated counterpart mapping.")
        if counter not in specs:
            raise ValueError("A native source account is absent from the master inventory.")
        mapping["counter_basis"] = basis
        postings.append({"source_identity": {k: record[k] for k in ("namespace", "source_company_id", "source_book", "native_id")},
            "mapping": mapping, "party_account_key": "receivable" if role == "Customer" else "payable", "counter_account_key": counter,
            "source_cash_category_id": f.get("cash_ledger_id"),
            "source_party_role": parties[party_id].get("customer_type"), "party_role_basis": role_basis,
            "posting_required": money(f["amount"]) != 0 and not f["cancelled"]})
        counts[(role, role_basis)] += 1
    return {"postings": postings, "account_specs": specs, "required_supplier_ids": sorted(suppliers, key=int),
        "role_counts": {" / ".join(key): value for key, value in counts.items()},
        "shared_cash_opening_in_company_gl": False, "settlement_references_inferred": False,
        "policy": "Preserve native signed amounts. Respect single source roles; use document kind for dual roles; ambiguous unified-party openings/adjustments use Customer/Receivable. Reconcile combined Customer+Supplier net for each original party/company/book.",
        "limitations": ["Counterparts are explicit legacy control mappings, not a reconstructed statutory tax ledger.",
            "Source shared cash category balances and openings are retained once outside company GL; cash selectors never fabricate Cash/Bank legs.",
            "Unresolved source adjustments remain visible and unallocated; no fictitious settlement links."]}


def settlement_plan(graph, mapping, records):
    if graph.get("integrity_issues"):
        raise ValueError("The source settlement graph has unresolved integrity issues.")
    module_path = Path(__file__).resolve().parents[2] / "apps/erp_extensions/erp_extensions/migration/settlements.py"
    spec = importlib.util.spec_from_file_location("settlement_contract", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    key = lambda r: tuple(r[k] for k in ("source_company_id", "native_id", "source_book"))
    mapped = {key(r["source_identity"]): r for r in mapping["postings"]}
    native = {key(r): r for r in records}
    groups = []
    counts = {"components": 0, "edges": 0, "same_account_edges": 0, "cross_role_edges": 0}
    for i, component in enumerate(graph["components"]):
        if component["status"] != "conserved_current_state":
            continue
        nodes = {}
        identities = []
        for original in component["nodes"]:
            source = tuple(original)
            m, f = mapped[source], native[source]["financial"]
            node_key = ":".join(source)
            nodes[node_key] = {"company": source[0], "source_book": source[2], "finance_book": source[0] + ":" + source[2],
                "accounting_party_id": f["accounting_party_id"], "amount": f["amount"], "adjusted": f.get("source_adjusted_amount"),
                "entry_type": f["entry_type"], "party_type": m["mapping"]["party_type"], "party_account": m["party_account_key"]}
            identities.append(m["source_identity"])
        edges, validate_edges = [], []
        for index in component["edge_indices"]:
            edge = graph["edges"][index]
            if edge["status"] != "conserved_current_state":
                raise ValueError("An unresolved edge cannot enter a conserved component plan.")
            a, b = tuple(edge["first"]), tuple(edge["second"])
            amount = format(money(edge["amount"]), "f")
            validate_edges.append({"first": ":".join(a), "second": ":".join(b), "amount": amount})
            edges.append({"first": mapped[a]["source_identity"], "second": mapped[b]["source_identity"], "amount": amount,
                          "source_edge_index": index})
        proof = module.validate_component(nodes, validate_edges)
        groups.append({"source_component_id": str(i), "nodes": identities, "edges": edges, "proof_counts": proof})
        counts["components"] += 1
        for field in ("edges", "same_account_edges", "cross_role_edges"):
            counts[field] += proof[field]
    return {"counts": counts, "groups": groups, "historical_allocation_dates_claimed": False,
            "unresolved_components_included": False, "execution": "Current native reconciliation; cross-role offsets use actual application date."}


def resolve_mapping(posting, targets, accounts):
    source = posting["source_identity"]
    company_id, book = source["source_company_id"], source["source_book"]
    company = targets["companies"][company_id]
    books = [r["finance_book"] for r in targets["books"] if r["source_company_id"] == company_id and r["source_book"] == book]
    if len(books) != 1:
        raise ValueError("Each company/book requires exactly one actual target binding.")
    result = {**posting["mapping"], "company": company["company"], "finance_book": books[0], "cost_center": company["cost_center"],
        "party_account": accounts[company_id][posting["party_account_key"]], "counter_account": accounts[company_id][posting["counter_account_key"]]}
    if not all(isinstance(result[k], str) and result[k] for k in ("company", "finance_book", "cost_center", "party_account", "counter_account")):
        raise ValueError("Actual company, book and account names are required.")
    return result


def compile_actual_package(root, plan, target_path, account_path, scope_path):
    def load_module(name):
        path = Path(__file__).resolve().parents[2] / f"apps/erp_extensions/erp_extensions/migration/{name}.py"
        spec = importlib.util.spec_from_file_location("migration_" + name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    contracts, finance = load_module("contracts"), load_module("finance")
    targets, accounts = json.loads(target_path.read_text()), json.loads(account_path.read_text())
    scope = contracts.normalize_scope(json.loads(scope_path.read_text()))
    identity_key = lambda r: tuple(r[k] for k in ("namespace", "source_company_id", "source_book", "native_id"))
    mappings = {identity_key(p["source_identity"]): resolve_mapping(p, targets, accounts) for p in plan["postings"]}
    destination = root / "destination/financial-native-dry-run.jsonl"
    history_path = root / "destination/history-records.jsonl"
    manifest_hash = sha256()
    groups = {}
    seen, posted, zero = set(), 0, 0
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as output, history_path.open("rb") as history:
        for raw in history:
            manifest_hash.update(raw)
            row = json.loads(raw)
            if row["namespace"] not in ("accv2.voucher", "accv2.opening"):
                continue
            key = identity_key(row)
            if key in seen or key not in mappings:
                raise ValueError("An actual financial source identity is duplicate or unmapped.")
            seen.add(key)
            record = contracts.normalize_record(scope, row)
            record["source_scope"] = targets["scope"]
            mapping = mappings[key]
            spec = finance.build_journal_spec(record, mapping, approved_opening_date=scope["opening_effective_date"], shared_cash_approved=True)
            output.write(json.dumps({"source_identity": {k: row[k] for k in ("namespace", "source_company_id", "source_book", "native_id")},
                "record_name": "history-" + record["source_key"], "mapping": mapping, "spec": spec}, ensure_ascii=False) + "\n")
            posted += bool(spec["posting_required"])
            zero += not spec["posting_required"]
            f = record["business_data"]["financial"]
            group_key = (row["source_company_id"], f["accounting_party_id"], row["source_book"])
            if group_key not in groups:
                groups[group_key] = {"source_company_id": group_key[0], "source_party_id": group_key[1], "source_book": group_key[2],
                    "company": mapping["company"], "finance_book": mapping["finance_book"], "native_signed_amount": Decimal(0), "records": 0, "target_parties": {}}
            group = groups[group_key]
            if not f["cancelled"]:
                group["native_signed_amount"] += money(f["amount"]) * (1 if f["entry_type"] == "debit" else -1)
            group["records"] += 1
            group["target_parties"][mapping["party_type"]] = {"party": mapping["party"], "account": mapping["party_account"]}
    if len(seen) != len(mappings):
        raise ValueError("The actual history package lacks required financial source identities.")
    result = {"history_sha256": manifest_hash.hexdigest(), "records": len(seen), "native_journals_required": posted,
        "explicit_zero_or_cancelled_no_posting": zero, "company_party_book_groups": len(groups), "scope": targets["scope"],
        "target_bindings_sha256": sha256(target_path.read_bytes()).hexdigest(), "account_bindings_sha256": sha256(account_path.read_bytes()).hexdigest(),
        "groups": list(groups.values()), "combined_role_net_basis": "Combine explicitly mapped Customer and Supplier legs; proved current offsets have zero combined source-party net."}
    path = root / "destination/financial-native-dry-run-controls.json"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(result, handle, default=str, indent=2)
    return {k: result[k] for k in ("records", "native_journals_required", "explicit_zero_or_cancelled_no_posting", "company_party_book_groups")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-root", type=Path, default=Path(".local/knitpack-migration"))
    parser.add_argument("--target-bindings", type=Path)
    parser.add_argument("--account-bindings", type=Path)
    parser.add_argument("--scope", type=Path)
    args = parser.parse_args()
    root = args.private_root
    paths = {"headers": root / "destination/native-settlement-header-index.json", "invoices": root / "reconciliation/native-invoice-final.json",
             "controls": root / "reconciliation/annual-ledger-expanded-book2-final.json"}
    inputs = {key: {"path": str(path), "sha256": sha256(path.read_bytes()).hexdigest()} for key, path in paths.items()}
    headers = json.loads(paths["headers"].read_text(), parse_float=Decimal)["headers"]
    invoices = json.loads(paths["invoices"].read_text(), parse_float=Decimal)
    links = {tuple(x["voucher_key"]): x for x in invoices["voucher_links"]}
    records = []
    for row in headers:
        record = financial_record(row["native_header"], links.get(tuple(row["source_key"])))
        record["provenance"] = row["provenance"]
        records.append(record)
    controls = json.loads(paths["controls"].read_text(), parse_float=Decimal)["partitions"]
    proof = compare_party_controls([x["native_header"] for x in headers], controls, "2023-04-01")
    master_package = json.loads((root / "destination/master-mapping-package.json").read_text())
    parties = {}
    for entity in master_package["entities"]:
        if entity["kind"] != "party":
            continue
        evidence = entity["evidence"][0]
        raw = (root / "report-snapshot" / evidence["file"]).read_bytes()
        if sha256(raw).hexdigest() != evidence["sha256"]:
            raise ValueError("A source party master failed its immutable hash check.")
        value = json.loads(raw, parse_float=Decimal)
        for part in evidence["pointer"].split("/")[1:]:
            value = value[int(part)] if isinstance(value, list) else value[part.replace("~1", "/").replace("~0", "~")]
        parties[identity(value["id"])] = value
    account_evidence = json.loads((root / "destination/native-posting-reference-evidence.json").read_text())
    plan = mapping_plan(records, parties, account_evidence["source_general_masters"], account_evidence["source_cash_masters"])
    graph_path = root / "destination/current-settlement-state.json"
    graph_bytes = graph_path.read_bytes()
    settlements = settlement_plan(json.loads(graph_bytes, parse_float=Decimal), plan, records)
    for filename, value in (("financial-record-enrichments.json", {"inputs": inputs, "records": records}),
                            ("financial-posting-mapping-plan.json", {"inputs": inputs, **plan}),
                            ("native-settlement-application-plan.json", {"graph_sha256": sha256(graph_bytes).hexdigest(), **settlements}),
                            ("native-party-balance-projection.json", {"inputs": inputs, **proof})):
        path = root / "destination" / filename
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            json.dump(value, handle, indent=2, ensure_ascii=False, default=str)
        os.chmod(path, 0o600)
    dry_run = None
    if any((args.target_bindings, args.account_bindings, args.scope)):
        if not all((args.target_bindings, args.account_bindings, args.scope)):
            raise ValueError("Supply target bindings, account bindings and the immutable scope together.")
        dry_run = compile_actual_package(root, plan, args.target_bindings, args.account_bindings, args.scope)
    print(json.dumps({"records": len(records), "required_suppliers": len(plan["required_supplier_ids"]), "party_controls": proof["counts"],
                      "settlements": settlements["counts"], "actual_target_dry_run": dry_run}))


if __name__ == "__main__":
    main()
