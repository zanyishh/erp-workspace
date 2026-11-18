"""Delivery particulars printed from a native invoice's linked dispatches."""
import importlib.util
import sys
import unittest
from datetime import date
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch


class Row(dict):
    __getattr__ = dict.get


class DeliveryNotePrintTests(unittest.TestCase):
    def setUp(self):
        self.frappe = Mock()
        self.frappe.whitelist = lambda **kwargs: lambda function: function
        self.frappe.get_meta.side_effect = lambda name: SimpleNamespace(
            name=name, get_masked_fields=lambda **kwargs: [])
        self.fields = {'Sales Invoice Item': {'delivery_note'}, 'Delivery Note': {
            'posting_date', 'vehicle_no', 'transporter_name', 'lr_no', 'lr_date', 'dispatch_address'}}
        modules = {'frappe': self.frappe, 'bs4': Mock(), 'frappe.model.meta': Mock(),
            'frappe.utils': Mock(), 'frappe.www.printview': Mock(), 'erp_extensions': Mock(),
            'erp_extensions.api': SimpleNamespace(_fieldnames=lambda meta, *args, **kwargs: self.fields[meta.name]),
            'erp_extensions.invoice_settings': Mock(), 'erp_extensions.knitting.permissions': Mock()}
        source = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions/invoices.py'
        with patch.dict(sys.modules, modules):
            spec = importlib.util.spec_from_file_location('native_invoice_print', source)
            self.backend = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.backend)
        self.doc = Row(company='Demo', customer='Buyer', items=[
            Row(delivery_note=ref) for ref in ('DN-2', 'DN-1', 'DN-2', 'DN-3', 'DN-4', None)])
        self.frappe.get_list.return_value = [
            Row(name='DN-1', posting_date=date(2026, 11, 10)),
            Row(name='DN-2', vehicle_no='TRUCK-2', lr_no='GR-2'),
            Row(name='DN-3', vehicle_no='RESTRICTED-3'),
            Row(name='DN-4', vehicle_no='RESTRICTED-4')]
        self.frappe.has_permission.side_effect = lambda dt, perm, doc=None: not (
            (perm == 'read' and doc == 'DN-3') or (perm == 'print' and doc == 'DN-4'))

    def test_distinct_dispatches_keep_line_order_and_checked_document_details(self):
        notes = self.backend._delivery_notes(self.doc)
        self.assertEqual(notes, [
            {'name': 'DN-2', 'vehicle_no': 'TRUCK-2', 'lr_no': 'GR-2'},
            {'name': 'DN-1', 'posting_date': '2026-11-10'}])
        self.frappe.get_list.assert_called_once()
        query = self.frappe.get_list.call_args.kwargs
        self.assertEqual(query['filters'], {'company': 'Demo', 'customer': 'Buyer', 'docstatus': 1,
            'name': ['in', ['DN-2', 'DN-1', 'DN-3', 'DN-4']]})

    def test_hidden_child_reference_and_missing_print_permission_do_not_query(self):
        self.fields['Sales Invoice Item'].clear()
        self.assertEqual(self.backend._delivery_notes(self.doc), [])
        self.fields['Sales Invoice Item'].add('delivery_note')
        self.frappe.has_permission.side_effect = lambda dt, perm, doc=None: perm != 'print'
        self.assertEqual(self.backend._delivery_notes(self.doc), [])
        self.frappe.get_list.assert_not_called()

    def test_masked_dispatch_values_are_not_printed_even_when_a_row_contains_them(self):
        self.frappe.get_meta.side_effect = lambda name: SimpleNamespace(name=name,
            get_masked_fields=lambda **kwargs: [Row(fieldname='lr_no')] if name == 'Delivery Note' else [])
        self.fields['Delivery Note'].discard('vehicle_no')
        notes = self.backend._delivery_notes(self.doc)
        self.assertEqual(notes[0], {'name': 'DN-2'})
        self.assertNotIn('lr_no', self.frappe.get_list.call_args.kwargs['fields'])
        self.assertNotIn('vehicle_no', self.frappe.get_list.call_args.kwargs['fields'])

    def test_dispatch_origin_uses_the_saved_readable_address_for_each_shipment(self):
        self.frappe.get_list.return_value[0]['dispatch_address'] = 'Depot &amp; weighbridge'
        self.frappe.get_list.return_value[1]['dispatch_address'] = 'Gate 002'
        notes = self.backend._delivery_notes(self.doc)
        self.assertEqual([row['dispatch_address'] for row in notes], ['Gate 002', 'Depot & weighbridge'])
        self.fields['Delivery Note'].remove('dispatch_address')
        self.assertTrue(all('dispatch_address' not in row for row in self.backend._delivery_notes(self.doc)))

    def test_register_rounding_matches_the_payable_amount_and_scopes_job_links(self):
        self.backend._company = lambda company: self.assertEqual(company, 'Demo')
        self.backend._precision = lambda *args: 2
        self.backend.cint = lambda value: int(value or 0)
        self.fields['Sales Invoice'] = {'grand_total', 'rounded_total', 'disable_rounded_total', 'knitting_job'}
        self.fields['Knitting Job'] = {'source_reference'}
        self.frappe.get_meta.return_value = None
        self.frappe.get_meta.side_effect = lambda name: SimpleNamespace(
            name=name, get_masked_fields=lambda: [],
            get_field=lambda _: SimpleNamespace(options='Draft\nUnpaid'))
        invoices = [
            Row(name='INV-A', docstatus=1, grand_total=Decimal('8799.55'), rounded_total=8800,
                disable_rounded_total=0, knitting_job='JOB-A'),
            Row(name='INV-B', docstatus=1, grand_total=Decimal('8799.55'), rounded_total=8800,
                disable_rounded_total=1, knitting_job='JOB-HIDDEN'),
        ]
        self.frappe.get_list.side_effect = lambda doctype, **kwargs: (
            invoices if doctype == 'Sales Invoice' else [Row(name='JOB-A', source_reference='WO-487')])
        page = self.backend.register('Demo')
        self.assertEqual([row['payable_total'] for row in page['rows']], ['8800', '8799.55'])
        self.assertEqual(page['rows'][0]['knitting_job'], 'JOB-A')
        self.assertEqual(page['rows'][0]['knitting_job_reference'], 'WO-487')
        self.assertNotIn('knitting_job', page['rows'][1])
        self.assertEqual(self.frappe.get_list.call_args.kwargs['filters'], {
            'company': 'Demo', 'name': ['in', ['JOB-A', 'JOB-HIDDEN']]})

    def test_delivery_invoice_review_hash_includes_rounded_payable(self):
        self.backend._precision = lambda *args: 2
        self.backend.cint = lambda value: int(value or 0)
        self.frappe.utils = Mock()
        permissions = SimpleNamespace(snapshot_link_checks=lambda: lambda fn: fn)
        domain = SimpleNamespace(money=lambda value, precision: f'{Decimal(str(value)):.{precision}f}')
        source = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions/knitting/api.py'
        modules = {'frappe': self.frappe, 'frappe.utils': self.frappe.utils,
            'fixture_knitting': SimpleNamespace(domain=domain, permissions=permissions),
            'erp_extensions.invoices': self.backend}
        with patch.dict(sys.modules, modules):
            spec = importlib.util.spec_from_file_location('fixture_knitting.api', source)
            api = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(api)
            doc = Row(currency='INR', net_total=Decimal('8799.55'), total_taxes_and_charges=0,
                grand_total=Decimal('8799.55'), rounded_total=8800, disable_rounded_total=0,
                customer='Synthetic buyer', customer_name='Synthetic buyer', due_date='2026-11-20',
                flags={}, items=[], taxes=[])
            # Attribute access for child-table fields must mirror Frappe's Document.
            doc.items = []
            rounded = api.invoice_review(doc)
            self.assertEqual((rounded['payable_total'], rounded['rounding_adjustment']), ('8800.00', '0.45'))
            signature = api.invoice_signature(doc)
            doc['disable_rounded_total'] = 1
            self.assertNotEqual(api.invoice_signature(doc), signature)
            self.assertEqual(api.invoice_review(doc)['payable_total'], '8799.55')


if __name__ == '__main__':
    unittest.main()
