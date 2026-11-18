"""Fresh, unposted Invoice register fixtures on native-test.localhost only."""
import argparse
import hashlib
import json
import os
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', help='Exact previously generated synthetic fixture JSON')
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

        def snapshot(companies):
            if not all(name.startswith('Architecture Invoice Register ') for name in companies):
                raise RuntimeError('Refusing unrelated company material')
            rows = frappe.get_all('Sales Invoice', filters={'company': ['in', companies]},
                                  fields=['name', 'company', 'docstatus', 'modified', 'grand_total'], order_by='name')
            if any(row.docstatus != 0 for row in rows):
                raise RuntimeError('All synthetic register invoices must remain drafts')
            if any(frappe.db.count(doctype, {'company': ['in', companies]})
                   for doctype in ('GL Entry', 'Stock Ledger Entry')):
                raise RuntimeError('Register fixtures must never post financial or stock entries')
            return hashlib.sha256(json.dumps(rows, sort_keys=True, default=str).encode()).hexdigest()

        if arguments.verify:
            fixture = json.loads(arguments.verify)
            if fixture['site'] != 'native-test.localhost' or len(fixture['companies']) != 2:
                raise RuntimeError('Refusing unrelated fixture')
            if snapshot(fixture['companies']) != fixture['draftHash']:
                raise RuntimeError('Connected reads changed synthetic drafts')
            print(json.dumps({'site': frappe.local.site, 'draftInvoices': 26,
                              'draftHash': 'unchanged', 'financialAndStockPostings': 0}))
            return

        from erp_extensions import onboarding
        stamp = str(time.time_ns())
        with onboarding._provisioning():
            frappe.db.sql('select name from `tabDocType` where name=%s for update', onboarding.MEMBER)
            companies = []
            for number in (1, 2):
                company = frappe.get_doc({'doctype': 'Company',
                    'company_name': f'Architecture Invoice Register {stamp} {number}',
                    'abbr': 'AIR' + uuid.uuid4().hex[:6].upper(), 'country': 'India',
                    'default_currency': 'INR', 'chart_of_accounts': 'Standard',
                    'create_chart_of_accounts_based_on': 'Standard Template'}).insert()
                companies.append(company.name)
            customer = frappe.get_doc({'doctype': 'Customer', 'customer_name': 'Architecture invoice customer ' + stamp,
                'customer_type': 'Company', 'customer_group': 'Commercial', 'territory': 'India'}).insert()
            item = frappe.get_doc({'doctype': 'Item', 'item_code': 'Architecture invoice service ' + stamp,
                'item_name': 'Synthetic architecture service', 'item_group': 'All Item Groups',
                'stock_uom': 'Nos', 'is_stock_item': 0}).insert()
            invoices = []
            for number in range(26):
                invoice = frappe.get_doc({'doctype': 'Sales Invoice', 'company': companies[0],
                    'customer': customer.name, 'posting_date': '2026-11-16', 'due_date': '2026-11-16',
                    'items': [{'item_code': item.name, 'qty': 1, 'rate': '12.50'}]}).insert()
                invoices.append(invoice.name)
            digest = snapshot(companies)
            frappe.db.commit()
        print(json.dumps({'site': frappe.local.site, 'companies': companies, 'invoices': invoices,
                          'customer': customer.name, 'item': item.name, 'draftHash': digest,
                          'createdSyntheticCompanies': 2, 'createdDraftInvoices': 26,
                          'financialAndStockPostings': 0}))
    except BaseException:
        frappe.db.rollback()
        raise
    finally:
        frappe.destroy()


if __name__ == '__main__':
    main()
