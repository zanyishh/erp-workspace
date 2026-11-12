"""Integration tests: run only on the dedicated local native test site."""
import os
import unittest

import frappe
from erp_extensions import api


TYPE = "Native Workspace Test Record"
ROW = "Native Workspace Test Row"
TRANSACTION = "Native Workspace Test Transaction"
APPROVAL = "Native Workspace Test Approval"


class NativeApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        site = os.environ.get("NATIVE_TEST_SITE", "native-test.localhost")
        if site != "native-test.localhost":
            raise RuntimeError("Native integration tests require the dedicated test site")
        os.chdir("/home/frappe/frappe-bench/sites")
        frappe.init(site=site, sites_path=".")
        frappe.connect()
        frappe.set_user("Administrator")
        from erp_extensions.setup import configure_test_site
        configure_test_site()
        if not frappe.db.exists("DocType", ROW):
            frappe.get_doc({"doctype": "DocType", "name": ROW, "module": "Custom", "custom": 1,
                "istable": 1, "fields": [{"fieldname": "description", "label": "Description", "fieldtype": "Data"}]}).insert()
        if not frappe.db.exists("DocType", TYPE):
            frappe.get_doc({"doctype": "DocType", "name": TYPE, "module": "Custom", "custom": 1,
                "autoname": "hash", "fields": [
                    {"fieldname": "title", "label": "Title", "fieldtype": "Data", "reqd": 1},
                    {"fieldname": "amount", "label": "Amount", "fieldtype": "Float"},
                    {"fieldname": "locked", "label": "Locked", "fieldtype": "Data", "read_only": 1},
                    {"fieldname": "rows", "label": "Rows", "fieldtype": "Table", "options": ROW}],
                "permissions": [{"role": "System Manager", "read": 1, "write": 1, "create": 1}]}).insert()
        if not frappe.db.exists("Role", "Native Test Reader"):
            frappe.get_doc({"doctype": "Role", "role_name": "Native Test Reader"}).insert()
        meta = frappe.get_doc("DocType", TYPE)
        if not any(p.role == "Native Test Reader" for p in meta.permissions):
            meta.append("permissions", {"role": "Native Test Reader", "read": 1})
        for permission in meta.permissions:
            if permission.role == "Native Test Reader":
                permission.update({"write": 0, "create": 0, "delete": 0, "submit": 0, "cancel": 0, "print": 0})
        meta.save()
        if not frappe.db.exists("User", "native-reader@example.invalid"):
            frappe.get_doc({"doctype": "User", "email": "native-reader@example.invalid",
                "first_name": "Native reader", "send_welcome_email": 0,
                "roles": [{"role": "Native Test Reader"}]}).insert()
        if not frappe.db.exists("Role", "Native Test Editor"):
            frappe.get_doc({"doctype": "Role", "role_name": "Native Test Editor"}).insert()
        meta = frappe.get_doc("DocType", TYPE)
        if not any(p.role == "Native Test Editor" for p in meta.permissions):
            meta.append("permissions", {"role": "Native Test Editor", "read": 1, "write": 1, "create": 0})
            meta.save()
        if not frappe.db.exists("User", "native-editor@example.invalid"):
            frappe.get_doc({"doctype": "User", "email": "native-editor@example.invalid",
                "first_name": "Native editor", "send_welcome_email": 0,
                "roles": [{"role": "Native Test Editor"}]}).insert()
        if not frappe.db.exists("Role", "Native Test Canceller"):
            frappe.get_doc({"doctype": "Role", "role_name": "Native Test Canceller"}).insert()
        if not frappe.db.exists("DocType", TRANSACTION):
            frappe.get_doc({"doctype":"DocType","name":TRANSACTION,"module":"Custom","custom":1,
                "autoname":"hash","is_submittable":1,
                "fields":[{"fieldname":"title","fieldtype":"Data","label":"Title","reqd":1}],
                "permissions":[{"role":"System Manager","read":1,"write":1,"create":1,"submit":1,"cancel":1},
                    {"role":"Native Test Canceller","read":1,"write":1,"create":0,"submit":1,"cancel":1}]}).insert()
        if not frappe.db.exists("User", "native-canceller@example.invalid"):
            frappe.get_doc({"doctype":"User","email":"native-canceller@example.invalid",
                "first_name":"Native canceller","send_welcome_email":0,
                "roles":[{"role":"Native Test Canceller"}]}).insert()
        meta = frappe.get_doc("DocType", TYPE)
        if not any(df.fieldname == "warehouse" for df in meta.fields):
            meta.append("fields", {"fieldname":"warehouse","fieldtype":"Link","options":"Warehouse","label":"Warehouse"})
            meta.save()
        if not any(df.fieldname == "display_only" for df in meta.fields):
            meta.append("fields", {"fieldname":"display_only","fieldtype":"Read Only","label":"Display only"})
            meta.save()
        warehouses = frappe.get_all("Warehouse", filters={"company":"ERP Native Verification","is_group":0}, pluck="name", order_by="name")
        cls.allowed_warehouse, cls.denied_warehouse = warehouses[:2]
        if not frappe.db.exists("User Permission", {"user":"native-editor@example.invalid","allow":"Warehouse","for_value":cls.allowed_warehouse}):
            frappe.get_doc({"doctype":"User Permission","user":"native-editor@example.invalid",
                "allow":"Warehouse","for_value":cls.allowed_warehouse,"apply_to_all_doctypes":1}).insert()
        if not frappe.db.exists("DocType", APPROVAL):
            frappe.get_doc({"doctype":"DocType","name":APPROVAL,"module":"Custom","custom":1,
                "autoname":"hash","fields":[{"fieldname":"title","label":"Title","fieldtype":"Data","reqd":1}],
                "permissions":[{"role":"System Manager","read":1,"write":1,"create":1}]}).insert()
        for state in ("Native Draft", "Native Approved"):
            if not frappe.db.exists("Workflow State", state):
                frappe.get_doc({"doctype":"Workflow State","workflow_state_name":state}).insert()
        if not frappe.db.exists("Workflow Action Master", "Native Approve"):
            frappe.get_doc({"doctype":"Workflow Action Master","workflow_action_name":"Native Approve"}).insert()
        if not frappe.db.exists("Workflow", "Native Test Approval"):
            frappe.get_doc({"doctype":"Workflow","workflow_name":"Native Test Approval","document_type":APPROVAL,
                "is_active":1,"workflow_state_field":"workflow_state","send_email_alert":0,
                "states":[{"state":"Native Draft","doc_status":"0","allow_edit":"System Manager"},
                    {"state":"Native Approved","doc_status":"0","allow_edit":"System Manager"}],
                "transitions":[{"state":"Native Draft","action":"Native Approve","next_state":"Native Approved",
                    "allowed":"System Manager","allow_self_approval":1}]}).insert()
        if not frappe.db.exists("Role", "Native Draft Creator"):
            frappe.get_doc({"doctype":"Role","role_name":"Native Draft Creator"}).insert()
        from frappe.permissions import add_permission, update_permission_property
        if not frappe.db.exists("Custom DocPerm", {"parent":"Sales Invoice","role":"Native Draft Creator"}):
            add_permission("Sales Invoice","Native Draft Creator")
            for permission in ("read","write","create"):
                update_permission_property("Sales Invoice","Native Draft Creator",0,permission,1)
            update_permission_property("Sales Invoice","Native Draft Creator",0,"submit",0)
        if not frappe.db.exists("User", "native-mapper@example.invalid"):
            frappe.get_doc({"doctype":"User","email":"native-mapper@example.invalid","first_name":"Native mapper",
                "send_welcome_email":0,"roles":[{"role":"Sales User"},{"role":"Native Draft Creator"}]}).insert()
        frappe.db.commit()

    def setUp(self):
        frappe.set_user("Administrator")

    def tearDown(self):
        frappe.set_user("Administrator")
        frappe.db.rollback()

    @classmethod
    def tearDownClass(cls):
        frappe.destroy()

    def create(self, title="Native draft", **values):
        doc = api.document(TYPE)["doc"]
        doc.update(title=title, **values)
        return api.save(doc)["doc"]

    def test_activity_comments_and_private_attachment_roundtrip(self):
        import base64
        doc = self.create()
        api.add_comment(TYPE, doc["name"], "Review this native document")
        uploaded = api.upload_attachment(TYPE, doc["name"], "native-proof.txt",
            base64.b64encode(b"Native private attachment").decode())
        self.assertEqual(uploaded["is_private"], 1)
        activity = api.activity(TYPE, doc["name"])
        self.assertTrue(any("Review this native document" in c["content"] for c in activity["comments"]))
        self.assertIn(uploaded["name"], [f["name"] for f in activity["attachments"]])
        result = api.attachment(TYPE, doc["name"], uploaded["name"])
        self.assertEqual(base64.b64decode(result["content"]), b"Native private attachment")
        other = self.create(title="Other")
        with self.assertRaises(frappe.PermissionError):
            api.attachment(TYPE, other["name"], uploaded["name"])
        frappe.set_user("native-reader@example.invalid")
        self.assertEqual(api.attachment(TYPE, doc["name"], uploaded["name"])["name"], "native-proof.txt")
        with self.assertRaises(frappe.PermissionError):
            api.upload_attachment(TYPE, doc["name"], "denied.txt", "eA==")
        frappe.set_user("Administrator")
        api.remove_attachment(TYPE, doc["name"], uploaded["name"])
        self.assertFalse(frappe.db.exists("File", uploaded["name"]))

    def test_reports_reject_explicit_prepared_report_identifiers(self):
        with self.assertRaises(frappe.PermissionError):
            api.run_report("General Ledger", {"prepared_report_name":"FOREIGN-RESULT"})

    def test_private_files_keep_their_exact_bytes(self):
        import base64
        doc = self.create()
        for filename, raw in [("bom.txt", b"\xef\xbb\xbfNative proof"), ("windows.csv",b"\x80 Amount")]:
            uploaded=api.upload_attachment(TYPE,doc["name"],filename,base64.b64encode(raw).decode())
            result=api.attachment(TYPE,doc["name"],uploaded["name"])
            self.assertEqual(base64.b64decode(result["content"]),raw)
            api.remove_attachment(TYPE,doc["name"],uploaded["name"])

    def test_activity_does_not_accept_guests_or_blank_comments(self):
        doc = self.create()
        with self.assertRaises(frappe.ValidationError):
            api.add_comment(TYPE, doc["name"], "  ")
        frappe.set_user("Guest")
        with self.assertRaises(frappe.PermissionError):
            api.activity(TYPE, doc["name"])

    def test_native_assignments_use_the_standard_todo_lifecycle(self):
        doc = self.create()
        user = "native-reader@example.invalid"
        api.assign(TYPE, doc["name"], user)
        self.assertIn(user, [a["owner"] for a in api.activity(TYPE,doc["name"])["assignments"]])
        api.unassign(TYPE, doc["name"], user)
        self.assertNotIn(user, [a["owner"] for a in api.activity(TYPE,doc["name"])["assignments"]])

    def test_native_print_returns_a_real_pdf_and_checks_print_permission(self):
        import base64
        doc = self.create()
        result = api.print_pdf(TYPE, doc["name"])
        self.assertTrue(base64.b64decode(result["content"]).startswith(b"%PDF-"))
        frappe.set_user("native-reader@example.invalid")
        with self.assertRaises(frappe.PermissionError):
            api.print_pdf(TYPE, doc["name"])

    def test_no_item_calculator_is_offered_for_journal_entries(self):
        self.assertFalse(api.schema("Journal Entry")["preparable"])
        with self.assertRaisesRegex(frappe.ValidationError, "Calculation refresh"):
            api.prepare({"doctype":"Journal Entry","__islocal":1})

    def test_conditional_metadata_is_data_and_resolves_current_environment(self):
        field = api._field_conditions({"depends_on":"eval:doc.name == frappe.session.user"})
        self.assertEqual(field["depends_on"]["args"][1], {"op":"literal","value":"Administrator"})
        self.assertEqual(api._field_conditions({"depends_on":"customer"}),
            {"depends_on":{"op":"field","name":"customer"}})

    def test_linked_drafts_reject_stale_sources_and_foreign_rows(self):
        source = self.create(rows=[{"doctype":ROW,"description":"Source row"}])
        derived = api.new_from(TYPE,source["name"],"Duplicate",source["modified"])["doc"]
        with self.assertRaises(frappe.PermissionError):
            api.save({"doctype":TYPE,"__islocal":1,"__native_origin":derived["__native_origin"],
                "rows":[{"doctype":ROW,"name":source["rows"][0]["name"],"description":"Forged"}]})
        api.save(dict(source,title="Changed source"))
        with self.assertRaises(frappe.TimestampMismatchError):
            api.save({"doctype":TYPE,"__islocal":1,"__native_origin":derived["__native_origin"]})

    def test_numeric_document_ids_are_native_string_identities(self):
        saved = api.save({"doctype":"Ledger Health","__islocal":1})["doc"]
        self.assertIsInstance(saved["name"],str)
        rows = api.records("Ledger Health")
        self.assertTrue(all(isinstance(row["name"],str) for row in rows))
        loaded = api.document("Ledger Health",saved["name"])["doc"]
        self.assertEqual(loaded["name"],saved["name"])
        copied = api.new_from("Ledger Health",saved["name"],"Duplicate",saved["modified"])["doc"]
        self.assertIsInstance(copied["__native_origin"]["name"],str)

    def test_native_create_and_edit_persist_through_frappe(self):
        doc = self.create(amount=12.5, rows=[{"doctype": ROW, "description": "First"}])
        self.assertEqual(frappe.get_doc(TYPE, doc["name"]).amount, 12.5)
        doc["title"] = "Edited natively"
        saved = api.save(doc)["doc"]
        self.assertEqual(api.document(TYPE, saved["name"])["doc"]["title"], "Edited natively")
        self.assertEqual(saved["rows"][0]["description"], "First")

    def test_stale_native_save_does_not_overwrite_another_edit(self):
        first = self.create()
        concurrent = dict(first, title="Other edit")
        api.save(concurrent)
        first["title"] = "Stale edit"
        with self.assertRaises(frappe.TimestampMismatchError):
            api.save(first)
        self.assertEqual(frappe.get_doc(TYPE, first["name"]).title, "Other edit")

    def test_read_only_field_type_is_locked_even_without_a_flag(self):
        field = next(f for f in api.schema(TYPE)["fields"] if f["fieldname"] == "display_only")
        self.assertTrue(field["read_only"])
        with self.assertRaises(frappe.PermissionError):
            self.create(display_only="Forged")

    def test_readonly_field_cannot_be_injected(self):
        with self.assertRaises(frappe.PermissionError):
            self.create(locked="forged")

    def test_nonfinite_numeric_value_is_rejected(self):
        with self.assertRaises(frappe.ValidationError):
            self.create(amount="NaN")

    def test_foreign_child_identifier_cannot_be_attached(self):
        first = self.create(rows=[{"doctype": ROW, "description": "Owned by first"}])
        second = self.create()
        second["rows"] = first["rows"]
        with self.assertRaises(frappe.PermissionError):
            api.save(second)
        self.assertEqual(frappe.get_doc(TYPE, first["name"]).rows[0].description, "Owned by first")

    def test_public_session_status_exposes_only_authentication_state(self):
        frappe.set_user("Guest")
        self.assertEqual(api.session_status(), {"signed_in":False})
        frappe.set_user("Administrator")
        self.assertEqual(api.session_status(), {"signed_in":True})

    def test_guest_cannot_read_or_create_native_documents(self):
        frappe.set_user("Guest")
        with self.assertRaises(frappe.PermissionError):
            api.document(TYPE)

    def test_readonly_user_can_open_but_cannot_save(self):
        doc = self.create()
        frappe.set_user("native-reader@example.invalid")
        loaded = api.document(TYPE, doc["name"])
        self.assertEqual(loaded["doc"]["title"], "Native draft")
        self.assertFalse(loaded["permissions"].get("write"))
        with self.assertRaises(frappe.PermissionError):
            api.save(dict(loaded["doc"], title="Denied"))

    def test_new_child_defaults_come_from_the_server(self):
        parent = api.document(TYPE)["doc"]
        child = api.new_row(parent, "rows")["doc"]
        self.assertEqual(child["doctype"], ROW)
        self.assertTrue(child["__islocal"])
        self.assertFalse(child.get("name"))

    def test_existing_document_editor_can_add_rows_without_parent_create_permission(self):
        doc = self.create()
        frappe.set_user("native-editor@example.invalid")
        loaded = api.document(TYPE, doc["name"])["doc"]
        child = api.new_row(loaded, "rows")["doc"]
        child["description"] = "Added with parent write permission"
        loaded["rows"] = [child]
        saved = api.save(loaded)["doc"]
        self.assertEqual(saved["rows"][0]["description"], "Added with parent write permission")

    def test_authorized_editor_can_cancel_an_existing_submitted_transaction(self):
        draft = api.document(TRANSACTION)["doc"]
        draft["title"] = "Native lifecycle"
        saved = api.save(draft)["doc"]
        submitted = api.save(saved, action="Submit")["doc"]
        self.assertEqual(submitted["docstatus"], 1)
        frappe.set_user("native-canceller@example.invalid")
        current = api.document(TRANSACTION, submitted["name"])
        self.assertTrue(current["permissions"].get("cancel"))
        cancelled = api.save(current["doc"], action="Cancel")["doc"]
        self.assertEqual(cancelled["docstatus"], 2)

    def test_reordered_child_rows_keep_their_order_after_reopening(self):
        doc = self.create(rows=[{"doctype":ROW,"description":"First"},{"doctype":ROW,"description":"Second"}])
        doc["rows"] = list(reversed(doc["rows"]))
        saved = api.save(doc)["doc"]
        reopened = api.document(TYPE, saved["name"])["doc"]
        self.assertEqual([r["description"] for r in reopened["rows"]], ["Second", "First"])
        self.assertEqual([r["idx"] for r in reopened["rows"]], [1, 2])

    def test_prepare_rechecks_permissions_after_link_changes(self):
        doc = self.create(warehouse=self.allowed_warehouse)
        frappe.set_user("native-editor@example.invalid")
        loaded = api.document(TYPE, doc["name"])["doc"]
        loaded["warehouse"] = self.denied_warehouse
        with self.assertRaises(frappe.PermissionError):
            api.prepare(loaded)

    def test_stale_workflow_action_cannot_approve_changed_content(self):
        draft = api.document(APPROVAL)["doc"]
        draft["title"] = "Original reviewed content"
        saved = api.save(draft)["doc"]
        newer = api.save(dict(saved, title="Changed after review"))["doc"]
        with self.assertRaises(frappe.TimestampMismatchError):
            api.transition(APPROVAL, saved["name"], "Native Approve", modified=saved["modified"])
        current = api.document(APPROVAL, saved["name"])["doc"]
        self.assertEqual(current["workflow_state"], "Native Draft")
        approved = api.transition(APPROVAL, newer["name"], "Native Approve", modified=newer["modified"])["doc"]
        self.assertEqual(approved["workflow_state"], "Native Approved")

    def test_sales_invoice_party_item_defaults_and_ledger_posting(self):
        suffix = frappe.generate_hash(length=8)
        company = "ERP Native Verification"
        group = frappe.db.get_value("Customer Group", {"is_group":0}, "name")
        territory = frappe.db.get_value("Territory", {"is_group":0}, "name")
        customer = api.save({"doctype":"Customer","__islocal":1,"customer_name":"Native Customer "+suffix,
            "customer_type":"Company","customer_group":group,"territory":territory})["doc"]
        item_group = frappe.db.get_value("Item Group", {"is_group":0}, "name")
        item = api.save({"doctype":"Item","__islocal":1,"item_code":"NATIVE-SERVICE-"+suffix,
            "item_name":"Native service","item_group":item_group,"stock_uom":"Nos","is_stock_item":0})["doc"]
        price_list = frappe.db.get_value("Price List", {"selling":1,"enabled":1}, "name")
        api.save({"doctype":"Item Price","__islocal":1,"item_code":item["name"],"price_list":price_list,"price_list_rate":100})
        values = {"doctype":"Sales Invoice","__islocal":1,"company":company,"customer":customer["name"],
            "selling_price_list":price_list,"posting_date":frappe.utils.today()}
        party = api.party_defaults(values)["doc"]
        self.assertTrue(party["debit_to"])
        values.update(currency=party["currency"],conversion_rate=1,debit_to=party["debit_to"])
        row = api.item_defaults(values,"items",{"doctype":"Sales Invoice Item","item_code":item["name"],"qty":2})["doc"]
        self.assertEqual(row["rate"],100)
        self.assertEqual(frappe.db.count("Item Price", {"item_code":item["name"]}),1)
        values["items"] = [{k:row[k] for k in ("item_code","qty","rate","uom","conversion_factor","income_account","cost_center") if k in row}]
        saved = api.save(values)["doc"]
        self.assertEqual(saved["grand_total"],200)
        posted = api.save({"doctype":"Sales Invoice","name":saved["name"],"modified":saved["modified"]},"Submit")["doc"]
        self.assertEqual(posted["docstatus"],1)
        ledger = frappe.get_all("GL Entry",filters={"voucher_no":posted["name"],"is_cancelled":0},fields=["debit","credit"])
        self.assertEqual(sum(r.debit for r in ledger),200)
        self.assertEqual(sum(r.credit for r in ledger),200)
        credit = api.new_from("Sales Invoice",posted["name"],"Credit Note",posted["modified"])["doc"]
        self.assertEqual(credit["return_against"],posted["name"])
        row = credit["items"][0]
        saved_credit = api.save({"doctype":"Sales Invoice","__islocal":1,
            "__native_origin":credit["__native_origin"],"items":[{"doctype":"Sales Invoice Item","name":row["name"],"qty":row["qty"]}]})["doc"]
        self.assertEqual(saved_credit["return_against"],posted["name"])
        self.assertEqual(saved_credit["is_return"],1)
        self.assertEqual(saved_credit["items"][0]["qty"],-2)
        self.assertNotEqual(saved_credit["items"][0]["name"],posted["items"][0]["name"])
        self.assertEqual(frappe.get_doc("Sales Invoice",posted["name"]).items[0].qty,2)
        order = api.save({"doctype":"Sales Order","__islocal":1,"company":company,"customer":customer["name"],
            "delivery_date":frappe.utils.today(),"currency":"INR","conversion_rate":1,
            "items":[{"doctype":"Sales Order Item","item_code":item["name"],"qty":2,"rate":100,
                "uom":"Nos","delivery_date":frappe.utils.today()}]})["doc"]
        order = api.save({"doctype":"Sales Order","name":order["name"],"modified":order["modified"]},"Submit")["doc"]
        frappe.set_user("native-mapper@example.invalid")
        linked = api.new_from("Sales Order",order["name"],"Sales Invoice",order["modified"])["doc"]
        payload = {"doctype":"Sales Invoice","__islocal":1,"__native_origin":linked["__native_origin"]}
        candidate = api._editable(payload)
        self.assertFalse(candidate.flags.ignore_permissions)
        self.assertFalse(candidate.has_permission("submit"))
        with self.assertRaises(frappe.PermissionError):
            api.save(payload,"Submit")
        saved_linked=api.save(payload)["doc"]
        self.assertEqual(saved_linked["items"][0]["so_detail"],order["items"][0]["name"])
        self.assertEqual(saved_linked["items"][0]["sales_order"],order["name"])
        frappe.set_user("Administrator")
        settings=frappe.get_doc("Stock Settings")
        settings.auto_insert_price_list_rate_if_missing=1
        settings.save()
        frappe.db.delete("Item Price", {"item_code":item["name"]})
        api.new_from("Sales Order",order["name"],"Sales Invoice",order["modified"])
        self.assertEqual(frappe.db.count("Item Price", {"item_code":item["name"]}),0)
        self.assertEqual(frappe.get_cached_doc("Stock Settings").auto_insert_price_list_rate_if_missing,1)
        self.assertEqual(frappe.db.get_single_value("Stock Settings","auto_insert_price_list_rate_if_missing"),1)
        frappe.db.set_value("Sales Order",order["name"],{"per_billed":100,"per_delivered":100})
        frappe.db.set_value("Sales Order Item",order["items"][0]["name"],{"delivered_qty":2,"billed_amt":200})
        fulfilled=frappe.get_doc("Sales Order",order["name"])
        duplicate=api.new_from("Sales Order",order["name"],"Duplicate",str(fulfilled.modified))["doc"]
        self.assertFalse(duplicate.get("per_billed"))
        self.assertFalse(duplicate["items"][0].get("delivered_qty"))




    def test_native_stock_receipt_and_transfer_update_real_stock_ledgers(self):
        company="ERP Native Verification"
        suffix=frappe.generate_hash(length=8)
        item=api.save({"doctype":"Item","__islocal":1,"item_code":"NATIVE-STOCK-"+suffix,
            "item_name":"Native stock item","item_group":frappe.db.get_value("Item Group",{"is_group":0},"name"),
            "stock_uom":"Nos","is_stock_item":1})["doc"]
        requested = api.item_defaults({"doctype":"Material Request","__islocal":1,"company":company,"material_request_type":"Purchase"},
            "items",{"doctype":"Material Request Item","item_code":item["name"],"qty":3})["doc"]
        self.assertEqual(requested["stock_uom"],"Nos")
        self.assertFalse(api.schema("Material Request")["preparable"])
        warehouses=frappe.get_all("Warehouse",filters={"company":company,"is_group":0,"warehouse_type":["!=","Transit"]},pluck="name")[:2]
        self.assertEqual(len(warehouses),2)
        common={"doctype":"Stock Entry Detail","item_code":item["name"],"qty":5,"uom":"Nos","conversion_factor":1,
            "expense_account":frappe.get_cached_value("Company",company,"stock_adjustment_account"),
            "cost_center":frappe.get_cached_value("Company",company,"cost_center")}
        receipt=api.save({"doctype":"Stock Entry","__islocal":1,"company":company,
            "stock_entry_type":"Material Receipt","items":[dict(common,t_warehouse=warehouses[0],basic_rate=100)]})["doc"]
        receipt=api.save({"doctype":"Stock Entry","name":receipt["name"],"modified":receipt["modified"]},"Submit")["doc"]
        transfer=api.save({"doctype":"Stock Entry","__islocal":1,"company":company,
            "stock_entry_type":"Material Transfer","items":[dict(common,s_warehouse=warehouses[0],t_warehouse=warehouses[1],qty=2)]})["doc"]
        transfer=api.save({"doctype":"Stock Entry","name":transfer["name"],"modified":transfer["modified"]},"Submit")["doc"]
        self.assertEqual(frappe.db.get_value("Bin",{"item_code":item["name"],"warehouse":warehouses[0]},"actual_qty"),3)
        self.assertEqual(frappe.db.get_value("Bin",{"item_code":item["name"],"warehouse":warehouses[1]},"actual_qty"),2)
        self.assertEqual(frappe.db.count("Stock Ledger Entry",{"voucher_no":["in",[receipt["name"],transfer["name"]]],"is_cancelled":0}),3)

    def test_quotation_preview_does_not_implicitly_create_a_customer(self):
        suffix=frappe.generate_hash(length=8)
        lead=api.save({"doctype":"Lead","__islocal":1,"first_name":"Native preview "+suffix})["doc"]
        item=api.save({"doctype":"Item","__islocal":1,"item_code":"NATIVE-LEAD-"+suffix,
            "item_group":frappe.db.get_value("Item Group",{"is_group":0},"name"),"stock_uom":"Nos","is_stock_item":0})["doc"]
        quote=api.save({"doctype":"Quotation","__islocal":1,"company":"ERP Native Verification", "quotation_to":"Lead", "party_name":lead["name"],
            "items":[{"doctype":"Quotation Item","item_code":item["name"],"qty":1,"rate":100,"uom":"Nos"}]})["doc"]
        quote=api.save({"doctype":"Quotation","name":quote["name"],"modified":quote["modified"]},"Submit")["doc"]
        before=frappe.db.count("Customer")
        with self.assertRaisesRegex(frappe.ValidationError,"Create and save a customer"):
            api.new_from("Quotation",quote["name"],"Sales Order",quote["modified"])
        self.assertEqual(frappe.db.count("Customer"),before)

    def test_native_general_ledger_uses_server_filters_and_real_postings(self):
        definition = api.report_definition("General Ledger", company="ERP Native Verification")
        self.assertIn("from_date", [f["fieldname"] for f in definition["fields"]])
        cash = frappe.db.get_value("Account", {"company":"ERP Native Verification","is_group":0,"account_type":"Cash"}, "name")
        expense = frappe.db.get_value("Account", {"company":"ERP Native Verification","is_group":0,"root_type":"Expense"}, "name")
        journal = {"doctype":"Journal Entry","__islocal":1}
        journal.update(company="ERP Native Verification", posting_date=frappe.utils.today(),
            accounts=[{"doctype":"Journal Entry Account","account":expense,"debit_in_account_currency":125.5},
                {"doctype":"Journal Entry Account","account":cash,"credit_in_account_currency":125.5}])
        saved = api.save(journal)["doc"]
        posted = api.save({"doctype":"Journal Entry","name":saved["name"],"modified":saved["modified"]}, action="Submit")["doc"]
        result = api.run_report("General Ledger", {"company":"ERP Native Verification",
            "from_date":frappe.utils.today(),"to_date":frappe.utils.today(),"categorize_by":"Categorize by Voucher (Consolidated)"})
        entries = [row for row in result["result"] if row.get("voucher_no") == posted["name"]]
        self.assertEqual(sum(row.get("debit",0) for row in entries), 125.5)
        self.assertEqual(sum(row.get("credit",0) for row in entries), 125.5)

    def test_unpermitted_user_cannot_run_financial_reports(self):
        frappe.set_user("native-reader@example.invalid")
        with self.assertRaises(frappe.PermissionError):
            api.report_definition("General Ledger")

    def test_native_prepared_report_queue_belongs_to_the_requesting_user(self):
        report = frappe.get_doc({"doctype":"Report","report_name":"Native Prepared Verification",
            "report_type":"Query Report","ref_doctype":TYPE,"module":"Custom","is_standard":"No",
            "prepared_report":1,"query":"select name as record from `tabNative Workspace Test Record`",
            "roles":[{"role":"System Manager"}]}).insert()
        queued = api.queue_report(report.name, {})
        job = frappe.get_doc("Prepared Report", queued["name"])
        self.assertEqual(job.owner, "Administrator")
        self.assertEqual(job.report_name, report.name)


if __name__ == "__main__":
    unittest.main()
