"""Real independent database connections. Synthetic non-valued custody only."""
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import unittest

import frappe
from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.knitting import api


class ConcurrencyTests(fixtures.KnittingTests):
    def test_accepted_estimate_converts_once_with_frozen_rate_across_connections(self):
        self.fixtures(target='10.000')
        programme = [{'id':'P1','fabric':'Single jersey','target_kg':'10.000','fabric_item':self.items['fabric']}]
        estimate = self.call('create_estimate', {'customer':self.customer,'target_kg':'10.000','rate':'100.00',
            'service_item':self.items['service'],'programme':programme})
        quote = frappe.get_doc('Quotation',estimate['data']['quotation'])
        accepted = self.call('accept_estimate',{'quotation':quote.name,'quotation_modified':str(quote.modified)})
        rate = self.call('create_rate', {'customer':self.customer,'fabric':'Single jersey','rate':'120.00'})
        payload = {'quotation':quote.name,'quotation_modified':accepted['data']['modified']}
        owned_events = [estimate['event'],accepted['event'],rate['event']]
        frappe.db.commit()
        try:
            barrier = Barrier(2)
            def worker(request):
                frappe.init(site='native-test.localhost',sites_path='.'); frappe.connect(); frappe.set_user('Administrator')
                try:
                    # Establish a repeatable-read snapshot before either conversion.
                    frappe.db.get_value('Quotation',quote.name,'name')
                    barrier.wait(timeout=20)
                    result = api.command(fixtures.COMPANY,'job_from_estimate',payload,request)
                    frappe.db.commit()
                    return {'ok':result}
                except Exception as error:
                    frappe.db.rollback(); return {'error':type(error).__name__}
                finally: frappe.destroy()
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(worker,['quote-race-a-'+frappe.generate_hash(length=10),'quote-race-b-'+frappe.generate_hash(length=10)]))
            self.assertEqual(sum('ok' in r for r in results),1,results)
            frappe.db.rollback()
            names = frappe.get_all('Knitting Job',filters={'quotation':quote.name},pluck='name')
            self.assertEqual(len(names),1)
            self.assertEqual(frappe.parse_json(frappe.db.get_value('Knitting Job',names[0],'pricing'))['P1'],'100.00')
        finally:
            frappe.db.rollback()
            jobs = [self.job,*frappe.get_all('Knitting Job',filters={'quotation':quote.name},pluck='name')]
            for doctype in ('Knitting QC','Knitting Roll','Knitting Plan','Knitting Ledger Entry','Knitting Event'):
                frappe.db.delete(doctype,{'job':['in',jobs]})
            frappe.db.delete('Knitting Job',{'name':['in',jobs]})
            for child in frappe.get_meta('Quotation').get_table_fields():
                frappe.db.delete(child.options,{'parent':quote.name,'parenttype':'Quotation'})
            frappe.db.delete('Quotation',{'name':quote.name})
            frappe.db.delete('Knitting Event',{'name':['in',owned_events]})
            frappe.db.delete('Knitting Rate',{'customer':self.customer})
            frappe.db.delete('Item Price',{'item_code':['in',list(self.items.values())]})
            for item in self.items.values(): frappe.delete_doc('Item',item)
            frappe.delete_doc('Customer',self.customer)
            frappe.db.commit()

    # Run only these scenarios, not inherited fixture cases a second time.
    def test_last_balance_and_duplicate_request_use_separate_connections(self):
        self.last_balance_race('produce')

    def test_aggregate_last_balance_and_replay_use_separate_connections(self):
        self.last_balance_race('produce_batch')

    def last_balance_race(self, action):
        self.fixtures(target="98.000")
        lot = self.receive("90.000")
        job, company = self.job, fixtures.COMPANY
        modified = str(frappe.db.get_value("Knitting Job", job, "modified"))
        output = (lambda kg: {"quantity_kg": kg, "rolls": "3"}) if action == 'produce_batch' else (lambda kg: {"weights_kg": [kg]})
        payload = {"job": job, "programme_line": "P1", **output('49.000'), "loss_kg": "1.000",
                   "inputs": [{"lot": lot, "quantity_kg": "50.000"}], "warehouse": self.warehouse}
        frappe.db.commit()
        try:
            barrier = Barrier(2)
            def worker(request):
                frappe.init(site="native-test.localhost", sites_path=".")
                frappe.connect()
                frappe.set_user("Administrator")
                try:
                    barrier.wait(timeout=20)
                    result = api.command(company, action, payload, request, modified)
                    frappe.db.commit()
                    return {"ok": result}
                except Exception as error:
                    frappe.db.rollback()
                    return {"error": type(error).__name__, "message": str(error)}
                finally:
                    frappe.destroy()
            request = "race-" + frappe.generate_hash(length=20)
            with ThreadPoolExecutor(max_workers=2) as pool:
                first = list(pool.map(worker, [request, request]))
            self.assertTrue(all("ok" in result for result in first), first)
            self.assertEqual(first[0]["ok"]["event"], first[1]["ok"]["event"])
            frappe.db.rollback()
            balance = api.snapshot(company, job)["jobs"][0]["balances"]
            self.assertEqual(balance["yarn_kg"], "40.000")
            self.assertEqual(balance["produced_kg"], "49.000")
            # Two distinct requests compete for exactly enough stock for one.
            payload = {**payload, **output('39.000'), "inputs": [{"lot": lot, "quantity_kg": "40.000"}]}
            modified = str(frappe.db.get_value("Knitting Job", job, "modified"))
            barrier = Barrier(2)
            with ThreadPoolExecutor(max_workers=2) as pool:
                second = list(pool.map(worker, ["race-a-" + frappe.generate_hash(length=16), "race-b-" + frappe.generate_hash(length=16)]))
            self.assertEqual(sum("ok" in result for result in second), 1, second)
            self.assertEqual(sum("error" in result for result in second), 1, second)
            frappe.db.rollback()
            self.assertEqual(api.snapshot(company, job)["jobs"][0]["balances"]["yarn_kg"], "0.000")
        finally:
            # Remove only this test's committed synthetic custody aggregate, never an ERP voucher.
            frappe.db.rollback()
            for doctype in ("Knitting QC", "Knitting Roll", "Knitting Fabric Batch", "Knitting Plan", "Knitting Ledger Entry", "Knitting Event"):
                frappe.db.delete(doctype, {"job": job})
            frappe.db.delete("Knitting Job", {"name": job})
            frappe.db.delete("Knitting Material Lot", {"name": lot})
            for item in self.items.values():
                frappe.delete_doc("Item", item)
            frappe.delete_doc("Customer", self.customer)
            frappe.db.commit()

# Inherited scenarios are already run by test_knitting; hide them from this class only.
for name in list(vars(fixtures.KnittingTests)):
    if name.startswith("test_"):
        setattr(ConcurrencyTests, name, None)
