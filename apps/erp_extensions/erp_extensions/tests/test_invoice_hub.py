"""Native invoice register and printable data against posted ERPNext records."""
import os
import secrets
import unittest

import frappe
from types import SimpleNamespace
from unittest.mock import patch

from frappe.utils import today


class InvoiceHubTests(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost',sites_path='.')
        frappe.connect()
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        from erp_extensions.onboarding import register_owner
        self.suffix = secrets.token_hex(4)
        self.company = 'Invoice hub '+self.suffix
        self.owner = 'invoicing-'+self.suffix+'@example.invalid'
        frappe.set_user('Guest')
        register_owner('Invoice Owner',self.owner,secrets.token_urlsafe(18),self.company,'general')
        frappe.set_user(self.owner)
        self.customer=frappe.get_doc({'doctype':'Customer','customer_type':'Company','customer_name':'Textile buyer '+self.suffix,
            'customer_group':frappe.db.get_value('Customer Group',{'is_group':0}),'territory':frappe.db.get_value('Territory',{'is_group':0})}).insert()
        self.item=frappe.get_doc({'doctype':'Item','item_code':'Invoice service '+self.suffix,'stock_uom':'Nos','is_stock_item':0,
                                 'item_group':frappe.db.get_value('Item Group',{'is_group':0})}).insert()

    def invoice(self, taxes=(), discount=0):
        company=frappe.get_doc('Company',self.company)
        return frappe.get_doc({'doctype':'Sales Invoice','company':self.company,'customer':self.customer.name,'posting_date':today(),
            'po_no':'PO-123','due_date':today(),'apply_discount_on':'Grand Total','discount_amount':discount,
            'items':[{'item_code':self.item.name,'qty':q,'rate':100,'description':'Fabric <b>service</b><br>blue',
                      'income_account':company.default_income_account,'cost_center':company.cost_center} for q in (1,2)],
            'taxes':[{'charge_type':'On Net Total','account_head':head,'description':label,'rate':rate,'cost_center':company.cost_center} for head,label,rate in taxes]}).insert().submit()

    def test_posted_invoice_register_print_and_style(self):
        from erp_extensions import invoices
        invoice=self.invoice()
        before=str(invoice.modified)
        reg=invoices.register(self.company,query=self.customer.name,status='All',limit=1)
        self.assertTrue(reg['can_create'])
        self.assertEqual([r['name'] for r in reg['rows']],[invoice.name])
        self.assertTrue(reg['rows'][0]['can_print'])
        self.assertFalse(reg['has_more'])
        self.assertEqual(invoices.register(self.company,status='Paid')['rows'],[])
        data=invoices.print_data(self.company,invoice.name)
        self.assertEqual(data['template_id'],'ledger')
        self.assertEqual(data['po_no'],'PO-123')
        self.assertEqual(data['modified'], str(invoice.modified))
        self.assertEqual(float(data['grand_total']),300)
        self.assertEqual(len(data['items']),2)
        self.assertEqual(data['items'][0]['description'],'Fabric service\nblue')
        self.assertFalse(data['company_gstin'])
        self.assertFalse(data['irn'])
        with self.assertRaises(frappe.ValidationError): invoices.set_template(self.company,invoice.name,'unknown')
        invoices.set_template(self.company,invoice.name,'canopy')
        self.assertEqual(invoices.print_data(self.company,invoice.name)['template_id'],'canopy')
        self.assertEqual(str(invoice.reload().modified),before)
        self.assertEqual(invoice.docstatus,1)
        self.assertEqual(frappe.db.count(invoices.STYLE,{'invoice':invoice.name}),1)
        for fn in (lambda:invoices.print_data('ERP Native Verification',invoice.name),lambda:invoices.register('ERP Native Verification'),lambda:invoices.set_template('ERP Native Verification',invoice.name,'ledger')):
            with self.assertRaises(frappe.PermissionError): fn()

    def test_recent_customer_comes_from_selected_company_and_stays_selectable(self):
        from erp_extensions.api import search_link
        self.invoice()
        def choices(company, query=''):
            return search_link('Customer', query, parent='Sales Invoice', field='customer',
                               context={'company': company})
        recent = choices(self.company)
        self.assertEqual(recent[0]['value'], self.customer.name)
        self.assertIn('Recently invoiced', recent[0]['description'])
        self.assertEqual(sum(row['value'] == self.customer.name for row in recent), 1)
        self.assertFalse(any('Recently invoiced' in (row.get('description') or '')
                             for row in choices(self.company, self.customer.name)))
        self.assertFalse(any('Recently invoiced' in (row.get('description') or '')
                             for row in choices('Out of scope')))
        frappe.db.set_value('Customer', self.customer.name, 'disabled', 1)
        self.assertNotIn(self.customer.name, [row['value'] for row in choices(self.company)])

    def test_register_reports_invoice_payable_after_rounding(self):
        from decimal import Decimal
        from erp_extensions import invoices
        posted = self.invoice()
        for disable, expected in ((0, '300.00'), (1, '300.23')):
            # Isolate display of persisted amount fields from company-specific rounding settings.
            frappe.db.set_value('Sales Invoice', posted.name, {
                'grand_total': 300.23, 'rounded_total': 300, 'disable_rounded_total': disable})
            row = invoices.register(self.company, query=posted.name)['rows'][0]
            self.assertEqual(Decimal(row['grand_total']), Decimal('300.23'))
            self.assertEqual(Decimal(row['payable_total']), Decimal(expected))

    def test_recorded_split_tax_discount_and_repeated_item_codes(self):
        from erp_extensions import invoices
        frappe.set_user('Administrator')
        parent = frappe.db.get_value('Account',{'company':self.company,'is_group':1,'root_type':'Liability'},'name')
        taxes = []
        for label in ('CGST','SGST','IGST'):
            account=frappe.get_doc({'doctype':'Account','account_name':label,'parent_account':parent,'account_type':'Tax','company':self.company}).insert()
            taxes.append((account.name,label,18 if label=='IGST' else 9))
        frappe.set_user(self.owner)
        invoice=self.invoice(taxes[:2],discount=12)
        data=invoices.print_data(self.company,invoice.name)
        self.assertEqual([t['label'] for t in data['taxes']],['CGST','SGST'])
        self.assertEqual(float(data['discount_amount']),12)
        self.assertAlmostEqual(sum(float(t['amount']) for t in data['taxes']),invoice.total_taxes_and_charges,places=2)
        self.assertEqual([len(r['taxes']) for r in data['items']],[2,2])
        self.assertNotEqual(data['items'][0]['taxes'][0]['amount'],data['items'][1]['taxes'][0]['amount'])
        self.assertEqual(float(data['grand_total']),invoice.grand_total)
        interstate=self.invoice(taxes[2:])
        summary=invoices.print_data(self.company,interstate.name)
        self.assertEqual([t['label'] for t in summary['taxes']],['IGST'])
        first=invoices.register(self.company,limit=1)
        second=invoices.register(self.company,start=1,limit=1)
        self.assertTrue(first['has_more'])
        self.assertFalse(second['has_more'])
        self.assertNotEqual(first['rows'][0]['name'],second['rows'][0]['name'])

    def test_reader_without_print_or_write_and_draft_site_policy(self):
        from erp_extensions import invoices
        from unittest.mock import patch
        invoice=self.invoice()
        draft=frappe.copy_doc(invoice)
        draft.insert()
        settings_response = invoices.get_settings(self.company)
        private = dict(settings_response['settings'], template_id='pearl', account_number='00123', upi_id='example@demobank')
        invoices.save_settings(self.company, private, settings_response['revision'])
        # A site administrator may independently disable printing of drafts.
        settings=frappe.get_cached_doc('Print Settings')
        with patch.object(settings,'allow_print_for_draft',0):
            entry=next(r for r in invoices.register(self.company)['rows'] if r['name']==draft.name)
            self.assertFalse(entry['can_print'])
            from erp_extensions.api import _result
            self.assertFalse(_result(draft)['permissions']['print'])
            with self.assertRaises(frappe.PermissionError):
                invoices.print_data(self.company,draft.name)
        frappe.set_user('Administrator')
        from frappe.permissions import add_permission
        role='Invoice reader '+self.suffix
        frappe.get_doc({'doctype':'Role','role_name':role}).insert()
        for doctype in ('Company', 'Sales Invoice'):
            add_permission(doctype,role,ptype='read')
        viewer=frappe.get_doc({'doctype':'User','email':'reader-'+self.suffix+'@example.invalid','first_name':'Viewer','send_welcome_email':0,
                              'roles':[{'role':role}]}).insert()
        frappe.get_doc({'doctype':'User Permission','user':viewer.name,'allow':'Company','for_value':self.company,'apply_to_all_doctypes':1}).insert()
        frappe.set_user(viewer.name)
        # These temporary grants are uncommitted; load this transaction's metadata.
        for doctype in ('Company', 'Sales Invoice'):
            frappe.get_meta(doctype, cached=False)
        self.assertTrue(frappe.has_permission('Company', 'read'))
        self.assertFalse(frappe.has_permission('Sales Invoice', 'write'))
        self.assertFalse(frappe.has_permission('Sales Invoice', 'print'))
        self.assertTrue(invoices.register(self.company)['rows'])
        self.assertFalse(invoices.register(self.company)['rows'][0]['can_print'])
        restricted = invoices.get_settings(self.company)
        self.assertFalse(restricted['can_manage'])
        self.assertEqual(restricted['settings']['template_id'], 'pearl')
        self.assertFalse(restricted['settings']['account_number'])
        self.assertFalse(restricted['settings']['upi_id'])
        self.assertFalse(invoices.register(self.company)['can_manage_settings'])
        with self.assertRaises(frappe.PermissionError):
            invoices.save_settings(self.company, private, restricted['revision'])
        with self.assertRaises(frappe.PermissionError): invoices.print_data(self.company,invoice.name)
        with self.assertRaises(frappe.PermissionError): invoices.set_template(self.company,invoice.name,'grove')

    def test_native_india_tax_ids_print_as_gst_without_regional_fields(self):
        from erp_extensions import invoices
        seller, buyer = '33ABCDE1234F1Z5', '33ABCDF1234F1Z4'
        frappe.set_user('Administrator')
        company = frappe.get_doc('Company', self.company)
        company.country = 'India'
        company.tax_id = seller
        company.save()
        self.customer.tax_id = buyer
        self.customer.save()
        frappe.set_user(self.owner)
        invoice = self.invoice()
        data = invoices.print_data(self.company, invoice.name)
        self.assertEqual(data['company_gstin'], seller)
        self.assertEqual(data['customer_gstin'], buyer)
        self.assertIsNone(invoices._india_tax_id('ABCDE1234F', 'India'))
        self.assertIsNone(invoices._india_tax_id('GB123456789', 'India'))
        self.assertIsNone(invoices._india_tax_id(buyer, 'United Kingdom'))

    def test_print_includes_saved_order_dispatch_terms_and_neutral_tax_ids(self):
        from erp_extensions import invoices
        invoice = self.invoice()
        # Test the saved document's print contract independently of master data.
        frappe.db.set_value('Sales Invoice', invoice.name, {
            'company_tax_id': 'SELLER-991', 'tax_id': 'BUYER-238', 'po_date': '2026-11-10',
            'dispatch_address': 'Goods yard 14<br>Loading gate 2', 'named_place': 'South depot'})
        result = invoices.print_data(self.company, invoice.name)
        self.assertEqual(result['company_tax_id'], 'SELLER-991')
        self.assertEqual(result['tax_id'], 'BUYER-238')
        self.assertEqual(result['po_no'], 'PO-123')
        self.assertEqual(result['po_date'], '2026-11-10')
        self.assertEqual(result['dispatch_address'], 'Goods yard 14\nLoading gate 2')
        self.assertEqual(result['named_place'], 'South depot')
        self.assertNotIn('vehicle_no', result)

    def test_optional_print_fields_respect_saved_values_readability_and_masking(self):
        from erp_extensions import invoices
        fields = {'vehicle_no': 'TRUCK-57', 'lr_no': 'MASKED-123', 'transporter_name': 'PRIVATE',
            'shipping_rule': '', 'company_tax_id': 'VAT-456', 'unrelated_value': 'IGNORE'}
        meta = SimpleNamespace(has_field=fields.__contains__,
            get_masked_fields=lambda: [SimpleNamespace(fieldname='lr_no')])
        projected = SimpleNamespace(meta=meta, get=fields.get)
        with patch.object(invoices, '_fieldnames', return_value=set(fields) - {'transporter_name'}):
            self.assertEqual(invoices._print_particulars(projected),
                {'vehicle_no': 'TRUCK-57', 'company_tax_id': 'VAT-456'})

    def test_guest_is_denied(self):
        from erp_extensions import invoices
        frappe.set_user('Guest')
        with self.assertRaises(frappe.PermissionError): invoices.register(self.company)

    def test_delivery_to_posted_invoice_keeps_one_readable_dispatch_per_shipment(self):
        from erp_extensions import invoices
        from erpnext.stock.doctype.delivery_note.delivery_note import make_sales_invoice

        note = frappe.get_doc({
            'doctype': 'Delivery Note', 'company': self.company, 'customer': self.customer.name,
            'posting_date': today(), 'vehicle_no': 'SYNTHETIC-TRUCK', 'lr_no': 'TEST-LR',
            'lr_date': today(), 'items': [
                {'item_code': self.item.name, 'qty': qty, 'rate': 100} for qty in (1, 2)],
        }).insert().submit()
        invoice = make_sales_invoice(note.name)
        invoice.due_date = today()
        invoice.insert().submit()
        self.assertEqual([row.delivery_note for row in invoice.items], [note.name, note.name])
        printed = invoices.print_data(self.company, invoice.name)
        self.assertEqual(printed['delivery_notes'], [{
            'name': note.name, 'posting_date': str(note.posting_date), 'vehicle_no': 'SYNTHETIC-TRUCK',
            'lr_no': 'TEST-LR', 'lr_date': str(note.lr_date),
        }])

    def test_composer_creates_one_reviewed_draft_with_stock_and_service(self):
        from erp_extensions import invoice_compose as compose, invoices
        stock=frappe.get_doc({'doctype':'Item','item_code':'Stock '+self.suffix,'is_stock_item':1,'stock_uom':'Nos',
            'item_group':self.item.item_group,'item_defaults':[{'company':self.company,'default_warehouse':frappe.get_cached_value('Company',self.company,'default_warehouse')}]}).insert()
        price_list=frappe.db.get_value('Price List',{'selling':1,'enabled':1},'name')
        for item,rate in [(self.item,25),(stock,30)]:
            frappe.get_doc({'doctype':'Item Price','price_list':price_list,'item_code':item.name,'price_list_rate':rate}).insert()
        frappe.set_user('Administrator')
        parent=frappe.db.get_value('Account',{'company':self.company,'is_group':1,'root_type':'Liability'})
        duty=frappe.get_doc({'doctype':'Account','account_name':'Example duty','parent_account':parent,'account_type':'Tax','company':self.company}).insert()
        template=frappe.get_doc({'doctype':'Sales Taxes and Charges Template','company':self.company,'title':'Standard '+self.suffix,'is_default':1,
            'taxes':[{'charge_type':'On Net Total','account_head':duty.name,'description':'Configured levy','rate':10}]}).insert()
        frappe.set_user(self.owner)
        args={'company':self.company,'customer':self.customer.name,'posting_date':today(),'due_date':today(),
              'items':[{'item_code':self.item.name,'qty':'2'},{'item_code':stock.name,'qty':'1','rate':'35'}],'template_id':'grove'}
        preview=compose.preview(**args)
        self.assertEqual(float(preview['grand_total']),93.5)
        self.assertEqual(preview['taxes'][0]['label'],'Configured levy')
        self.assertEqual(float(preview['items'][0]['rate']),25)
        self.assertEqual(float(preview['items'][1]['rate']),35)
        self.assertEqual(frappe.db.count('Sales Invoice',{'company':self.company}),0)
        request=secrets.token_hex(16)
        from erp_extensions import operations
        frappe.set_user('Administrator')
        operations.install()
        frappe.set_user(self.owner)
        operations.begin_operation(self.company, 'invoice', request)
        result=compose.save_draft(**args,request_id=request,review=preview['review'])
        self.assertEqual(compose.save_draft(**args,request_id=request,review=preview['review'])['name'],result['name'])
        doc=frappe.get_doc('Sales Invoice',result['name'])
        self.assertEqual(doc.docstatus,0)
        self.assertEqual(doc.grand_total,93.5)
        self.assertEqual(doc.taxes_and_charges,template.name)
        self.assertEqual(invoices._style(doc.name),'grove')
        self.assertEqual(frappe.db.count('Sales Invoice',{'company':self.company}),1)
        recovered = operations.operation_status(self.company, request)
        self.assertEqual(recovered['state'], 'completed')
        self.assertEqual(recovered['result']['name'], result['name'])
        self.assertIn(request, [row['request_id'] for row in operations.pending_operations(self.company)['rows']])
        operations.acknowledge_operation(self.company, request)
        self.assertNotIn(request, [row['request_id'] for row in operations.pending_operations(self.company)['rows']])
        with self.assertRaises(frappe.ValidationError):
            compose.save_draft(**{**args,'items':[{'item_code':stock.name,'qty':'5'}]},request_id=request,review=preview['review'])
        with self.assertRaises(frappe.ValidationError):
            compose.save_draft(**args,request_id=secrets.token_hex(16),review='0'*64)
        with self.assertRaises(frappe.PermissionError):
            compose.preview(**{**args,'company':'ERP Native Verification'})
        current = invoices.get_settings(self.company)
        invoices.save_settings(self.company, dict(current['settings'], template_id='cobalt'), current['revision'])
        for chosen in ('', 'ledger'):
            args['template_id'] = chosen
            quote = compose.preview(**args)
            new = compose.save_draft(**args, request_id=secrets.token_hex(16), review=quote['review'])
            self.assertEqual(invoices._style(new['name']), chosen)
            printed = invoices.print_data(self.company, frappe.get_doc('Sales Invoice', new['name']).submit().name)
            self.assertEqual(printed['template_id'], chosen or 'cobalt')

    def test_company_stationery_is_inherited_and_payment_uses_the_actual_balance(self):
        import base64
        import json
        from decimal import Decimal
        from io import BytesIO
        from urllib.parse import parse_qs, urlsplit
        from PIL import Image
        from erp_extensions import invoice_compose, invoices

        posted = self.invoice()
        original_modified = str(posted.modified)
        initial = invoices.get_settings(self.company)
        self.assertTrue(initial['can_manage'])
        self.assertEqual(initial['settings']['template_id'], 'ledger')
        self.assertEqual(initial['revision'], '0')
        image = BytesIO()
        Image.new('RGBA', (830, 160), (0, 20, 130, 110)).save(image, 'PNG')
        configured = dict(initial['settings'], template_id='cobalt', accent_color='#722C37', bank_name='Example Bank',
            account_holder='Example & Co', account_number='0012340009', ifsc='test0123456',
            logo_base64=base64.b64encode(image.getvalue()).decode(), upi_id='example.test@demobank',
            upi_name='Example & Co', print_footer='Thank you for your order', signatory_name='Demo Manager')
        saved = invoices.save_settings(self.company, json.dumps(configured), initial['revision'])
        self.assertEqual(saved['settings']['account_number'], '0012340009')
        self.assertEqual(saved['settings']['ifsc'], 'TEST0123456')
        normalized = Image.open(BytesIO(base64.b64decode(saved['settings']['logo_base64'])))
        self.assertLessEqual(normalized.width, 768)
        self.assertEqual(normalized.mode, 'RGB')
        self.assertEqual(invoices.get_settings(self.company), saved)
        self.assertEqual(saved['settings']['accent_color'], '#722C37')
        legacy_settings = {key: value for key, value in saved['settings'].items() if key not in {'accent_color', 'print_footer', 'signatory_name'}}
        self.assertEqual(invoices.save_settings(self.company, legacy_settings, saved['revision']), saved)
        reg = invoices.register(self.company)
        self.assertTrue(reg['can_manage_settings'])
        self.assertEqual(reg['default_template_id'], 'cobalt')
        self.assertNotIn('settings', reg)
        self.assertEqual(invoice_compose.defaults(self.company)['template_id'], 'cobalt')
        data = invoices.print_data(self.company, posted.name)
        self.assertEqual(data['settings'], saved['settings'])
        self.assertEqual((data['template_id'], data['template_override']), ('cobalt', ''))
        uri = urlsplit(data['upi_uri'])
        self.assertEqual((uri.scheme, uri.netloc), ('upi', 'pay'))
        kv = parse_qs(uri.query)
        self.assertEqual(kv['pa'], ['example.test@demobank'])
        self.assertEqual(kv['pn'], ['Example & Co'])
        self.assertEqual(kv['cu'], ['INR'])
        self.assertEqual(kv['am'], ['300.00'])
        self.assertIn(posted.name, kv['tn'][0])
        self.assertFalse(data['signed_qr_code'])
        invoices.set_template(self.company, posted.name, 'ledger')
        self.assertEqual(invoices.print_data(self.company, posted.name)['template_id'], 'ledger')
        invoices.set_template(self.company, posted.name, '')
        data = invoices.print_data(self.company, posted.name)
        self.assertEqual(data['template_id'], 'cobalt')
        self.assertEqual(str(posted.reload().modified), original_modified)
        for changes in ({'docstatus': 0}, {'docstatus': 2}, {'is_return': True},
                        {'outstanding_amount': '0'}, {'outstanding_amount': '-1'},
                        {'outstanding_currency': 'USD'}, {'currency': 'USD'},
                        {'outstanding_amount': '0.004'}):
            self.assertFalse(invoices.payment_uri({**data, **changes}, saved['settings']), changes)
        partial = parse_qs(urlsplit(invoices.payment_uri({**data, 'outstanding_amount': Decimal('10.50')}, saved['settings'])).query)
        self.assertEqual(partial['am'], ['10.50'])
        with self.assertRaises(frappe.TimestampMismatchError):
            invoices.save_settings(self.company, dict(configured, bank_name='Older Bank'), initial['revision'])
        cleared = invoices.save_settings(self.company, initial['settings'], saved['revision'])
        self.assertEqual(cleared['settings'], initial['settings'])
        self.assertFalse(invoices.print_data(self.company, posted.name)['upi_uri'])
        self.assertEqual(str(posted.reload().modified), original_modified)

    def test_settings_deny_other_companies_and_invalid_images_or_payment_fields(self):
        from erp_extensions import invoices
        import base64
        initial = invoices.get_settings(self.company)
        for changes in ({'accent_color': '#FFFFFF'}, {'template_id':'orange'}, {'upi_id':'upi://pay?pa=other'},
                        {'upi_name':'Missing UPI id'}, {'account_number':'12!'}, {'bank_name':'Missing account'},
                        {'account_number':'0000123','ifsc':'INVALID'}, {'logo_base64': 'not a base64 image'},
                        {'logo_base64':base64.b64encode(b'<svg/>').decode()}, {'additional':'hidden'}):
            with self.assertRaises(frappe.ValidationError):
                invoices.save_settings(self.company, {**initial['settings'], **changes}, initial['revision'])
        self.assertEqual(invoices.get_settings(self.company), initial)
        for company in ('ERP Native Verification', 'missing-company'):
            with self.assertRaises(frappe.PermissionError): invoices.get_settings(company)
            with self.assertRaises(frappe.PermissionError): invoices.save_settings(company, initial['settings'], '0')
        frappe.set_user('Guest')
        with self.assertRaises(frappe.PermissionError): invoices.get_settings(self.company)
