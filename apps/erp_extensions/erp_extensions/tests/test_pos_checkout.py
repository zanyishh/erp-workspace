"""Cash register with real items, payments, shift records and stock ledger."""
import os
import secrets
import unittest

import frappe


class CheckoutTests(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        frappe.set_user('Administrator')

    def test_sales_invoice_checkout(self):
        self.exercise("Sales Invoice", managed=True)

    def test_consolidated_pos_invoice_checkout(self):
        self.exercise("POS Invoice")

    def exercise(self, invoice_type, managed=False):
        from erp_extensions import pos_checkout as pos
        from erpnext.stock.doctype.stock_entry.stock_entry_utils import make_stock_entry
        from erpnext.stock.utils import get_stock_balance
        pos.install()
        frappe.db.set_single_value('POS Settings','invoice_type',invoice_type)
        frappe.set_user('Guest')
        with self.assertRaises(frappe.PermissionError):
            pos.register('ERP Native Verification')
        frappe.set_user('Administrator')
        tag=secrets.token_hex(5)
        company=frappe.get_doc('Company','ERP Native Verification')
        if managed:
            from erp_extensions.onboarding import register_owner
            frappe.set_user('Guest')
            owner=register_owner('Register owner',f'pos-owner-{tag}@example.invalid',secrets.token_urlsafe(25),f'Register company {tag}','general')
            frappe.set_user('Administrator')
            company=frappe.get_doc('Company',owner['company'])
        if managed:
            from erp_extensions.onboarding import invite_member, accept_invite
            frappe.set_user(owner['email'])
            self.assertTrue(pos.register(company.name)['can_configure'])
            profile_name=pos.configure(company.name)['profile']
            invite=invite_member(company.name,f'cashier-{tag}@example.invalid','cashier')
            frappe.set_user('Guest')
            joined=accept_invite(invite['token'],'Cashier',invite['email'],secrets.token_urlsafe(25))
            user=frappe.get_doc('User',joined['email'])
            self.assertEqual([r.role for r in user.roles],['Workspace POS Cashier'])
            frappe.set_user(owner['email'])
        else:
            user=frappe.get_doc({'doctype':'User','first_name':'Test cashier','email':f'cashier-{tag}@example.invalid',
                'send_welcome_email':0,'roles':[{'role':r} for r in ('Sales Manager','Accounts User','Sales User','Stock User')]}).insert()
        customer=frappe.get_doc({'doctype':'Customer','customer_name':'POS shopper '+tag,'customer_group':'Commercial','territory':'India','customer_type':'Company'}).insert()
        item=frappe.get_doc({'doctype':'Item','item_code':'POS-STOCK-'+tag,'is_stock_item':1,'item_group':frappe.db.get_value('Item Group',{'is_group':0}),'stock_uom':'Nos'}).insert()
        price=frappe.db.get_value('Price List',{'selling':1,'enabled':1,'currency':company.default_currency})
        frappe.get_doc({'doctype':'Item Price','item_code':item.name,'price_list':price,'price_list_rate':45}).insert()
        warehouse=frappe.db.get_value('POS Profile',profile_name,'warehouse') if managed else frappe.db.get_value('Warehouse',{'company':company.name,'is_group':0,'disabled':0})
        frappe.set_user('Administrator')
        make_stock_entry(company=company.name,item_code=item.name,qty=3,to_warehouse=warehouse,rate=20)
        mode=frappe.get_doc('Mode of Payment','Cash')
        if not any(r.company==company.name for r in mode.accounts):
            mode.append('accounts', {'company':company.name,'default_account':company.default_cash_account}); mode.save()
        if managed:
            profile=frappe.get_doc('POS Profile',profile_name)
        else:
            profile=frappe.get_doc({'doctype':'POS Profile','__newname':'Native till '+tag,'name':'Native till '+tag,'company':company.name,
                'warehouse':warehouse,'currency':company.default_currency,'selling_price_list':price,'customer':customer.name,
                'cost_center':company.cost_center,'write_off_cost_center':company.cost_center,'write_off_account':company.write_off_account,
                'income_account':company.default_income_account,'expense_account':company.default_expense_account,
                'applicable_for_users':[{'user':user.name}],'payments':[{'mode_of_payment':'Cash','default':1}]}).insert()
        frappe.set_user('Administrator')
        # Even a role-authorized cashier cannot use a till limited to another user.
        with self.assertRaises(frappe.PermissionError):
            pos.open_shift(company.name, profile.name, '0')
        frappe.set_user(user.name)
        if managed:
            from erp_extensions.workspace import context
            workspace=context()
            self.assertEqual(workspace['company'],company.name)
            self.assertTrue(workspace['can_operate_pos'])
            self.assertTrue(workspace['cashier_home'])
            with self.assertRaises(frappe.PermissionError):
                pos.configure(company.name)
            for role in ('Sales Manager','Accounts Manager','System Manager'):
                self.assertNotIn(role, frappe.get_roles())
        args={'company':company.name,'profile':profile.name}
        self.assertIn(profile.name,pos.register(company.name)['profiles'])
        opening=pos.open_shift(**args,amount='100')['opening']
        cart=[{'item':item.name,'qty':2}]
        sale={'company':company.name,'opening':opening,'customer':customer.name,'items':cart}
        quote=pos.quote(**sale)
        self.assertEqual(float(quote['amount']),90)
        failed={**sale,'items':[{'item':item.name,'qty':9}]}
        frappe.db.savepoint('insufficient_stock')
        with self.assertRaises(frappe.ValidationError):
            pos.checkout(**failed, expected='405', token='d'*32)
        frappe.db.rollback(save_point='insufficient_stock')
        sale.update(expected=quote['amount'],token=tag*4)
        result=pos.checkout(**sale)
        self.assertEqual(pos.checkout(**sale),result)
        with self.assertRaises(frappe.ValidationError):
            pos.checkout(**{**sale,'items':[{'item':item.name,'qty':1}]})
        receipt=frappe.get_doc(result['doctype'], result['invoice'])
        self.assertEqual(receipt.doctype,invoice_type)
        self.assertEqual((receipt.docstatus,receipt.customer,receipt.paid_amount),(1,customer.name,90))
        self.assertEqual(receipt.payments[0].mode_of_payment,'Cash')
        details=pos.closing(company.name,opening)
        self.assertEqual(float(details['payments'][0]['expected']),190)
        closed=pos.close_shift(company.name,opening,{'Cash':190},details['revision'])
        self.assertEqual(frappe.db.get_value('POS Opening Entry',opening,'status'),'Closed')
        self.assertEqual(frappe.db.get_value('POS Closing Entry',closed['closing'],'docstatus'),1)
        self.assertEqual(get_stock_balance(item.name,warehouse),1)
        # Return against the original receipt during a new shift, after sale consolidation.
        second=pos.open_shift(**args,amount='100')['opening']
        returns={'company':company.name,'opening':second,'invoice':receipt.name}
        review=pos.refund_review(**returns)
        self.assertEqual((float(review['amount']),review['customer']),(90,customer.name))
        with self.assertRaises(frappe.PermissionError):
            pos.refund_review(**{**returns,'company':'Invalid company'})
        with self.assertRaises(frappe.ValidationError):
            pos.refund(**returns,expected='91',token='x'*32)
        returned=pos.refund(**returns,expected=review['amount'],token='y'*32)
        self.assertEqual(pos.refund(**returns,expected=review['amount'],token='y'*32),returned)
        with self.assertRaises(frappe.ValidationError):
            pos.refund(**returns,expected=review['amount'],token='z'*32)
        credit=frappe.get_doc(invoice_type,returned['invoice'])
        self.assertEqual((credit.docstatus,credit.is_return,credit.return_against),(1,1,receipt.name))
        self.assertEqual((credit.paid_amount,credit.payments[0].amount),(-90,-90))
        counts=pos.closing(company.name,second)
        self.assertEqual(float(counts['payments'][0]['expected']),10)
        pos.close_shift(company.name,second,{'Cash':10},counts['revision'])
        self.assertEqual(get_stock_balance(item.name,warehouse),3)
        frappe.set_user('native-reader@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            pos.register(company.name)
