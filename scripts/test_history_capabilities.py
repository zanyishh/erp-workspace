"""Read-capability contract without a site or customer records."""
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


class HistoryCapabilityTests(unittest.TestCase):
    def test_production_report_route_is_exact_and_still_denied_to_cashiers(self):
        path = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions/team_scope.py'
        spec = importlib.util.spec_from_file_location('synthetic_team_scope', path)
        module = importlib.util.module_from_spec(spec)
        member = SimpleNamespace(team_role='owner')
        def deny(message, error=PermissionError):
            raise error(message)
        framework = SimpleNamespace(request=SimpleNamespace(path=''), form_dict={},
                                    throw=deny, PermissionError=PermissionError)
        modules = {'frappe': framework,
                   'erp_extensions.onboarding': SimpleNamespace(MEMBER='Synthetic Member', membership=lambda: member),
                   'erp_extensions.knitting.install': SimpleNamespace(SCHEMAS={})}
        with patch.dict(sys.modules, modules):
            spec.loader.exec_module(module)
            framework.request.path='/api/method/erp_extensions.migration.production_reports.summary'
            try:
                module.guard_request()
            except PermissionError:
                self.fail('The original-production report is not reachable by the managed owner.')
            member.team_role='cashier'
            with self.assertRaises(PermissionError): module.guard_request()
            member.team_role='owner'
            for command in ('erp_extensions.migration.production_reports.raw',
                            'erp_extensions.migration.production_reports.summary_extra'):
                framework.request.path='/api/method/'+command
                with self.assertRaises(PermissionError): module.guard_request()

    def test_cashier_capability_matches_managed_route_denial(self):
        path = Path(__file__).resolve().parents[1] / 'apps/erp_extensions/erp_extensions/migration/api.py'
        spec = importlib.util.spec_from_file_location('synthetic_history.api', path)
        api = importlib.util.module_from_spec(spec)
        framework = SimpleNamespace(whitelist=lambda: lambda fn: fn,
            get_all=Mock(return_value=['visible-record']))
        team = SimpleNamespace(membership=Mock(return_value=SimpleNamespace(team_role='cashier')))
        modules = {'frappe':framework, 'synthetic_history':SimpleNamespace(contracts=SimpleNamespace(), service=SimpleNamespace()),
            'synthetic_history.install':SimpleNamespace(SCOPE='Scope', RECORD='Record', AUTHORITY='Authority'),
            'erp_extensions.knitting.permissions':SimpleNamespace(company_allowed=lambda company: True),
            'erp_extensions.team_scope':team}
        with patch.dict(sys.modules, modules):
            spec.loader.exec_module(api)
            with patch.object(api, '_scope', return_value={'name':'scope'}) as scope, \
                    patch.object(api, '_filters', return_value=({}, {})):
                self.assertFalse(api.available('Synthetic company'))
                scope.assert_not_called()
                framework.get_all.assert_not_called()
                for member in (None, SimpleNamespace(team_role='accountant')):
                    team.membership.return_value=member
                    self.assertTrue(api.available('Synthetic company'))


if __name__ == '__main__':
    unittest.main()
