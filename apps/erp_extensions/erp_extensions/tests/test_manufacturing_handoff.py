"""Submitted General ERP material and manufacturing movements on the isolated site."""
import os
import unittest

import frappe
from frappe.utils import now, today
from erp_extensions import api


class ManufacturingHandoffTests(unittest.TestCase):
    def setUp(self):
        os.chdir("/home/frappe/frappe-bench/sites")
        frappe.init(site="native-test.localhost", sites_path=".")
        frappe.connect()
        frappe.set_user("Administrator")
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        self.company = "ERP Native Verification"
        self.stores, self.wip, self.finished = frappe.get_all("Warehouse", filters={
            "company":self.company, "is_group":0, "disabled":0, "warehouse_type":["!=", "Transit"]
        }, pluck="name", order_by="name", limit=3)
        self.material = self.item("Material")

    def item(self, label):
        return api.save({"doctype":"Item", "__islocal":1, "item_code":label + frappe.generate_hash(length=8),
            "item_name":label, "stock_uom":"Nos", "is_stock_item":1,
            "item_group":frappe.db.get_value("Item Group", {"is_group":0}, "name")})["doc"]["name"]

    def submit(self, values):
        saved = api.save(values)["doc"]
        return api.save({"doctype":saved["doctype"], "name":saved["name"], "modified":saved["modified"]}, "Submit")

    def follow(self, source, action, quantity=None, **values):
        origin = api.document(source.doctype, source.name)
        self.assertIn(action, origin["related_actions"])
        draft = api.new_from(source.doctype, source.name, action, str(origin["doc"]["modified"]), quantity=quantity)["doc"]
        return self.submit({"doctype":draft["doctype"], "__islocal":1, "__native_origin":draft["__native_origin"], **values})["doc"]

    def test_work_order_material_movement_and_finished_stock(self):
        product = self.item("Finished")
        self.submit({"doctype":"Stock Entry", "__islocal":1, "company":self.company,
            "stock_entry_type":"Material Receipt", "items":[{"item_code":self.material, "qty":4,
            "t_warehouse":self.stores, "basic_rate":25, "uom":"Nos", "conversion_factor":1}]})
        bom = frappe.get_doc({"doctype":"BOM", "item":product, "company":self.company, "currency":"INR",
            "quantity":1,"rm_cost_as_per":"Valuation Rate","items":[{"item_code":self.material,"qty":2}]}).insert()
        bom.submit()
        self.assertEqual(api.search_link("BOM",bom.name,"Work Order","bom_no",{"company":self.company}), [])
        self.assertIn(bom.name,[row["value"] for row in api.search_link("BOM",bom.name,"Work Order","bom_no",{
            "company":self.company,"production_item":product})])
        self.assertNotIn(bom.name,[row["value"] for row in api.search_link("BOM",bom.name,"Work Order","bom_no",{
            "company":self.company,"production_item":self.material})])
        work = self.submit({"doctype":"Work Order", "__islocal":1, "company":self.company, "production_item":product,
            "bom_no":bom.name, "qty":2, "source_warehouse":self.stores, "wip_warehouse":self.wip,
            "fg_warehouse":self.finished, "planned_start_date":now()})
        order = frappe.get_doc("Work Order", work["doc"]["name"])
        self.assertNotIn("Record finished goods", work["related_actions"])
        with self.assertRaises(frappe.ValidationError):
            api.new_from(order.doctype, order.name, "Transfer materials", str(order.modified), quantity=3)
        partial = self.follow(order, "Transfer materials", 1)
        self.assertEqual(partial["fg_completed_qty"], 1)
        self.follow(order, "Record finished goods", 1)
        transferred = self.follow(order, "Transfer materials")
        self.assertEqual(transferred["work_order"], order.name)
        self.assertEqual(transferred["fg_completed_qty"], 1)
        manufactured = self.follow(order, "Record finished goods")
        self.assertEqual(manufactured["work_order"], order.name)
        order.reload()
        self.assertEqual((order.status, order.produced_qty), ("Completed", 2))
        self.assertNotIn("Record finished goods", api.document(order.doctype, order.name)["related_actions"])
        for item, warehouse, expected in [(self.material, self.stores, 0), (self.material, self.wip, 0), (product, self.finished, 2)]:
            self.assertEqual(frappe.db.get_value("Bin", {"item_code":item, "warehouse":warehouse}, "actual_qty"), expected)

    def test_purchase_request_links_order_and_preserves_remainder(self):
        request = self.submit({"doctype":"Material Request", "__islocal":1, "company":self.company,
            "material_request_type":"Purchase", "schedule_date":today(), "items":[{"item_code":self.material,
                "qty":3,"warehouse":self.stores,"schedule_date":today()}]})
        doc = frappe.get_doc("Material Request", request["doc"]["name"])
        self.assertIn("Purchase Order", request["related_actions"])
        self.assertNotIn("Stock Entry", request["related_actions"])
        order = self.follow(doc, "Purchase Order", supplier=frappe.db.get_value("Supplier", {"disabled":0}, "name"))
        self.assertEqual(order["items"][0]["material_request"], doc.name)
        self.assertEqual(order["items"][0]["qty"], 3)
        self.assertNotIn("Purchase Order", api.document(doc.doctype, doc.name)["related_actions"])

    def test_hierarchy_rename_updates_children_and_deletion_respects_links_and_version(self):
        root = frappe.db.get_value("Item Group", {"is_group":1, "parent_item_group":["is","not set"]}, "name")
        label = "Hierarchy " + frappe.generate_hash(length=8)
        group = frappe.get_doc({"doctype":"Item Group","item_group_name":label,"is_group":1,"parent_item_group":root}).insert()
        child = frappe.get_doc({"doctype":"Item Group","item_group_name":label+" child","parent_item_group":group.name}).insert()
        with self.assertRaises(frappe.TimestampMismatchError):
            api.change_tree_record(group.doctype, group.name, "2000-01-01", "rename", new_name=label+" updated")
        renamed = api.change_tree_record(group.doctype, group.name, str(group.modified), "rename", new_name=label+" updated")["name"]
        child.reload()
        self.assertEqual(child.parent_item_group, renamed)
        frappe.set_user("Guest")
        with self.assertRaises(frappe.PermissionError):
            api.change_tree_record(child.doctype, child.name, str(child.modified), "delete")
        frappe.set_user("Administrator")
        parent = frappe.get_doc(group.doctype, renamed)
        with self.assertRaises(frappe.ValidationError):
            api.change_tree_record(parent.doctype, parent.name, str(parent.modified), "delete")
        api.change_tree_record(child.doctype, child.name, str(child.modified), "delete")
        self.assertFalse(frappe.db.exists(child.doctype, child.name))

    def test_perpetual_inventory_condition_resolves_only_accessible_company_values(self):
        source = {'depends_on':'eval:cint(erpnext.is_perpetual_inventory_enabled(parent.company))'}
        tree = api._field_conditions(source)['depends_on']
        options = tree['args'][0]['object']['value']
        self.assertEqual(options[self.company], frappe.db.get_value('Company',self.company,'enable_perpetual_inventory'))
        frappe.set_user('Guest')
        self.assertNotIn(self.company,api._field_conditions(source)['depends_on']['args'][0]['object']['value'])

    def test_stock_receipt_and_issue_preserve_batch_and_serial_identities(self):
        frappe.db.set_single_value('Stock Settings', 'enable_serial_and_batch_no_for_item', 1)
        item = self.item('Tracked')
        doc = frappe.get_doc('Item',item)
        doc.has_batch_no, doc.has_serial_no = 1, 1
        doc.save()
        batch = frappe.get_doc({'doctype':'Batch','batch_id':'Lot '+frappe.generate_hash(length=7),'item':item}).insert()
        serial = 'Unit-'+frappe.generate_hash(length=7)
        data = {'item_code':item, 'qty':1,'uom':'Nos','conversion_factor':1,'basic_rate':25,
            'use_serial_batch_fields':1, 'serial_no':serial, 'batch_no':batch.name}
        receipt = self.submit({'doctype':'Stock Entry','__islocal':1,'company':self.company,
            'stock_entry_type':'Material Receipt','items':[{**data,'t_warehouse':self.stores}]})['doc']
        out = self.submit({'doctype':'Stock Entry','__islocal':1,'company':self.company,
            'stock_entry_type':'Material Issue','items':[{**data,'s_warehouse':self.stores}]})['doc']
        for entry, qty in [(receipt,1),(out,-1)]:
            bundle = frappe.db.get_value('Stock Ledger Entry',{'voucher_no':entry['name'],'is_cancelled':0},'serial_and_batch_bundle')
            self.assertTrue(bundle)
            line = frappe.get_doc('Serial and Batch Bundle',bundle).entries[0]
            self.assertEqual((line.serial_no,line.batch_no,line.qty),(serial,batch.name,qty))
        self.assertEqual(frappe.db.get_value('Bin',{'warehouse':self.stores,'item_code':item},'actual_qty'),0)

    def test_service_order_supplier_materials_finished_receipt_and_bill(self):
        service, product = self.item('Service'), self.item('Outsourced')
        for name, changes in [(service,{'is_stock_item':0}), (product,{'is_sub_contracted_item':1})]:
            item = frappe.get_doc('Item',name)
            item.update(changes)
            item.save()
        self.submit({'doctype':'Stock Entry','__islocal':1,'company':self.company,'stock_entry_type':'Material Receipt',
            'items':[{'item_code':self.material,'qty':4,'t_warehouse':self.stores,'basic_rate':25,'uom':'Nos','conversion_factor':1}]})
        bom = frappe.get_doc({'doctype':'BOM','item':product,'company':self.company,'currency':'INR','quantity':1,
            'is_default':1,'rm_cost_as_per':'Valuation Rate','items':[{'item_code':self.material,'qty':2}]}).insert()
        bom.submit()
        supplier=frappe.db.get_value('Supplier',{'disabled':0},'name')
        purchase=self.submit({'doctype':'Purchase Order','__islocal':1,'company':self.company,
            'supplier':supplier,'is_subcontracted':1,'supplier_warehouse':self.wip,'set_warehouse':self.finished,'schedule_date':today(),
            'items':[{'item_code':service,'qty':2,'rate':12,'fg_item':product,'fg_item_qty':2,'warehouse':self.finished,'schedule_date':today()}]})
        order=self.follow(frappe.get_doc('Purchase Order',purchase['doc']['name']),'Subcontracting Order',
                          supplier_warehouse=self.wip)
        sco=frappe.get_doc('Subcontracting Order',order['name'])
        self.assertEqual(sco.purchase_order,purchase['doc']['name'])
        origin=api.new_from(sco.doctype,sco.name,'Send materials to supplier',str(sco.modified))['doc']
        moved=self.submit({'doctype':'Stock Entry','__islocal':1,'__native_origin':origin['__native_origin'],
            'items':[{'name':row['name'],'s_warehouse':self.stores,'t_warehouse':self.wip} for row in origin['items']]})
        self.assertEqual(moved['doc']['subcontracting_order'],sco.name)
        receipt=self.follow(sco,'Subcontracting Receipt')
        self.assertEqual(receipt['items'][0]['subcontracting_order'],sco.name)
        self.assertEqual(frappe.db.get_value('Bin',{'item_code':product,'warehouse':self.finished},'actual_qty'),2)
        pr=self.follow(frappe.get_doc('Subcontracting Receipt',receipt['name']),'Purchase Receipt')
        pi=self.follow(frappe.get_doc('Purchase Receipt',pr['name']),'Purchase Invoice')
        self.assertEqual(pi['grand_total'],24)
        debit=self.follow(frappe.get_doc('Purchase Invoice',pi['name']),'Debit Note')
        self.assertEqual((debit['return_against'],debit['grand_total']), (pi['name'],-24))
        self.assertNotIn('Debit Note', api.document('Purchase Invoice',debit['name'])['related_actions'])
