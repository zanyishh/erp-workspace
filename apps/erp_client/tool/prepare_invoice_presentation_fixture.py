"""Fresh invoice presentation fixtures on native-test.localhost only."""
import argparse
import hashlib
import json
import os
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify')
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
            raise RuntimeError('Refusing unrelated deployment')
        from erp_extensions.migration import service
        if not all(frappe.db.exists('DocType', name) for name in (service.SCOPE, service.RECORD)):
            raise RuntimeError('Require the existing original source store')

        def snapshot(companies, scope_name):
            if len(companies) != 4 or not all(name.startswith('Architecture Invoice Presentation ') for name in companies):
                raise RuntimeError('Refusing unrelated company material')
            scope = service.get_scope(scope_name)
            if (not scope['source_instance'].startswith('architecture-invoice-presentation-')
                    or list(scope['company_bindings'].values()) != companies):
                raise RuntimeError('Refusing unrelated source material')
            rows = {}
            for doctype in ('Sales Invoice', 'GL Entry', 'Stock Ledger Entry'):
                names = frappe.get_all(doctype, filters={'company': ['in', companies]}, pluck='name', order_by='name')
                rows[doctype] = [frappe.get_doc(doctype, name).as_dict() for name in names]
            rows['originals'] = frappe.get_all(service.RECORD, filters={'source_scope': scope_name},
                fields=['*'], order_by='name')
            for record in rows['originals']:
                service.get_record(record.name)  # Recompute and verify the stored source digest.
            if (len(rows['Sales Invoice']) != 1 or rows['Sales Invoice'][0].docstatus != 1
                    or not rows['GL Entry'] or rows['Stock Ledger Entry'] or len(rows['originals']) != 1):
                raise RuntimeError('Unexpected synthetic presentation fixture shape')
            return {'hashVersion': 2,
                    'financialHash': hashlib.sha256(json.dumps(rows, sort_keys=True, default=str).encode()).hexdigest(),
                    'postedSyntheticInvoices': 1, 'syntheticGlEntries': len(rows['GL Entry']), 'stockPostings': 0,
                    'immutableSourceRecords': 1}

        if arguments.verify:
            fixture = json.loads(arguments.verify)
            if fixture.get('site') != 'native-test.localhost' or fixture.get('hashVersion') != 2:
                raise RuntimeError('Refusing unrelated site')
            current = snapshot(fixture['companies'], fixture['scope'])
            if current['financialHash'] != fixture['financialHash']:
                raise RuntimeError('Presentation changes altered financial or original source data')
            print(json.dumps({'site': frappe.local.site, **current, 'financialAndSourceHashes': 'unchanged'}))
            return

        from erp_extensions import onboarding
        stamp = str(time.time_ns())
        with onboarding._provisioning():
            frappe.db.sql('select name from `tabDocType` where name=%s for update', onboarding.MEMBER)
            companies = []
            for number in range(1, 5):
                company = frappe.get_doc({'doctype': 'Company',
                    'company_name': f'Architecture Invoice Presentation {stamp} {number}',
                    'abbr': 'AIP' + uuid.uuid4().hex[:6].upper(), 'country': 'India',
                    'default_currency': 'INR', 'chart_of_accounts': 'Standard',
                    'create_chart_of_accounts_based_on': 'Standard Template'}).insert()
                companies.append(company.name)
            customer = frappe.get_doc({'doctype': 'Customer', 'customer_name': 'Architecture presentation customer ' + stamp,
                'customer_type': 'Company', 'customer_group': 'Commercial', 'territory': 'India'}).insert()
            item = frappe.get_doc({'doctype': 'Item', 'item_code': 'Architecture presentation service ' + stamp,
                'item_name': 'Synthetic presentation service', 'item_group': 'All Item Groups',
                'stock_uom': 'Nos', 'is_stock_item': 0}).insert()
            invoice = frappe.get_doc({'doctype': 'Sales Invoice', 'company': companies[0],
                'customer': customer.name, 'set_posting_time': 1,
                'posting_date': '2026-11-16', 'due_date': '2026-11-16',
                'disable_rounded_total': 1, 'items': [{'item_code': item.name, 'qty': 1, 'rate': '12.50'}]}).insert()
            invoice.submit()
            evidence = hashlib.sha256(('synthetic invoice presentation ' + stamp).encode()).hexdigest()
            scope_name = service.create_scope({'source_instance': 'architecture-invoice-presentation-' + stamp,
                'company_bindings': {str(i + 1): name for i, name in enumerate(companies)},
                'allowed_users': ['Administrator'], 'opening_effective_date': '2023-04-01',
                'physical_posting_mode': 'closing_initialization',
                'manifest_sha256': evidence, 'policy_evidence_sha256': evidence})
            reference = 'ARCH-SOURCE-' + stamp
            original = service.store_record(scope_name, {'namespace': 'architecture.invoice', 'family': 'invoice',
                'native_id': '1', 'source_company_id': '1', 'source_book': '0', 'shared_cash': False,
                'original_reference': reference, 'original_date_raw': '2026-11-16', 'title': reference,
                'summary': 'Synthetic original invoice presentation only',
                'business_data': {'fields': {'currency': 'INR', 'total': '12.50'}, 'tables': [],
                    'invoice_print': {'seller_name': companies[0], 'customer_name': 'Synthetic original customer',
                        'posting_date': '2026-11-16', 'currency': 'INR', 'precision': 2,
                        'grand_total': '12.50', 'net_total': '12.50', 'taxes': [],
                        'items': [{'item_name': 'Synthetic original service', 'description': 'Source facts retained',
                                   'qty': '1', 'rate': '12.50', 'amount': '12.50', 'uom': 'Nos'}]}},
                'provenance': [{'file': 'architecture-synthetic.json', 'sha256': evidence, 'pointer': '/invoices/1'}]})
            result = snapshot(companies, scope_name)
            frappe.db.commit()
        print(json.dumps({'site': frappe.local.site, 'companies': companies, 'scope': scope_name,
            'invoice': invoice.name, 'original': original['name'], 'originalReference': reference,
            'createdSyntheticCompanies': 4, **result}))
    except BaseException:
        frappe.db.rollback()
        raise
    finally:
        frappe.destroy()


if __name__ == '__main__':
    main()
