"""Fresh draft-only financial composer fixtures on native-test.localhost."""
import argparse
import hashlib
import json
import os
import time
import uuid
from decimal import Decimal


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
        if arguments.verify:
            fixture = json.loads(arguments.verify)
            companies = fixture['companies']
            if (fixture['site'] != frappe.local.site or len(companies) != 2
                    or not all(c.startswith('Architecture Invoice Composer ') for c in companies)):
                raise RuntimeError('Refusing unrelated company material')
            names = frappe.get_all('Sales Invoice', filters={'company': ['in', companies]}, pluck='name', order_by='name')
            if len(names) != 1:
                raise RuntimeError('Exact retry must create just one draft invoice')
            doc = frappe.get_doc('Sales Invoice', names[0])
            if (doc.company != companies[0] or doc.docstatus != 0 or doc.customer != fixture['customer']
                    or Decimal(str(doc.grand_total)) != Decimal('25') or len(doc.items) != 1
                    or doc.items[0].item_code != fixture['item'] or doc.items[0].qty != 2 or doc.items[0].rate != 12.5):
                raise RuntimeError('The saved draft differs from the reviewed synthetic input')
            if any(frappe.db.count(doctype, {'company': ['in', companies]}) for doctype in ('GL Entry', 'Stock Ledger Entry')):
                raise RuntimeError('Composer draft rehearsal must not post financial or stock entries')
            from erp_extensions import invoices
            if frappe.db.get_value(invoices.STYLE, doc.name, 'template_id') != 'grove':
                raise RuntimeError('The selected draft template was not retained')
            digest = hashlib.sha256(json.dumps(doc.as_dict(), sort_keys=True, default=str).encode()).hexdigest()
            if fixture.get('draftHash') and fixture['draftHash'] != digest:
                raise RuntimeError('A repeat changed the complete saved draft or its child rows')
            print(json.dumps({'site': frappe.local.site, 'draftInvoices': 1, 'draft': doc.name, 'draftHash': digest,
                              'financialAndStockPostings': 0, 'reviewedInputAndTemplate': 'matched'}))
            return
        from erp_extensions import onboarding
        stamp = str(time.time_ns())
        with onboarding._provisioning():
            frappe.db.sql('select name from `tabDocType` where name=%s for update', onboarding.MEMBER)
            companies = []
            for number in (1, 2):
                company = frappe.get_doc({'doctype': 'Company',
                    'company_name': f'Architecture Invoice Composer {stamp} {number}',
                    'abbr': 'AIC' + uuid.uuid4().hex[:6].upper(), 'country': 'India',
                    'default_currency': 'INR', 'chart_of_accounts': 'Standard',
                    'create_chart_of_accounts_based_on': 'Standard Template'}).insert()
                companies.append(company.name)
            customer = frappe.get_doc({'doctype': 'Customer', 'customer_name': 'Architecture composer customer ' + stamp,
                'customer_type': 'Company', 'customer_group': 'Commercial', 'territory': 'India'}).insert()
            item = frappe.get_doc({'doctype': 'Item', 'item_code': 'Architecture composer service ' + stamp,
                'item_name': 'Synthetic composer service', 'item_group': 'All Item Groups',
                'stock_uom': 'Nos', 'is_stock_item': 0}).insert()
            posting = frappe.utils.today()
            frappe.db.commit()
        print(json.dumps({'site': frappe.local.site, 'companies': companies, 'customer': customer.name,
                          'item': item.name, 'postingDate': posting, 'requestId': 'architecture-invoice-' + stamp,
                          'createdSyntheticCompanies': 2, 'financialAndStockPostings': 0}))
    except BaseException:
        frappe.db.rollback()
        raise
    finally:
        frappe.destroy()


if __name__ == '__main__':
    main()
