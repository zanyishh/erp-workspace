"""Real native GL/party-ledger bridge, with synthetic data on native-test only."""
import os
import unittest
from decimal import Decimal

import frappe
from erp_extensions.migration import finance, service, settlements
from erp_extensions.tests.test_migration_contracts import HistoricalContractTests


class HistoricalFinanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("NATIVE_TEST_SITE", "native-test.localhost") != "native-test.localhost":
            raise RuntimeError("Financial tests require native-test.localhost")
        os.chdir("/home/frappe/frappe-bench/sites")
        frappe.init(site="native-test.localhost", sites_path=".")
        frappe.connect()
        try:
            frappe.set_user("Administrator")
            from erp_extensions.migration.install import install
            install()
            finance.install()
            settlements.install()
            frappe.db.commit()
        finally:
            frappe.destroy()

    def setUp(self):
        if os.environ.get("NATIVE_TEST_SITE", "native-test.localhost") != "native-test.localhost":
            self.fail("Financial tests require native-test.localhost")
        os.chdir("/home/frappe/frappe-bench/sites")
        frappe.init(site="native-test.localhost", sites_path=".")
        frappe.connect()
        self.addCleanup(self.cleanup)
        frappe.set_user("Administrator")
        self.company = "ERP Native Verification"
        companies = [self.company, "ERP Knitting Verification"]
        self.suffix = frappe.generate_hash(length=8)
        for i in (3, 4):
            companies.append(frappe.get_doc({"doctype": "Company", "company_name": f"Synthetic Finance {i} {self.suffix}",
                "abbr": f"F{i}{self.suffix}", "default_currency": "INR", "country": "India"}).insert().name)
        fixture = HistoricalContractTests()
        scope = fixture.scope()
        scope.update(source_instance="finance-" + self.suffix, allowed_users=["Administrator"],
                     company_bindings={str(i + 1): c for i, c in enumerate(companies)})
        self.scope = service.create_scope(scope)
        finance.configure_books(self.scope, [{"source_company_id": str(c), "source_book": str(b),
            "finance_book": f"Synthetic {self.suffix} {c} book {b}"} for c in range(1, 5) for b in range(3)])
        self.customer = frappe.get_doc({"doctype": "Customer", "customer_name": "Synthetic bill-to " + self.suffix,
            "customer_type": "Company", "customer_group": frappe.db.get_value("Customer Group", {"is_group": 0}, "name"),
            "territory": frappe.db.get_value("Territory", {"is_group": 0}, "name")}).insert().name
        account = lambda kind: frappe.db.get_value("Account", {"company": self.company, "account_type": kind, "is_group": 0}, "name")
        self.mapping = {"source_company_id": "1", "source_book": "1", "company": self.company,
            "finance_book": f"Synthetic {self.suffix} 1 book 1", "currency": "INR", "party_type": "Customer",
            "party": self.customer, "accounting_party_id": "7", "party_account": account("Receivable"),
            "counter_account": frappe.db.get_value("Account", {"company": self.company, "root_type": "Income", "is_group": 0}, "name"),
            "counter_basis": "native_document_type", "cost_center": frappe.get_cached_value("Company", self.company, "cost_center")}
        self.cash = account("Cash")
        values = fixture.record(namespace="accv2.voucher", family="voucher", source_book="1",
            original_date_raw="2026-05-03", business_data={"fields": {"reference": "SYN-009"}, "financial": {
                "voucher_type": "sales", "amount": "123.45", "currency": "INR", "entry_type": "debit",
                "accounting_party_id": "7", "invoice_party_id": "8", "source_reference": "SYN-009", "cancelled": False}})
        self.record = service.store_record(self.scope, values)["name"]

    def cleanup(self):
        frappe.db.rollback()
        frappe.clear_cache(user="Administrator")
        frappe.destroy()

    def payment(self, journal, book=None):
        return frappe.get_doc({"doctype": "Payment Entry", "company": self.company, "payment_type": "Receive",
            "posting_date": "2026-05-04", "finance_book": book, "party_type": "Customer", "party": self.customer,
            "paid_from": self.mapping["party_account"], "paid_to": self.cash,
            "paid_amount": 23.45, "received_amount": 23.45, "source_exchange_rate": 1, "target_exchange_rate": 1,
            "references": [{"reference_doctype": "Journal Entry", "reference_name": journal,
                "total_amount": 123.45, "outstanding_amount": 123.45, "allocated_amount": 23.45}]})

    def test_native_journal_is_idempotent_and_later_payment_keeps_its_book(self):
        result = finance.post_record(self.record, self.mapping)
        self.assertTrue(result["created"])
        repeated = finance.post_record(self.record, self.mapping)
        self.assertFalse(repeated["created"])
        self.assertEqual(repeated["journal"], result["journal"])
        from erpnext.accounts.doctype.payment_entry.payment_entry import get_outstanding_on_journal_entry
        before, _ = get_outstanding_on_journal_entry(result["journal"], "Customer", self.customer)
        self.assertEqual(Decimal(str(before)), Decimal("123.45"))
        payment = self.payment(result["journal"])
        payment.insert()
        payment.submit()
        self.assertEqual(payment.finance_book, self.mapping["finance_book"])
        after, _ = get_outstanding_on_journal_entry(result["journal"], "Customer", self.customer)
        self.assertEqual(Decimal(str(after)), Decimal("100.00"))
        for doctype in ("GL Entry", "Payment Ledger Entry"):
            books = frappe.get_all(doctype, filters={"voucher_type": "Payment Entry", "voucher_no": payment.name}, pluck="finance_book")
            self.assertTrue(books)
            self.assertEqual(set(books), {self.mapping["finance_book"]})

    def test_native_payment_cannot_cross_books(self):
        result = finance.post_record(self.record, self.mapping)
        with self.assertRaises(frappe.ValidationError):
            self.payment(result["journal"], f"Synthetic {self.suffix} 1 book 0").insert()

    def test_native_party_control_uses_exact_saved_amount_and_authority_completeness(self):
        finance.post_record(self.record, self.mapping)
        controls = {"scope": self.scope, "native_journals_required": 1, "groups": [{"source_company_id": "1", "source_party_id": "7",
            "source_book": "1", "company": self.company, "finance_book": self.mapping["finance_book"], "native_signed_amount": "123.45",
            "target_parties": {"Customer": {"party": self.customer, "account": self.mapping["party_account"]}}}]}
        self.assertTrue(finance.verify_party_controls(self.scope, controls)["all_native_party_balances_equal"])
        controls["groups"][0]["native_signed_amount"] = "123"
        self.assertFalse(finance.verify_party_controls(self.scope, controls)["all_native_party_balances_equal"])

    def test_finance_book_picker_returns_only_selected_company_books(self):
        from erp_extensions import api
        rows = api.search_link("Finance Book", self.suffix, "Sales Invoice", "finance_book", {"company": self.company})
        self.assertEqual({row["value"] for row in rows}, {f"Synthetic {self.suffix} 1 book {i}" for i in range(3)})

    def test_client_flags_cannot_authorize_internal_binding_writes(self):
        for doctype, flag, guard in ((finance.BOOK_BINDING, "finance_binding_insert", finance.guard_book_binding),
                                     (settlements.DOCTYPE, "settlement_insert", settlements.guard_write)):
            doc = frappe.get_doc({"doctype": doctype})
            doc.flags[flag] = True
            with self.subTest(doctype=doctype), self.assertRaises(frappe.PermissionError):
                guard(doc, "before_insert")

    def test_outside_system_manager_cannot_read_binding_proofs(self):
        outside = frappe.get_doc({"doctype": "User", "email": f"outside-{self.suffix}@example.invalid", "first_name": "Synthetic outside",
            "send_welcome_email": 0, "roles": [{"role": "System Manager"}]}).insert().name
        row = frappe.get_doc(finance.BOOK_BINDING, frappe.db.get_value(finance.BOOK_BINDING, {"source_scope": self.scope}, "name"))
        self.assertFalse(finance.has_permission(row, "read", user=outside))
        self.assertEqual(finance.query_conditions(user=outside, doctype=finance.BOOK_BINDING), "1=0")

    def settlement_record(self, native_id, amount, adjusted, direction, kind, role="Customer"):
        mapping = dict(self.mapping)
        financial = {"voucher_type": kind, "amount": amount, "currency": "INR", "entry_type": direction,
            "accounting_party_id": "7", "source_adjusted_amount": adjusted, "cancelled": False}
        if kind != "sales":
            financial["general_ledger_id"] = "1"
            mapping.update(counter_basis="native_general_account", general_ledger_id="1")
        if role == "Supplier":
            supplier = frappe.get_doc({"doctype": "Supplier", "supplier_name": "Synthetic supplier " + self.suffix,
                "supplier_group": frappe.db.get_value("Supplier Group", {"is_group": 0}, "name"), "supplier_type": "Company"}).insert()
            mapping.update(party_type="Supplier", party=supplier.name,
                party_account=frappe.db.get_value("Account", {"company": self.company, "account_type": "Payable", "is_group": 0}, "name"))
        values = HistoricalContractTests().record(namespace="accv2.voucher", family="voucher", source_book="1", native_id=native_id,
            original_date_raw="2026-05-03", business_data={"fields": {}, "financial": financial})
        name = service.store_record(self.scope, values)["name"]
        finance.post_record(name, mapping)
        return name, mapping

    def apply_pair(self, first, second, amount="60"):
        bindings = dict([first, second])
        edges = [{"first": first[0], "second": second[0], "amount": amount}]
        result = settlements.apply_component(self.scope, "synthetic-component", bindings, edges, "a" * 64)
        again = settlements.apply_component(self.scope, "synthetic-component", bindings, edges, "a" * 64)
        self.assertFalse(again["created"])
        self.assertEqual(result["binding"], again["binding"])
        for name, mapping in bindings.items():
            posted = finance.post_record(name, mapping)
            self.assertFalse(posted["created"])
            self.assertEqual(str(frappe.db.get_value("Journal Entry", posted["journal"], "posting_date")), "2026-05-03")
        return result

    def test_same_account_settlement_preserves_native_authority_and_remaining_amount(self):
        sale = self.settlement_record("101", "100", "60", "debit", "sales")
        receipt = self.settlement_record("102", "60", "60", "credit", "receipt")
        result = self.apply_pair(sale, receipt)
        self.assertEqual(Decimal(result["outstanding_at_application"][sale[0]]), Decimal("40"))
        self.assertEqual(Decimal(result["outstanding_at_application"][receipt[0]]), Decimal("0"))
        self.assertEqual(result["offset_journals"], [])

    def test_cross_role_offset_is_current_dated_and_preserves_combined_net(self):
        sale = self.settlement_record("103", "100", "60", "debit", "sales")
        purchase = self.settlement_record("104", "60", "60", "credit", "purchase", "Supplier")
        result = self.apply_pair(sale, purchase)
        self.assertEqual(len(result["offset_journals"]), 1)
        self.assertEqual(str(frappe.db.get_value("Journal Entry", result["offset_journals"][0], "posting_date")), frappe.utils.today())
        self.assertEqual(Decimal(result["outstanding_at_application"][sale[0]]), Decimal("40"))
        self.assertEqual(Decimal(result["outstanding_at_application"][purchase[0]]), Decimal("0"))

    def test_cross_role_advance_offset_reconciles_both_native_payment_sides(self):
        payment = self.settlement_record("105", "60", "60", "debit", "payment", "Supplier")
        receipt = self.settlement_record("106", "60", "60", "credit", "receipt")
        result = self.apply_pair(payment, receipt)
        self.assertEqual(len(result["offset_journals"]), 1)
        self.assertTrue(all(Decimal(v) == 0 for v in result["outstanding_at_application"].values()))

