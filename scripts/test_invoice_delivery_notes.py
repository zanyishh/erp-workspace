"""Delivery particulars printed from a native invoice's linked dispatches."""
import importlib.util
import sys
import unittest
from datetime import date
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
            'posting_date', 'vehicle_no', 'transporter_name', 'lr_no', 'lr_date'}}
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


if __name__ == '__main__':
    unittest.main()
