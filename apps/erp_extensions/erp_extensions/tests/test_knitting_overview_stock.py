"""Running/all-job yarn scope; synthetic native-test.localhost custody only."""
from unittest.mock import patch

import frappe

from erp_extensions.knitting import domain, permissions, registers
from erp_extensions.tests import test_knitting as fixtures


class OverviewStockTests(fixtures.KnittingTests):
    def shared_lot(self):
        self.fixtures()
        self.first = self.job
        self.lot = self.receive('12.345')
        programme = domain.json_value(frappe.db.get_value('Knitting Job', self.job, 'programme'))
        self.second = self.call('create_job', {'customer': self.customer, 'target_kg': '88.000',
            'material_mode': 'Customer', 'programme': programme, 'rate': '100'})['data']['job']
        self.call('transfer_yarn', {'job': self.first, 'lot': self.lot, 'quantity_kg': '7.125',
            'target_job': self.second, 'target_modified': str(frappe.db.get_value('Knitting Job', self.second, 'modified'))})
        with permissions.service_write():
            completed = frappe.get_doc('Knitting Job', self.second)
            completed.status = 'Completed'
            completed.save()

    def test_shared_lot_allocations_distinguish_running_and_completed_jobs(self):
        self.shared_lot()
        for limit in (1000, 1):
            with self.subTest(batch_size=limit), patch.object(registers, 'BATCH_SIZE', limit):
                balances = self.knitting().overview(fixtures.COMPANY)['balances']
                self.assertEqual(balances['yarn_kg'], '12.345')
                self.assertEqual(balances['running_yarn_kg'], '5.220')

    def test_reopened_job_joins_running_stock_without_changing_all_job_stock(self):
        self.shared_lot()
        before = self.knitting().overview(fixtures.COMPANY)['balances']
        self.call('reopen_job', {'job': self.second, 'reason': 'Synthetic resumed order'})
        after = self.knitting().overview(fixtures.COMPANY)['balances']
        self.assertEqual((before['running_yarn_kg'], after['running_yarn_kg']), ('5.220', '12.345'))
        self.assertEqual((before['yarn_kg'], after['yarn_kg']), ('12.345', '12.345'))

    def test_zero_and_unallocated_or_nonwarehouse_custody_do_not_inflate_running_stock(self):
        self.fixtures()
        self.assertEqual(self.knitting().overview(fixtures.COMPANY)['balances']['running_yarn_kg'], '0.000')
        self.call('receive_yarn', {'item': self.items['yarn'], 'quantity_kg': '9.000',
            'material_owner': 'Customer', 'party': self.customer, 'warehouse': self.warehouse})
        lot = self.receive('2.000')
        with permissions.service_write():
            event = frappe.get_doc('Knitting Event', frappe.db.get_value('Knitting Ledger Entry', {'lot': lot}, 'event'))
            source = frappe.get_doc('Knitting Material Lot', lot)
            domain.ledger(event, source, domain.Decimal('-2.000'), self.job, units='-2')
            domain.ledger(event, source, domain.Decimal('2.000'), self.job, custodian='SC:SYNTHETIC', units='2')
        balances = self.knitting().overview(fixtures.COMPANY)['balances']
        self.assertEqual((balances['yarn_kg'], balances['running_yarn_kg']), ('0.000', '0.000'))

    def test_hidden_completed_job_prevents_partial_running_and_all_totals(self):
        self.shared_lot()
        frappe.set_user('knit-operator@example.invalid')
        balances = self.knitting().overview(fixtures.COMPANY)['balances']
        self.assertEqual((balances['yarn_kg'], balances['running_yarn_kg']), ('12.345', '5.220'))
        frappe.set_user('Administrator')
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid',
            'allow': 'Knitting Job', 'for_value': self.first, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            self.knitting().overview(fixtures.COMPANY)


for name in vars(fixtures.KnittingTests):
    if name.startswith('test_'):
        setattr(OverviewStockTests, name, None)
