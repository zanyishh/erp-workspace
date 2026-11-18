"""Bounded knitting history and complete summaries, using rollback-only synthetic rows."""
from datetime import datetime, timedelta
from decimal import Decimal
from unittest.mock import patch

import frappe

from erp_extensions.tests import test_knitting as fixtures


class RegisterTests(fixtures.KnittingTests):
    def test_job_origin_is_known_for_empty_programmes_without_exposing_source_record(self):
        self.fixtures()
        api = self.knitting()
        cases = [(None, [], False), ('SYNTHETIC-ORIGINAL-RECORD', [], True),
                 (None, [{'id': 'preserved', 'source_fabric_id': '7', 'target_kg': '0.000'}], True)]
        for marker, programme, expected in cases:
            frappe.db.set_value('Knitting Job', self.job,
                {'source_record': marker, 'programme': frappe.as_json(programme)}, update_modified=False)
            pages = [api.register(fixtures.COMPANY, 'jobs', query=self.job)['rows'],
                     api.snapshot(fixtures.COMPANY, self.job)['jobs'],
                     api.lookup(fixtures.COMPANY, 'Job', query=self.job)['rows'],
                     api.lookup(fixtures.COMPANY, 'ClosingJob', query=self.job)['rows']]
            for rows in pages:
                row = next(row for row in rows if row['name'] == self.job)
                self.assertIs(row.get('is_imported'), expected)
                self.assertNotIn('source_record', row)

    def seed(self, doctype, name, **values):
        # Large read fixtures bypass posting only inside this rollback-only test.
        if frappe.local.site != "native-test.localhost":
            raise RuntimeError("Synthetic register fixtures require native-test.localhost")
        stamp = values.pop("creation", datetime(2020, 1, 1))
        doc = frappe.get_doc({"doctype": doctype, "name": name, "company": fixtures.COMPANY,
            "creation": stamp, "modified": stamp, "owner": "Administrator", "modified_by": "Administrator", **values})
        doc.db_insert()
        return doc.name

    def endpoints(self):
        api = self.knitting()
        for name in ("register", "overview", "roll"):
            self.assertTrue(callable(getattr(api, name, None)), f"Missing bounded knitting {name} endpoint")
        return api

    def test_register_reaches_old_jobs_and_applies_filters_before_paging(self):
        self.fixtures()
        prefix = "SYN-PAGE-JOB-" + frappe.generate_hash(length=7)
        programme = frappe.db.get_value("Knitting Job", self.job, "programme")
        names = [self.seed("Knitting Job", f"{prefix}-{n:04}", customer=self.customer,
            status="Completed" if n == 0 else "Running", material_mode="Customer", target_kg="1.000",
            programme=programme, revision=1, rate=10) for n in range(221)]
        snapshot = self.knitting().snapshot(fixtures.COMPANY)
        self.assertEqual(len(snapshot["jobs"]), 100, "Snapshot must be a bounded first page, not silently truncated history")
        self.assertTrue(snapshot["pagination"]["jobs"]["has_more"])
        api = self.endpoints()
        found = []
        for start, count in ((0, 100), (100, 100), (200, 21)):
            page = api.register(fixtures.COMPANY, "jobs", start=start, query=prefix)
            self.assertEqual(page["page"], {"start": start, "limit": 100, "has_more": start < 200, "total": 221})
            self.assertEqual(len(page["rows"]), count)
            found.extend(row.name for row in page["rows"])
        self.assertEqual(found, list(reversed(names)))
        matched = api.register(fixtures.COMPANY, "jobs", query=prefix, state="Completed")
        self.assertEqual([row.name for row in matched["rows"]], [names[0]])
        detail = api.snapshot(fixtures.COMPANY, names[0])
        self.assertEqual(detail["scope_job"], names[0])
        self.assertEqual(detail["jobs"][0].name, names[0])
        self.assertIn("workflow", detail["jobs"][0])
        summary = api.overview(fixtures.COMPANY)
        self.assertEqual(summary["jobs"], {"total": frappe.db.count("Knitting Job", {"company": fixtures.COMPANY}),
            "running": frappe.db.count("Knitting Job", {"company": fixtures.COMPANY, "status": "Running"})})

    def test_job_pages_and_recent_snapshot_follow_order_date_with_stable_ties(self):
        self.fixtures()
        prefix = 'SYN-DATED-' + frappe.generate_hash(length=7)
        programme = frappe.db.get_value('Knitting Job', self.job, 'programme')
        values = {'customer':self.customer, 'status':'Running', 'material_mode':'Customer',
            'target_kg':'1.000', 'programme':programme, 'revision':1}
        old = self.seed('Knitting Job', prefix+'-999', creation=datetime(2094,1,1), job_date='2090-01-01', **values)
        tied_a = self.seed('Knitting Job', prefix+'-001', creation=datetime(2090,1,1), job_date='2091-01-01', **values)
        tied_b = self.seed('Knitting Job', prefix+'-002', creation=datetime(2090,1,1), job_date='2091-01-01', **values)
        later_created = self.seed('Knitting Job', prefix+'-000', creation=datetime(2090,1,2), job_date='2091-01-01', **values)
        legacy = self.seed('Knitting Job', prefix+'-003', creation=datetime(2092,1,1), job_date=None, **values)
        expected = [legacy, later_created, tied_b, tied_a, old]
        from erp_extensions.knitting import registers
        with patch.object(registers, 'PAGE_SIZE', 2):
            pages = [self.endpoints().register(fixtures.COMPANY, 'jobs', query=prefix, start=start)
                for start in (0, 2, 4)]
            self.assertEqual([row.name for page in pages for row in page['rows']], expected)
            self.assertEqual([page['page']['has_more'] for page in pages], [True, True, False])
            self.assertEqual([row.name for row in self.knitting().snapshot(fixtures.COMPANY)['jobs']], expected[:2])
        self.assertEqual([row.name for row in self.knitting().lookup(fixtures.COMPANY, 'Job', query=prefix)['rows']], expected)

    def test_job_customer_titles_are_batched_and_keep_command_identity(self):
        self.fixtures()
        title = 'Readable synthetic customer'
        frappe.db.set_value('Customer', self.customer, 'customer_name', title)
        with patch.object(frappe, 'get_list', wraps=frappe.get_list) as reads:
            rows = self.knitting().register(fixtures.COMPANY, 'jobs', job=self.job)['rows']
        self.assertEqual((rows[0].customer, rows[0].get('customer_name')), (self.customer, title))
        title_reads = [call for call in reads.call_args_list if call.args[0]=='Customer'
            and call.kwargs.get('fields')==['name','customer_name']]
        self.assertEqual(len(title_reads), 1)
        self.assertEqual(self.knitting().snapshot(fixtures.COMPANY, self.job)['jobs'][0].get('customer_name'), title)
        for kind in ('Job', 'ClosingJob'):
            rows = self.knitting().lookup(fixtures.COMPANY, kind, query=self.job)['rows']
            self.assertEqual((rows[0].customer, rows[0].get('customer_name')), (self.customer, title))

    def test_customer_title_projection_never_returns_a_denied_party_name(self):
        self.fixtures()
        hidden = frappe.copy_doc(frappe.get_doc('Customer', self.customer))
        hidden.customer_name = 'Private customer title ' + frappe.generate_hash(length=8)
        hidden.insert()
        frappe.get_doc({'doctype':'User Permission', 'user':'knit-operator@example.invalid',
            'allow':'Customer', 'for_value':self.customer, 'apply_to_all_doctypes':1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        self.assertFalse(frappe.has_permission('Customer','read',doc=hidden.name))
        from erp_extensions.knitting import registers
        rows = [frappe._dict(customer=self.customer), frappe._dict(customer=hidden.name)]
        registers.customer_names(rows)
        self.assertEqual(rows[0].customer_name, self.customer)
        self.assertIsNone(rows[1].customer_name)
        self.assertEqual(rows[1].customer, hidden.name)

    def test_job_search_matches_readable_customer_titles_before_paging(self):
        self.fixtures()
        title = 'Searchable mill ' + frappe.generate_hash(length=8)
        frappe.db.set_value('Customer', self.customer, 'customer_name', title)
        prefix = 'SYN-TITLE-' + frappe.generate_hash(length=7)
        programme = frappe.db.get_value('Knitting Job', self.job, 'programme')
        names = [self.seed('Knitting Job', f'{prefix}-{n}', customer=self.customer, job_date='2090-01-01',
            programme=programme, status='Running', target_kg='1.000') for n in range(3)]
        from erp_extensions.knitting import registers
        with patch.object(registers, 'PAGE_SIZE', 2):
            first = self.knitting().register(fixtures.COMPANY, 'jobs', query=title)
            second = self.knitting().register(fixtures.COMPANY, 'jobs', query=title, start=2)
        self.assertEqual([row.name for row in first['rows']+second['rows']], [*reversed(names), self.job])
        self.assertEqual(first['page']['total'], 4)
        self.assertEqual({row.name for row in self.knitting().lookup(fixtures.COMPANY, 'Job', query=title)['rows']},
            {*names, self.job})
        denied = frappe.copy_doc(frappe.get_doc('Customer', self.customer))
        denied.customer_name = 'Private mill ' + frappe.generate_hash(length=8)
        denied.insert()
        self.seed('Knitting Job', prefix+'-hidden', customer=denied.name, programme=programme,
            status='Running', target_kg='1.000')
        frappe.get_doc({'doctype':'User Permission','user':'knit-operator@example.invalid',
            'allow':'Customer','for_value':self.customer,'apply_to_all_doctypes':1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        result = self.knitting().register(fixtures.COMPANY, 'jobs', query=denied.customer_name)
        self.assertEqual(result['rows'], [])
        self.assertEqual(result['page']['total'], 0)

    def test_roll_pages_and_exact_source_read_do_not_depend_on_recent_rows(self):
        self.fixtures(target="600.000")
        api = self.endpoints()
        prefix = "SYN-PAGE-ROLL-" + frappe.generate_hash(length=7)
        names = [self.seed("Knitting Roll", f"{prefix}-{n:04}", job=self.job, weight_kg="1.000",
            state="Released" if n == 0 else "Awaiting QC", warehouse=self.warehouse,
            fabric_item=self.items["fabric"]) for n in range(507)]
        first = api.snapshot(fixtures.COMPANY, self.job)
        self.assertEqual(len(first["rolls"]), 100)
        self.assertEqual(first["jobs"][0].workflow["inspection"]["count"], 506)
        found = []
        for start in range(0, 507, 100):
            result = api.register(fixtures.COMPANY, "rolls", job=self.job, start=start)
            found.extend(row.name for row in result["rows"])
            self.assertLessEqual(len(result["rows"]), 100)
            self.assertEqual(result["page"]["total"], 507)
        self.assertEqual(found, list(reversed(names)))
        selected = api.register(fixtures.COMPANY, "rolls", job=self.job, state="Released")
        self.assertEqual([r.name for r in selected["rows"]], [names[0]])
        self.assertEqual(api.roll(fixtures.COMPANY, self.job, names[0])["name"], names[0])
        self.assertEqual(api.roll(fixtures.COMPANY, self.job, names[0])["company"], fixtures.COMPANY)
        self.assertEqual(api.overview(fixtures.COMPANY)["rolls"], {"Awaiting QC": 506, "On Hold": 0, "Released": 1})
        original_job = self.job
        self.fixtures()
        with self.assertRaises(frappe.PermissionError):
            api.roll(fixtures.COMPANY, self.job, names[0])
        with self.assertRaises(frappe.PermissionError):
            api.roll("ERP Native Verification", original_job, names[0])

    def test_selected_job_lots_filter_allocations_before_paging_including_units(self):
        self.fixtures()
        api = self.endpoints()
        prefix = "SYN-PAGE-LOT-" + frappe.generate_hash(length=7)
        old = self.seed("Knitting Material Lot", prefix + "-0000", item=self.items["yarn"],
            party=self.customer, material_owner="Customer", warehouse=self.warehouse)
        for n in range(1, 121):
            self.seed("Knitting Material Lot", f"{prefix}-{n:04}", item=self.items["yarn"],
                party=self.customer, material_owner="Customer", warehouse=self.warehouse)
        event = self.seed("Knitting Event", prefix + "-EVENT", job=self.job, kind="adjust_yarn",
            occurred_at=datetime(2020, 1, 1), payload="{}", result="{}")
        self.seed("Knitting Ledger Entry", prefix + "-ENTRY", job=self.job, lot=old, event=event,
            warehouse=self.warehouse, custodian="Warehouse", quantity_kg="0.000", units="2")
        result = api.register(fixtures.COMPANY, "lots", job=self.job)
        self.assertEqual([r.name for r in result["rows"]], [old])
        self.assertEqual(result["rows"][0].allocations, [{"job": self.job, "quantity_kg": "0.000", "units": "2"}])
        self.assertEqual(api.snapshot(fixtures.COMPANY, self.job)["lots"][0].name, old)

    def test_overview_totals_and_production_drilldown_cover_more_than_five_hundred_events(self):
        self.fixtures()
        api = self.endpoints()
        before = api.overview(fixtures.COMPANY)
        prefix = "SYN-PAGE-EVENT-" + frappe.generate_hash(length=7)
        latest = datetime.fromisoformat(before["production"][-1]["date"]) if before["production"] else datetime.now()
        day = (latest + timedelta(days=30)).replace(hour=12, minute=0, second=0, microsecond=0)
        for n in range(505):
            self.seed("Knitting Event", f"{prefix}-{n:04}", job=self.job, kind="produce_bulk" if n % 2 else "produce",
                occurred_at=day, cancelled=0, payload="{}", result='{"quantity_kg":"1.125","amount":"777.00"}')
        self.seed("Knitting Event", prefix + "-CANCELLED", job=self.job, kind="produce", occurred_at=day,
            cancelled=1, payload="{}", result='{"quantity_kg":"1000.000"}')
        self.seed("Knitting Event", prefix + "-SUBCONTRACT", job=self.job, kind="subcontract_receive", occurred_at=day,
            cancelled=0, payload="{}", result='{"quantity_kg":"2000.000"}')
        self.seed("Knitting Event", prefix + "-DELIVERY", job=self.job, kind="deliver", occurred_at=day,
            cancelled=0, payload="{}", result='{"quantity_kg":"9.000"}')
        self.seed("Knitting Event", prefix + "-INVOICE", job=self.job, kind="invoice", occurred_at=day,
            cancelled=0, payload="{}", result='{"quantity_kg":"2.000"}')
        lot = self.receive("3.000")
        overview = api.overview(fixtures.COMPANY)
        self.assertEqual(overview["jobs"], before["jobs"])
        self.assertEqual(Decimal(overview["balances"]["yarn_kg"]), Decimal(before["balances"]["yarn_kg"]) + 3)
        self.assertEqual(Decimal(overview["balances"]["unbilled_kg"]), Decimal(before["balances"]["unbilled_kg"]) + 7)
        self.assertEqual(len(overview["production"]), 7)
        self.assertEqual(overview["production"][-1], {"date": str(day.date()), "quantity_kg": "568.125", "count": 505})
        self.assertTrue(all(row["quantity_kg"] == "0.000" and row["count"] == 0 for row in overview["production"][:-1]))
        found = []
        for start in range(0, 505, 100):
            page = api.register(fixtures.COMPANY, "events", production_date=str(day.date()), start=start)
            self.assertEqual(page["page"]["total"], 505)
            found.extend(page["rows"])
        self.assertEqual(len({row.name for row in found}), 505)
        self.assertEqual(sum(Decimal(row.result["quantity_kg"]) for row in found), Decimal("568.125"))
        self.assertTrue(lot)

    def test_register_contract_and_private_sources_remain_scoped(self):
        self.fixtures()
        api = self.endpoints()
        for kwargs in ({"collection":"User"}, {"collection":"events","start":-1},
                       {"collection":"events","start":True}, {"collection":"events","start":1.5},
                       {"collection":"events","start":"²"}, {"collection":"events","start":"9" * 10000},
                       {"collection":"events","start":1000001}, {"collection":"jobs","state":"anything"},
                       {"collection":"events","query":"x" * 121},
                       {"collection":"jobs","production_date":"2026-11-01"},
                       {"collection":"events","production_date":"2026-02-31"},
                       {"collection":"events","production_date":"9999-12-31"}):
            with self.subTest(kwargs=kwargs), self.assertRaises(frappe.ValidationError):
                api.register(fixtures.COMPANY, **kwargs)
        hidden = self.call("create_subcontract", {"job":self.job, "supplier":self.supplier(), "target_kg":"88", "rate":"10"})
        self.seed("Knitting Event", "SYN-HIDDEN-INVOICE-" + frappe.generate_hash(length=7), job=self.job,
            kind="invoice", cancelled=0, occurred_at=datetime.now(), payload="{}",
            result=frappe.as_json({"quantity_kg": "2.000", "purchase_order": hidden["data"]["purchase_order"]}))
        self.produce(self.receive())
        frappe.set_user("knit-checker@example.invalid")
        rows = api.register(fixtures.COMPANY, "events", job=self.job)["rows"]
        self.assertNotIn(hidden["event"], {row.name for row in rows})
        self.assertNotIn(hidden["data"]["purchase_order"], frappe.as_json(rows))
        overview = api.overview(fixtures.COMPANY)
        self.assertIsNone(overview["balances"]["unbilled_kg"])
        with self.assertRaises(frappe.PermissionError):
            api.register(fixtures.COMPANY, "rates")
        with self.assertRaises(frappe.PermissionError):
            api.register("Missing company", "jobs")
        frappe.set_user("knit-accountant@example.invalid")
        self.assertFalse(frappe.has_permission("Purchase Order", "read"))
        self.assertIsNone(api.overview(fixtures.COMPANY)["balances"]["unbilled_kg"])

    def test_production_summary_is_unavailable_when_a_source_voucher_is_hidden(self):
        self.fixtures(mode="Owned")
        api = self.endpoints()
        rolls = self.produce(self.receive(owner="Owned"))
        production = frappe.db.get_value("Knitting Roll", rolls[0], "production")
        frappe.db.set_value("Knitting Event", production, "occurred_at", "2033-01-04 12:00:00", update_modified=False)
        self.fixtures()
        visible_rolls = self.produce(self.receive())
        visible_production = frappe.db.get_value("Knitting Roll", visible_rolls[0], "production")
        frappe.db.set_value("Knitting Event", visible_production, "occurred_at", "2033-01-03 12:00:00", update_modified=False)
        owner_summary = api.overview(fixtures.COMPANY)
        self.assertEqual(owner_summary["production"][-1]["date"], "2033-01-04")
        self.assertEqual(owner_summary["production"][-1]["quantity_kg"], "88.000")
        frappe.set_user("knit-checker@example.invalid")
        self.assertFalse(frappe.has_permission("Stock Entry", "read"))
        self.assertFalse(frappe.has_permission("Knitting Event", "read", doc=production))
        self.assertTrue(frappe.has_permission("Knitting Event", "read", doc=visible_production))
        summary = api.overview(fixtures.COMPANY)
        self.assertIsNone(summary["production"], "A missing source is not zero or partial company production")
        self.assertNotIn("2033-01-04", frappe.as_json(summary))

    def assert_job_reconciliation_unavailable(self, job):
        api = self.endpoints()
        for result in (api.snapshot(fixtures.COMPANY, job)["jobs"],
                       api.register(fixtures.COMPANY, "jobs", query=job)["rows"],
                       api.lookup(fixtures.COMPANY, "Job", query=job)["rows"]):
            row = next(row for row in result if row.name == job)
            self.assertIsNone(row.balances)
            self.assertIs(row.reconciliation_available, False)
            self.assertNotIn("workflow", row)

    def test_hidden_stock_voucher_masks_only_affected_job_totals_and_preserves_qc(self):
        from erp_extensions.knitting import domain, permissions
        self.fixtures(mode="Owned")
        rolls = self.produce(self.receive(owner="Owned"))
        restricted_job = self.job
        authoritative = domain.balances(restricted_job)
        self.fixtures()
        visible_job = self.job
        frappe.set_user("knit-checker@example.invalid")
        self.assertFalse(frappe.has_permission("Stock Entry", "read"))
        self.assert_job_reconciliation_unavailable(restricted_job)
        page = self.endpoints().register(fixtures.COMPANY, "jobs")
        visible = next(row for row in page["rows"] if row.name == visible_job)
        self.assertEqual(visible.balances["produced_kg"], "0.000")
        self.assertNotEqual(visible.get("reconciliation_available"), False)
        self.assertEqual(self.endpoints().roll(fixtures.COMPANY, restricted_job, rolls[0])["state"], "Awaiting QC")
        with self.assertRaises(frappe.PermissionError):
            domain.balances(restricted_job)
        with permissions.service_write():
            self.assertEqual(domain.balances(restricted_job), authoritative)

    def test_hidden_invoice_source_and_incoming_transfer_cannot_feed_job_totals(self):
        from erp_extensions.knitting import domain
        self.fixtures()
        source_job = self.job
        hidden = self.call("create_subcontract", {"job":source_job, "supplier":self.supplier(), "target_kg":"88", "rate":"10"})
        order = hidden["data"]["purchase_order"]
        self.fixtures()
        target_job = self.job
        prefix = "SYN-HIDDEN-BALANCE-" + frappe.generate_hash(length=7)
        self.seed("Knitting Event", prefix + "-INVOICE", job=source_job, kind="invoice", cancelled=0,
            occurred_at=datetime.now(), payload="{}", result=frappe.as_json({"quantity_kg":"2.000", "purchase_order":order}))
        self.seed("Knitting Event", prefix + "-TRANSFER", job=source_job, target_job=target_job,
            kind="transfer_yarn", cancelled=0, occurred_at=datetime.now(), payload=frappe.as_json({"purchase_order":order}),
            result='{"quantity_kg":"3.000"}')
        frappe.set_user("knit-accountant@example.invalid")
        self.assertFalse(frappe.has_permission("Purchase Order", "read"))
        for job in (source_job, target_job):
            self.assert_job_reconciliation_unavailable(job)
            with self.assertRaises(frappe.PermissionError):
                domain.balances(job)

    def test_historical_reports_reject_restricted_cancelled_and_reversal_sources(self):
        from erp_extensions.knitting import reports
        self.fixtures(mode="Owned")
        rolls = self.produce(self.receive(owner="Owned"))
        event = frappe.db.get_value("Knitting Roll", rolls[0], "production")
        frappe.db.set_value("Knitting Event", event, "cancelled", 1, update_modified=False)
        self.seed("Knitting Event", "SYN-HIDDEN-REVERSAL-" + frappe.generate_hash(length=7), job=self.job,
            kind="reverse", cancelled=0, occurred_at=datetime.now(), reverses=event, payload="{}", result="{}")
        frappe.set_user("knit-accountant@example.invalid")
        with self.assertRaises(frappe.PermissionError):
            reports.event_rows(fixtures.COMPANY, reports.filters({"job":self.job, "to_date":"2033-01-05"}))

    def test_bulk_production_checks_nested_stock_vouchers(self):
        from erp_extensions.knitting import permissions
        self.fixtures(mode="Owned")
        lot = self.receive(owner="Owned")
        result = self.call("produce_bulk", {"job":self.job, "entries":[{"programme_line":"P1",
            "inputs":[{"lot":lot, "quantity_kg":"90.000"}], "weights_kg":["44.000", "44.000"],
            "loss_kg":"2.000", "warehouse":self.warehouse}]})
        event = frappe.get_doc("Knitting Event", result["event"])
        self.assertFalse(event.voucher_name)
        self.assertEqual(frappe.parse_json(event.result)["vouchers"][0]["voucher_type"], "Stock Entry")
        frappe.set_user("knit-checker@example.invalid")
        self.assertFalse(frappe.has_permission("Stock Entry", "read"))
        self.assertFalse(permissions.source_scope(event))
        with self.assertRaises(frappe.PermissionError):
            permissions.require_event_sources([event])
        self.assertEqual(self.endpoints().register(fixtures.COMPANY, "events", query=event.name)["rows"], [])
        self.assertIsNone(self.endpoints().overview(fixtures.COMPANY)["production"])
        self.assert_job_reconciliation_unavailable(self.job)
        self.assertEqual(self.endpoints().roll(fixtures.COMPANY, self.job, result["data"]["rolls"][0])["state"], "Awaiting QC")


for name in list(vars(fixtures.KnittingTests)):
    if name.startswith("test_"):
        setattr(RegisterTests, name, None)
