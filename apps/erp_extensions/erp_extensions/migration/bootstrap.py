"""Idempotent console bootstrap for a dedicated customer migration site."""
import secrets
import re
import frappe


def provision(values):
    if (getattr(frappe.local,'request',None) or frappe.session.user!='Administrator'
            or frappe.local.site!='customer-migration.localhost' or not frappe.conf.get('erp_customer_migration_enabled')):
        frappe.throw('Run customer provisioning only in its dedicated local workspace console.')
    from . import install,service,finance
    from erp_extensions.knitting.install import install as install_knitting
    from erp_extensions import workspace,invoices
    install.install();finance.install();install_knitting();invoices.install()
    from erpnext.setup.setup_wizard.operations.install_fixtures import install as install_baseline, install_defaults
    if not frappe.db.exists('Warehouse Type','Transit'):
        install_baseline('India')
    scope=values['scope'];profiles=values['companies'];account=values['account']
    if set(profiles)!=set(scope['company_bindings']) or account not in scope['allowed_users']:
        frappe.throw('The customer company and owner bindings must match the reviewed scope.')
    for year in range(2023,2027):
        name=f'{year}-{year+1}'
        if not frappe.db.exists('Fiscal Year',name):
            frappe.get_doc({'doctype':'Fiscal Year','year':name,'year_start_date':f'{year}-04-01',
                'year_end_date':f'{year+1}-03-31'}).insert()
    if not frappe.db.exists('UOM','Kg'):
        frappe.get_doc({'doctype':'UOM','uom_name':'Kg','must_be_whole_number':0}).insert()
    result={}
    for cid,name in scope['company_bindings'].items():
        profile=profiles[cid]
        phones=[value.strip() for value in re.split(r'[,;]',profile.get('phone_no') or '') if value.strip()]
        emails=[value.strip() for value in re.split(r'[,;]',profile.get('email') or '') if value.strip()]
        if profile['name']!=name:frappe.throw('Original company names must match their separate destination bindings.')
        if not frappe.db.exists('Company',name):
            frappe.get_doc({'doctype':'Company','company_name':name,'abbr':'KP'+cid,'default_currency':'INR',
                'country':'India','chart_of_accounts':'Standard','tax_id':profile.get('gstin') or '',
                'phone_no':phones[0] if phones else '', 'email':emails[0] if emails else ''}).insert()
        company=frappe.get_doc('Company',name)
        if company.abbr!='KP'+cid or company.default_currency!='INR':
            frappe.throw('An existing destination company conflicts with the reviewed mapping.')
        contact='KP-COMPANY-CONTACT-'+cid
        if not frappe.db.exists('Contact',contact) and (phones or emails):
            frappe.get_doc({'doctype':'Contact','first_name':name,'phone_nos':[{'phone':value} for value in phones],
                'email_ids':[{'email_id':value} for value in emails],
                'links':[{'link_doctype':'Company','link_name':name}]}).insert(set_name=contact)
        warehouse=frappe.db.get_value('Warehouse',{'company':name,'is_group':0},'name')
        items={}
        for key,stock,label in (('SERVICE',0,'Knitting services'),('FABRIC',1,'Knitted fabric')):
            code=f'KP-{cid}-{key}'
            if not frappe.db.exists('Item',code):
                frappe.get_doc({'doctype':'Item','item_code':code,'item_name':label,'stock_uom':'Kg',
                    'item_group':frappe.db.get_value('Item Group',{'is_group':0},'name'),'is_stock_item':stock,
                    'item_defaults':[{'company':name,'default_warehouse':warehouse}]}).insert()
            items[key.lower()]=code
        from erp_extensions.knitting.permissions import profile as industry_profile
        existing=industry_profile(name)
        if not existing:
            workspace.configure(name,{'state':'Active','warehouse':warehouse,'service_item':items['service'],
                'fabric_item':items['fabric'],'shifts':['A','B'],'number_prefix':'KN'})
        result[cid]={'company':name,'warehouse':warehouse,'service_item':items['service'],'fabric_item':items['fabric'],
            'cost_center':company.cost_center,'receivable':company.default_receivable_account,'payable':company.default_payable_account}
    if not frappe.db.get_single_value('Global Defaults','default_company'):
        install_defaults(frappe._dict(company_name=scope['company_bindings']['1'],currency='INR',country='India',
            fy_start_date='2026-04-01',fy_end_date='2027-03-31',fiscal_year='2026-2027'))
    if not frappe.db.exists('User',account):
        roles=[r for r in ('System Manager','Accounts Manager','Sales Manager','Purchase Manager','Stock Manager',
            'Manufacturing Manager','Knitting Manager') if frappe.db.exists('Role',r)]
        frappe.get_doc({'doctype':'User','email':account,'first_name':'Workspace owner','send_welcome_email':0,
            'new_password':secrets.token_urlsafe(36),'roles':[{'role':r} for r in roles]}).insert()
    if 'System Manager' not in frappe.get_roles(account):frappe.throw('The reviewed local owner must have the expected role.')
    for company in scope['company_bindings'].values():
        if not frappe.db.exists('User Permission',{'user':account,'allow':'Company','for_value':company}):
            frappe.get_doc({'doctype':'User Permission','user':account,'allow':'Company','for_value':company,'apply_to_all_doctypes':1}).insert()
    scope_name=service.create_scope(scope)
    books=[{'source_company_id':cid,'source_book':str(book),'finance_book':f'KP{cid} · Book {book}'}
           for cid in scope['company_bindings'] for book in range(3)]
    finance.configure_books(scope_name,books)
    for party in values['parties']:
        pid=party['source_id'];title=party['party_name']
        for doctype,code in [('Customer','KP-PARTY-'+pid)]+([('Supplier','KP-SUPPLIER-'+pid)] if party.get('supplier') else []):
            titlefield=doctype.lower()+'_name'
            if frappe.db.exists(doctype,code):
                if frappe.db.get_value(doctype,code,titlefield)!=title:
                    frappe.throw('An existing party differs from its original identity.')
                continue
            fields={'doctype':doctype,titlefield:title,doctype.lower()+'_type':'Company'}
            if doctype=='Customer':fields.update(customer_group=frappe.db.get_value('Customer Group',{'is_group':0},'name'),territory='India')
            else:fields.update(supplier_group=frappe.db.get_value('Supplier Group',{'is_group':0},'name'))
            frappe.get_doc(fields).insert(set_name=code)
    frappe.db.commit()
    return {'scope':scope_name,'companies':result,'books':books,'party_count':len(values['parties'])}


