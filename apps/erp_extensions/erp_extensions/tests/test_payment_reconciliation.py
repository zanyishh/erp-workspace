"""Payment and invoice balances are verified on real posted, rollback-only documents."""
import os
import secrets
import unittest

import frappe
from frappe.utils import today


class PaymentReconciliationTests(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        self.assertEqual(frappe.local.site, 'native-test.localhost')
        self.company = 'ERP Native Verification'
        frappe.set_user('Administrator')
        self.owner = frappe.db.get_value('Workspace Team Member', {'team_role':'owner'}, ['member_user','company'], as_dict=True)
        if not self.owner:
            from erp_extensions.onboarding import register_owner
            suffix = secrets.token_hex(4)
            frappe.set_user('Guest')
            result = register_owner('Reconciliation owner', f'recon-{suffix}@example.invalid', secrets.token_urlsafe(22), f'Reconciliation {suffix}', 'general')
            self.owner = frappe._dict(member_user=result['email'], company=result['company'])
        self.company = self.owner.company
        frappe.set_user(self.owner.member_user)

    def exercise(self, party_type):
        from erp_extensions import reconciliation as service
        from erpnext.accounts.doctype.payment_entry.payment_entry import get_payment_entry
        suffix = secrets.token_hex(5)
        company = frappe.get_doc('Company', self.company)
        customer = party_type == 'Customer'
        party = frappe.get_doc({'doctype':party_type, party_type.lower()+'_name':'Account party '+suffix,
                    'customer_type':'Company','supplier_type':'Company', 'customer_group':frappe.db.get_value('Customer Group', {'is_group':0}),
                    'supplier_group':frappe.db.get_value('Supplier Group', {'is_group':0}), 'territory':frappe.db.get_value('Territory', {'is_group':0})}).insert()
        item = frappe.get_doc({'doctype':'Item','item_code':'Recon service '+suffix,'item_group':frappe.db.get_value('Item Group',{'is_group':0}),
            'stock_uom':'Nos','is_stock_item':0}).insert()
        invoice = frappe.get_doc({'doctype':'Sales Invoice' if customer else 'Purchase Invoice','company':self.company,
            party_type.lower():party.name,'posting_date':today(),'due_date':today(), 'items':[{'item_code':item.name,'qty':1,'rate':100,
            'income_account':company.default_income_account,'expense_account':company.default_expense_account,'cost_center':company.cost_center}]}).insert().submit()
        payment = get_payment_entry(invoice.doctype, invoice.name, bank_account=company.default_cash_account)
        payment.set('references', []); payment.paid_amount = payment.received_amount = 75
        payment.reference_no, payment.reference_date = suffix, today()
        payment.insert().submit()
        self.assertEqual(payment.unallocated_amount,75)
        args = {'company':self.company, 'party_type':party_type, 'party':party.name}
        first = service.candidates(**args)
        self.assertEqual([r['name'] for r in first['payments']], [payment.name]); self.assertEqual([r['name'] for r in first['invoices']], [invoice.name])
        selection = {'payment':payment.name, 'invoice':invoice.name, 'amount':'25',
                     'expected_payment':first['payments'][0]['balance'], 'expected_invoice':first['invoices'][0]['balance']}
        with self.assertRaises(frappe.ValidationError): service.allocate(**args, **{**selection,'amount':'90'})
        from erp_extensions import operations
        frappe.set_user('Administrator')
        operations.install()
        frappe.set_user(self.owner.member_user)
        request = secrets.token_hex(16)
        operations.begin_operation(self.company, 'reconciliation', request)
        result = service.allocate(**args, **selection, request_id=request)
        self.assertEqual(service.allocate(**args, **selection, request_id=request), result)
        self.assertEqual(operations.operation_status(self.company, request)['result'], result)
        with self.assertRaises(frappe.ValidationError):
            service.allocate(**args, **{**selection, 'amount': '20'}, request_id=request)
        self.assertEqual(float(result['payment_balance']),50); self.assertEqual(float(result['invoice_balance']),75)
        with self.assertRaises(frappe.ValidationError): service.allocate(**args, **selection)
        with self.assertRaises(frappe.PermissionError): service.candidates(**{**args,'company':'ERP Knitting Verification'})
        self.assertEqual(invoice.reload().outstanding_amount,75); self.assertEqual(payment.reload().unallocated_amount,50)
        self.assertEqual(sum(ref.allocated_amount for ref in payment.references if ref.reference_name==invoice.name),25)

    def test_customer_receipt_allocation(self):
        self.exercise('Customer')

    def test_supplier_payment_allocation(self):
        self.exercise('Supplier')

    def test_bank_statement_deposit_clears_only_the_selected_posted_receipt(self):
        from erp_extensions import bank_matching as service
        suffix = secrets.token_hex(5)
        frappe.set_user('Administrator')
        parent = frappe.db.get_value('Account', {'company':self.company, 'is_group':1, 'account_type':'Bank'}, 'name')
        account = frappe.get_doc({'doctype':'Account','account_name':'Statement pilot '+suffix,'company':self.company,'parent_account':parent,'account_type':'Bank'}).insert()
        bank = frappe.get_doc({'doctype':'Bank','bank_name':'Local bank '+suffix}).insert()
        bank_account = frappe.get_doc({'doctype':'Bank Account','account_name':'Operating '+suffix,'bank':bank.name,'company':self.company,'is_company_account':1,'account':account.name}).insert()
        frappe.set_user(self.owner.member_user)
        company = frappe.get_doc('Company', self.company)
        customer = frappe.get_doc({'doctype':'Customer','customer_name':'Statement payer '+suffix,'customer_type':'Company',
            'customer_group':frappe.db.get_value('Customer Group',{'is_group':0}),'territory':frappe.db.get_value('Territory',{'is_group':0})}).insert()
        payment = frappe.get_doc({'doctype':'Payment Entry','company':self.company, 'payment_type':'Receive', 'party_type':'Customer',
            'party':customer.name, 'paid_from':company.default_receivable_account, 'paid_to':account.name,
            'paid_amount':65,'received_amount':65, 'source_exchange_rate':1, 'target_exchange_rate':1})
        payment.reference_no, payment.reference_date = suffix, today()
        payment.insert().submit()
        from erp_extensions import bank_csv
        args = {'company':self.company, 'bank_account':bank_account.name}
        mapping = {'date':'Booking date','deposit':'In','withdrawal':'Out','reference':'Reference','description':'Details','id':'Bank ID'}
        content = f'Booking date,In,Out,Reference,Details,Bank ID\n{today()},65,,{suffix},Deposit one,{suffix}1\n{today()},,70,out-{suffix},Withdrawal,{suffix}2\n'
        batch = dict(**args,content=content,mapping=mapping,date_format='YMD')
        self.assertEqual(bank_csv.statement_csv(**args,content=content,stage='columns')['headers'][0],'Booking date')
        self.assertEqual(bank_csv.statement_csv(**batch,stage='preview')['new_count'],2)
        result = bank_csv.statement_csv(**batch,stage='import')
        self.assertEqual(result['created'],2)
        repeated=bank_csv.statement_csv(**batch,stage='import')
        self.assertEqual((repeated['created'],repeated['duplicates']), (0,2))
        with self.assertRaises(frappe.ValidationError):
            bank_csv.statement_csv(**{**batch,'content':content.replace(',65,,',',66,,')},stage='import')
        with self.assertRaises(frappe.ValidationError):
            bank_csv.statement_csv(**{**batch,'content':content.replace(',,70,',',5,70,')},stage='import')
        self.assertEqual(frappe.db.count('Bank Transaction',{'bank_account':bank_account.name}),2)
        line=frappe.get_doc('Bank Transaction',{'bank_account':bank_account.name,'transaction_id':suffix+'1'})
        self.assertEqual(line.docstatus,1)
        overview = service.entries(**args)
        self.assertIn(str(line.name),[r['name'] for r in overview['statements']])
        rows = service.matches(**args, statement=str(line.name))['payments']
        self.assertEqual([r['name'] for r in rows], [payment.name])
        review = dict(**args, statement=str(line.name),payment=payment.name,expected_statement='65',expected_payment='65')
        with self.assertRaises(frappe.ValidationError): service.match(**{**review,'expected_statement':'64'})
        result = service.match(**review)
        self.assertEqual(float(result['matched']),65); self.assertEqual(float(result['remaining']),0)
        self.assertEqual(str(payment.reload().clearance_date), today()); self.assertEqual(line.reload().status,'Reconciled')
        with self.assertRaises(frappe.ValidationError): service.match(**review)
        self.assertEqual(len(line.reload().payment_entries),1)
        supplier = frappe.get_doc({'doctype':'Supplier','supplier_name':'Statement supplier '+suffix,
            'supplier_group':frappe.db.get_value('Supplier Group',{'is_group':0})}).insert()
        outgoing = frappe.get_doc({'doctype':'Payment Entry','company':self.company, 'payment_type':'Pay', 'party_type':'Supplier',
            'party':supplier.name, 'paid_from':account.name, 'paid_to':company.default_payable_account, 'paid_amount':70,
            'received_amount':70, 'source_exchange_rate':1,'target_exchange_rate':1,'reference_no':'out-'+suffix, 'reference_date':today()}).insert().submit()
        remaining=service.entries(**args)['statements']
        self.assertEqual(len(remaining),1)
        debit=remaining[0].name
        self.assertIn(outgoing.name,[r['name'] for r in service.matches(**args,statement=debit)['payments']])
        result=service.match(**args, statement=debit, payment=outgoing.name,expected_statement='70',expected_payment='70')
        self.assertEqual(float(result['remaining']),0)
        self.assertEqual(str(outgoing.reload().clearance_date),today())
        self.assertEqual(bank_csv.statement_csv(**batch,stage='import')['created'],0)
        self.assertEqual(service.entries(**args)['statements'],[])
        fallback = dict(**args,content=f'Day,Credit,Details\n14/11/2026,3.00,"Fee, reversed"\n',mapping={'date':'Day','deposit':'Credit','description':'Details'},date_format='DMY')
        self.assertEqual(bank_csv.statement_csv(**fallback,stage='import')['created'],1)
        self.assertEqual(bank_csv.statement_csv(**fallback,stage='import')['duplicates'],1)
        ambiguous = fallback['content'] + '14/11/2026,3.00,"Fee, reversed"\n'
        with self.assertRaises(frappe.ValidationError):
            bank_csv.statement_csv(**{**fallback,'content':ambiguous},stage='import')
        with self.assertRaises(frappe.PermissionError):
            bank_csv.statement_csv(**{**fallback,'company':'ERP Knitting Verification'},stage='import')

