"""Synthetic permission checks for source delivery rates and native batches."""
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from erp_extensions.knitting import api, permissions


class MigrationEventVisibilityTests(unittest.TestCase):
    def test_billing_party_is_only_projected_to_financial_roles(self):
        value = {'customer':'Material customer', 'billing_customer':'Billing customer'}
        self.assertEqual(api.project(value, financial_read=False), {'customer':'Material customer'})
        self.assertEqual(api.project(value, financial_read=True), value)

    def test_operational_projection_removes_original_and_current_rates(self):
        value = {'quantity_kg': '10.000', 'sources': [
            {'legacy_line': '7', 'rate': '125.00', 'original_dc_rate': '0', 'quantity_kg': '10.000'}]}
        self.assertEqual(api.project(value, financial_read=False), {'quantity_kg': '10.000',
            'sources': [{'legacy_line': '7', 'quantity_kg': '10.000'}]})
        self.assertEqual(api.project(value, financial_read=True), value)

    def test_generic_delivery_event_read_requires_financial_permission(self):
        with patch.object(permissions, 'company_allowed', return_value=True), \
                patch.object(permissions, 'profile', return_value=True), \
                patch.object(permissions, 'source_scope', return_value=True):
            for kind in ('deliver_batch', 'migration_delivery_reference'):
                doc = SimpleNamespace(doctype='Knitting Event', company='Synthetic company', kind=kind)
                with patch.object(permissions, 'capabilities', return_value={'jobs', 'production'}):
                    self.assertFalse(permissions.has_permission(doc, 'read'))
                with patch.object(permissions, 'capabilities', return_value={'jobs', 'financial_read'}):
                    self.assertTrue(permissions.has_permission(doc, 'read'))