def local_profile():
    if (getattr(frappe.local,'request',None) or frappe.session.user!='Administrator'
            or frappe.local.site!='customer-migration.localhost' or not frappe.conf.get('erp_customer_migration_enabled')):
        frappe.throw('Prepare the customer profile only through its local console.')
    from . import service
    from .install import SCOPE
    from erp_extensions.workspace import context
    from frappe.core.doctype.user.user import generate_keys
    from frappe.utils.password import get_decrypted_password
    scopes=frappe.get_all(SCOPE,fields=['name'],limit=2)
    if len(scopes)!=1:frappe.throw('The local customer profile requires one reviewed source scope.')
    scope=service.get_scope(scopes[0].name)
    accounts=[user for user in scope['allowed_users'] if user!='Administrator']
    if len(accounts)!=1:frappe.throw('The customer profile needs its explicit local owner.')
    account=accounts[0]
    frappe.set_user(account)
    try:
        state=context(scope['company_bindings']['1'])
        if {c.name for c in state['companies']}!=set(scope['company_bindings'].values()):
            frappe.throw('The local owner has an unexpected company scope.')
    finally:frappe.set_user('Administrator')
    key=frappe.db.get_value('User',account,'api_key')
    secret=get_decrypted_password('User',account,'api_secret',raise_exception=False) if key else None
    if not key or not secret:
        credentials=generate_keys(account);key,secret=credentials['api_key'],credentials['api_secret']
    frappe.db.commit()
    return {'id':'customer','label':'Your companies','origin':'http://127.0.0.1:8082',
        'site':frappe.local.site,'company':scope['company_bindings']['1'],'account':account,'key':key,'secret':secret}


def prepare_finance_accounts(scope_name,specs):
    if (getattr(frappe.local,'request',None) or frappe.session.user!='Administrator'
            or frappe.local.site!='customer-migration.localhost' or not frappe.conf.get('erp_customer_migration_enabled')):
        frappe.throw('Prepare historical accounts only in the dedicated customer console.')
    from . import service
    scope=service.get_scope(scope_name);result={}
    for cid,company in scope['company_bindings'].items():
        result[cid]={}
        for key,spec in specs.items():
            name=spec['account_name']+' - '+frappe.get_cached_value('Company',company,'abbr')
            if not frappe.db.exists('Account',name):
                parent=frappe.db.get_value('Account',{'company':company,'root_type':spec['root_type'],
                    'is_group':1,'parent_account':['is','not set']},'name')
                if not parent:frappe.throw('The native chart is missing its required account root.')
                frappe.get_doc({'doctype':'Account','company':company,'account_name':spec['account_name'],
                    'parent_account':parent,'account_type':spec['account_type'],'is_group':0,
                    'account_currency':'INR','report_type':'Profit and Loss' if spec['root_type'] in ('Income','Expense') else 'Balance Sheet'}).insert()
            account=frappe.get_doc('Account',name)
            if account.company!=company or account.root_type!=spec['root_type'] or (account.account_type or '')!=spec['account_type']:
                frappe.throw('An existing target account conflicts with its reviewed mapping.')
            result[cid][key]=name
        company_doc=frappe.get_doc('Company',company)
        company_doc.default_receivable_account=result[cid]['receivable']
        company_doc.default_payable_account=result[cid]['payable']
        company_doc.save()
    frappe.db.commit()
    return result


def apply_branding(scope_name,profiles):
    if (getattr(frappe.local,'request',None) or frappe.session.user!='Administrator'
            or frappe.local.site!='customer-migration.localhost' or not frappe.conf.get('erp_customer_migration_enabled')):
        frappe.throw('Prepare customer artwork only in its dedicated local console.')
    import base64,hashlib
    from . import service
    from erp_extensions import invoice_settings
    from erp_extensions.invoices import DEFAULT_STYLE
    from frappe.utils.file_manager import save_file
    scope=service.get_scope(scope_name);result={}
    for cid,profile in profiles.items():
        company=scope['company_bindings'][cid]
        if frappe.db.exists(invoice_settings.PROFILE,company):
            result[cid]={'created':False};continue
        values={key:'' for key in invoice_settings.FIELDS}
        values.update(template_id=DEFAULT_STYLE,bank_name=profile['bank_name'],account_number=profile['acc_no'],
            account_holder=company if profile['acc_no'] else '',ifsc=profile['ifsc'],logo_base64=profile['logo_base64'])
        invoice_settings.save(company,values,'0')
        logo_hash=None
        if profile['logo_base64']:
            content=base64.b64decode(profile['logo_base64'],validate=True);logo_hash=hashlib.sha256(content).hexdigest()
            file=save_file('original-company-logo-'+cid+'.png',content,'Company',company,is_private=1)
            company_doc=frappe.get_doc('Company',company);company_doc.company_logo=file.file_url;company_doc.save()
        result[cid]={'created':True,'original_logo_sha256':logo_hash,'bank_details_present':bool(profile['acc_no'])}
    frappe.db.commit();return result
