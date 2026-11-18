"""Create or verify fresh synthetic history on native-test.localhost only."""
import argparse
import hashlib
import json
import os
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', help='Previously generated synthetic fixture JSON')
    arguments = parser.parse_args()
    if os.environ.get('NATIVE_TEST_SITE') != 'native-test.localhost':
        raise RuntimeError('Require the explicitly selected synthetic site')
    import frappe
    os.chdir('/home/frappe/frappe-bench/sites')
    frappe.init(site='native-test.localhost', sites_path='.')
    frappe.connect()
    frappe.set_user('Administrator')
    try:
        if frappe.local.site != 'native-test.localhost':
            raise RuntimeError('Refusing writes outside the synthetic site')
        from erp_extensions.migration import service
        if not all(frappe.db.exists('DocType', name) for name in (service.SCOPE, service.RECORD)):
            raise RuntimeError('The existing historical store must already be installed')
        if arguments.verify:
            fixture = json.loads(arguments.verify)
            scope = service.get_scope(fixture['scope'])
            if (fixture.get('site') != 'native-test.localhost'
                    or not scope['source_instance'].startswith('architecture-history-')
                    or list(scope['company_bindings'].values()) != fixture['companies']
                    or not all(name.startswith('Architecture History ') for name in fixture['companies'])):
                raise RuntimeError('Refusing unrelated historical fixture material')
            actual = {row.name: row.data_sha256 for row in frappe.get_all(service.RECORD,
                filters={'source_scope': fixture['scope']}, fields=['name', 'data_sha256'])}
            if actual != fixture['hashes']:
                raise RuntimeError('A synthetic historical source changed during verification')
            print(json.dumps({'site': frappe.local.site, 'immutableSourceRecords': len(actual),
                              'sourceHashes': 'unchanged'}))
            return

        stamp = str(time.time_ns())
        companies = []
        # Use entirely fresh companies so no pre-existing migration material is read.
        # The same transaction lock used by owner provisioning protects account trees.
        from erp_extensions import onboarding
        with onboarding._provisioning():
            frappe.db.sql('select name from `tabDocType` where name=%s for update', onboarding.MEMBER)
            for number in range(1, 5):
                company = frappe.get_doc({
                    'doctype': 'Company', 'company_name': f'Architecture History {stamp} {number}',
                    'abbr': 'AH' + uuid.uuid4().hex[:6].upper(), 'country': 'India',
                    'default_currency': 'INR', 'chart_of_accounts': 'Standard',
                    'create_chart_of_accounts_based_on': 'Standard Template',
                }).insert()
                companies.append(company.name)
            evidence = hashlib.sha256(('synthetic architecture history ' + stamp).encode()).hexdigest()
            scope_name = service.create_scope({
                'source_instance': 'architecture-history-' + stamp,
                'company_bindings': {str(i + 1): name for i, name in enumerate(companies)},
                'allowed_users': ['Administrator'], 'opening_effective_date': '2023-04-01',
                'physical_posting_mode': 'closing_initialization',
                'manifest_sha256': evidence, 'policy_evidence_sha256': evidence,
            })

            def store(namespace, family, native, title, body, *, shared=False,
                      source_company='1', original='2026-11-15', book='0'):
                values = {
                    'namespace': namespace, 'family': family, 'native_id': native,
                    'source_company_id': None if shared else source_company,
                    'source_book': book, 'shared_cash': shared,
                    'original_reference': title, 'original_date_raw': original,
                    'title': title, 'summary': 'Synthetic architecture verification only',
                    'business_data': body,
                    'provenance': [{'file': 'architecture-synthetic.json', 'sha256': evidence,
                                    'pointer': '/' + family + '/' + native}],
                }
                return service.store_record(scope_name, values)['name']

            jobs = []
            for number in range(1, 42):
                native = f'{number:03}'
                reference = f'ARCH-{stamp}-{native}'
                name = store('knitpack.job', 'job', native, reference, {
                    'fields': {'party': 'Synthetic original customer', 'quantity': '-0.1250'},
                    'tables': [], 'original_business': {'job_ledger': {
                        'job': {'id': native, 'companymas_id': '1', 'sec_acc': '0'},
                        'pjobno': reference,
                    }},
                })
                jobs.append({'name': name, 'native': native, 'reference': reference})
            production = []
            for number, job, quantity, count, machine in (
                (1, '001', '-0.1250', '0.5', 'Machine A'),
                (2, '001', '1.2500', None, 'Machine A'),
                (3, '002', None, '-0.25', 'Machine B'),
            ):
                production.append(store('knitpack.production', 'production', str(number),
                    f'Architecture production {stamp} {number}', {
                        'fields': {'job': 'Saved raw job value', 'net_kg': quantity,
                                   'rolls': count, 'machine': machine, 'operator': "O'Brien_%",
                                   'shift': 'Night', 'party': 'Synthetic original customer'},
                        'tables': [], 'original_business': {'header': {
                            'id': str(number), 'companymas_id': '1', 'jobmas_id': job,
                        }},
                    }))
            cash = store('accv2.cash', 'cash_opening', '1', 'Synthetic shared opening',
                         {'fields': {'amount': '12.50'}}, shared=True, original='0000-00-00')
            hashes = {row.name: row.data_sha256 for row in frappe.get_all(service.RECORD,
                filters={'source_scope': scope_name}, fields=['name', 'data_sha256'])}
            frappe.db.commit()
        print(json.dumps({'site': frappe.local.site, 'scope': scope_name, 'companies': companies,
                          'jobs': jobs, 'production': production, 'cash': cash, 'hashes': hashes,
                          'createdSyntheticCompanies': 4, 'createdHistoricalRecords': len(hashes),
                          'financialPostings': 0}))
    except BaseException:
        frappe.db.rollback()
        raise
    finally:
        frappe.destroy()


if __name__ == '__main__':
    main()
