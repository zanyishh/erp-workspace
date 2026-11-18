"""Job register filters and trusted original references; rollback-only native fixtures."""
from datetime import datetime

import frappe

from erp_extensions.tests import test_knitting as fixtures
from erp_extensions.tests.test_migration_contracts import HistoricalContractTests
from erp_extensions.migration import service


class JobFilterTests(fixtures.KnittingTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        from erp_extensions.migration.install import install
        install()
        frappe.db.commit()

    def seed(self, suffix, **values):
        if frappe.local.site != 'native-test.localhost':
            raise RuntimeError('Synthetic job filters require native-test.localhost')
        name = self.prefix + suffix
        frappe.get_doc({'doctype': 'Knitting Job', 'name': name, 'company': fixtures.COMPANY,
            'customer': self.customer, 'status': 'Running', 'material_mode': 'Customer', 'kind': 'Order',
            'job_date': '2026-11-08', 'target_kg': '1.000', 'programme': '[]', 'revision': 1,
            'creation': datetime(2026, 11, 8), 'modified': datetime(2026, 11, 8),
            'owner': 'Administrator', 'modified_by': 'Administrator', **values}).db_insert()
        return name

    def prepare(self):
        self.fixtures()
        self.prefix = 'SYN-JOB-FILTER-' + frappe.generate_hash(length=8) + '-'

    def scope(self):
        others = frappe.get_all('Company', filters={'name': ['!=', fixtures.COMPANY]}, pluck='name', limit=3)
        self.assertEqual(len(others), 3)
        values = HistoricalContractTests().scope()
        values.update(source_instance='job-search-' + frappe.generate_hash(length=10),
            company_bindings={str(i + 1): company for i, company in enumerate([fixtures.COMPANY, *others])},
            allowed_users=['Administrator', 'knit-operator@example.invalid'])
        self.scope_name = service.create_scope(values)

    def original(self, native, label, **changes):
        return service.store_record(self.scope_name, HistoricalContractTests().record(
            namespace='knitpack.job', family='job', native_id=native,
            original_reference='Short-' + native, business_data={'fields': {}, 'original_business': {
                'job_ledger': {'pjobno': label, 'job': {'id': native, 'companymas_id': changes.get('source_company_id', '1')}}}},
            **changes))['name']

    def test_exact_customer_and_actual_job_dates_filter_before_count_and_paging(self):
        self.prepare()
        other = frappe.copy_doc(frappe.get_doc('Customer', self.customer))
        other.customer_name = self.customer + ' similar';other.insert()
        wanted = [self.seed(f'{i:04}', job_date='2026-11-01' if i == 0 else '2026-11-15' if i == 102 else '2026-11-08')
                  for i in range(103)]
        self.seed('other-party', customer=other.name)
        self.seed('undated', job_date=None)
        self.seed('before', job_date='2026-10-31')
        self.seed('after', job_date='2026-11-16')
        self.seed('other-company', company='ERP Native Verification')
        names = []
        for start, length in ((0, 100), (100, 3)):
            try:page = self.knitting().register(fixtures.COMPANY, 'jobs', query=self.prefix, start=start,
                customer=self.customer, from_date='2026-11-01', to_date='2026-11-15')
            except (TypeError, frappe.ValidationError) as error:self.fail('Job customer/date filters are required: ' + str(error))
            self.assertEqual((page['customer'], page['from_date'], page['to_date']), (self.customer, '2026-11-01', '2026-11-15'))
            self.assertEqual(page['page'], {'start': start, 'limit': 100, 'has_more': start == 0, 'total': 103})
            self.assertEqual(len(page['rows']), length)
            names.extend(row.name for row in page['rows'])
        self.assertEqual(set(names), set(wanted));self.assertEqual(len(names), 103)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, 'jobs', query=self.prefix,
            from_date='2026-11-15', to_date='2026-11-15')['page']['total'], 1)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, 'jobs', query=self.prefix,
            from_date='2026-11-16')['page']['total'], 1)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, 'jobs', query=self.prefix,
            to_date='2026-10-31')['page']['total'], 1)

    def test_customer_and_dates_reject_invalid_or_inapplicable_filters(self):
        self.prepare()
        for kwargs in ({'customer': ''}, {'customer': True}, {'customer': ['x']}, {'customer': 'x' * 141},
                       {'from_date': '2026-02-30'}, {'to_date': '2026-1-01'}, {'to_date': ''},
                       {'from_date': True}, {'from_date': '2026-11-16', 'to_date': '2026-11-15'}):
            with self.subTest(kwargs=kwargs), self.assertRaises(frappe.ValidationError):
                self.knitting().register(fixtures.COMPANY, 'jobs', **kwargs)
        with self.assertRaises(frappe.ValidationError):
            self.knitting().register(fixtures.COMPANY, 'machines', from_date='2026-11-15')
        with self.assertRaises(frappe.ValidationError):
            self.knitting().register(fixtures.COMPANY, 'estimates', customer=self.customer)

    def test_customer_read_and_company_permissions_are_required(self):
        self.prepare()
        hidden = frappe.copy_doc(frappe.get_doc('Customer', self.customer));hidden.customer_name += ' hidden';hidden.insert()
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid', 'allow': 'Customer',
            'for_value': self.customer, 'apply_to_all_doctypes': 1}).insert()
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid', 'allow': 'Company',
            'for_value': fixtures.COMPANY, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            self.knitting().register(fixtures.COMPANY, 'jobs', customer=hidden.name)
        with self.assertRaises(frappe.PermissionError):
            self.knitting().register('ERP Native Verification', 'jobs', customer=self.customer)

    def test_full_saved_reference_search_works_before_paging_and_keeps_originals_unchanged(self):
        self.prepare();self.scope()
        source = self.original('123', '456/26')
        wanted = self.seed('old', source_record=source, source_reference='456', job_date='2020-01-01')
        for i in range(102):self.seed(str(i))
        before = frappe.db.get_value(service.RECORD, source, ['record_data', 'data_sha256'], as_dict=True)
        page = self.knitting().register(fixtures.COMPANY, 'jobs', query='456/26')
        self.assertEqual([row.name for row in page['rows']], [wanted])
        self.assertEqual(page['page']['total'], 1)
        self.assertEqual(page['rows'][0]['source_reference_display'], '456/26')
        self.assertEqual(frappe.db.get_value(service.RECORD, source, ['record_data', 'data_sha256'], as_dict=True), before)
        self.assertEqual(self.knitting().register(fixtures.COMPANY, 'jobs', query='456/26', state='Completed')['rows'], [])
        self.assertIn(wanted, [row.name for row in self.knitting().register(fixtures.COMPANY, 'jobs', query='456')['rows']])

    def test_full_reference_search_follows_exact_link_not_same_native_id_in_other_book_or_company(self):
        self.prepare();self.scope()
        linked = self.original('123', 'GOOD/26')
        self.original('123', 'WRONG-BOOK/26', source_book='1')
        foreign = self.original('123', 'FOREIGN/26', source_company_id='2')
        wanted = self.seed('linked', source_record=linked)
        self.seed('foreign-link', source_record=foreign)
        for label in ('WRONG-BOOK/26', 'FOREIGN/26'):
            self.assertEqual(self.knitting().register(fixtures.COMPANY, 'jobs', query=label)['rows'], [])
        self.assertEqual([r.name for r in self.knitting().register(fixtures.COMPANY, 'jobs', query='GOOD/26')['rows']], [wanted])

    def test_full_reference_search_intersects_readable_jobs(self):
        self.prepare();self.scope()
        allowed = self.seed('allowed', source_record=self.original('123', 'ALLOWED/26'))
        hidden = self.seed('hidden', source_record=self.original('124', 'HIDDEN/26'))
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid', 'allow': 'Knitting Job',
            'for_value': allowed, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        self.assertEqual([r.name for r in self.knitting().register(fixtures.COMPANY, 'jobs', query='ALLOWED/26', job=allowed)['rows']], [allowed])
        self.assertEqual(self.knitting().register(fixtures.COMPANY, 'jobs', query='HIDDEN/26')['rows'], [])
        from erp_extensions.knitting.registers import original_reference_matches
        self.assertEqual(original_reference_matches(fixtures.COMPANY, '/26'), [allowed])

    def test_history_customer_choices_include_disabled_readable_parties_with_company_jobs_only(self):
        self.prepare()
        disabled = frappe.copy_doc(frappe.get_doc('Customer', self.customer));disabled.customer_name += ' disabled';disabled.insert()
        unrelated = frappe.copy_doc(frappe.get_doc('Customer', self.customer));unrelated.customer_name += ' unrelated';unrelated.insert()
        self.seed('disabled-party', customer=disabled.name)
        self.seed('foreign-party', customer=unrelated.name, company='ERP Native Verification')
        frappe.db.set_value('Customer', disabled.name, 'disabled', 1)
        try:choices = self.knitting().lookup(fixtures.COMPANY, 'JobCustomer')['rows']
        except frappe.ValidationError as error:self.fail('History needs a company-scoped party selector: ' + str(error))
        self.assertEqual({row.name for row in choices}, {self.customer, disabled.name})
        self.assertNotIn(disabled.name, {r.name for r in self.knitting().lookup(fixtures.COMPANY, 'Customer')['rows']})
        self.assertEqual(self.knitting().register(fixtures.COMPANY, 'jobs', customer=disabled.name)['page']['total'], 1)
        frappe.get_doc({'doctype': 'User Permission', 'user': 'knit-operator@example.invalid', 'allow': 'Customer',
            'for_value': self.customer, 'apply_to_all_doctypes': 1}).insert()
        frappe.set_user('knit-operator@example.invalid')
        self.assertEqual({r.name for r in self.knitting().lookup(fixtures.COMPANY, 'JobCustomer')['rows']}, {self.customer})

    def test_job_picker_full_reference_search_and_closing_state_apply_before_paging(self):
        self.prepare();self.scope()
        running = self.seed('running', source_record=self.original('123', 'PICK-OLD/26'), job_date='2020-01-01')
        complete = self.seed('complete', source_record=self.original('124', 'PICK-DONE/26'), status='Completed')
        for i in range(52):self.seed(str(i))
        self.assertEqual([r.name for r in self.knitting().lookup(fixtures.COMPANY, 'Job', query='PICK-OLD/26')['rows']], [running])
        closing = self.knitting().lookup(fixtures.COMPANY, 'ClosingJob', query='PICK-OLD/26')['rows']
        self.assertEqual([r.name for r in closing], [running])
        self.assertEqual(closing[0].get('source_reference_display'), 'PICK-OLD/26')
        self.assertNotIn('programme', closing[0]);self.assertNotIn('source_record', closing[0])
        self.assertEqual([r.name for r in self.knitting().lookup(fixtures.COMPANY, 'Job', query='PICK-DONE/26')['rows']], [complete])
        self.assertEqual(self.knitting().lookup(fixtures.COMPANY, 'ClosingJob', query='PICK-DONE/26')['rows'], [])

    def test_job_search_treats_percent_and_underscore_as_literal_across_native_and_original_fields(self):
        self.prepare();self.scope()
        for i, value in enumerate(('ORDER_26', 'ORDER%26')):
            exact = self.seed('exact-' + str(i), source_record=self.original(str(123 + i), value))
            self.seed('misleading-' + str(i), source_reference='ORDERX26')
            other = frappe.copy_doc(frappe.get_doc('Customer', self.customer));other.customer_name = 'ORDERX26';other.insert()
            self.seed('party-' + str(i), customer=other.name)
            self.assertEqual([r.name for r in self.knitting().register(fixtures.COMPANY, 'jobs', query=value)['rows']], [exact])
            self.assertEqual([r.name for r in self.knitting().lookup(fixtures.COMPANY, 'Job', query=value)['rows']], [exact])

    def test_corrupt_original_reference_never_becomes_a_search_match(self):
        self.prepare();self.scope()
        source = self.original('123', 'CORRUPT/26')
        self.seed('bad-hash', source_record=source)
        frappe.db.sql('update `tabHistorical Business Record` set data_sha256=%s where name=%s', ('0' * 64, source))
        with self.assertRaises(frappe.ValidationError):
            self.knitting().register(fixtures.COMPANY, 'jobs', query='CORRUPT/26')


for name in vars(fixtures.KnittingTests):
    if name.startswith('test_'):
        setattr(JobFilterTests, name, None)
