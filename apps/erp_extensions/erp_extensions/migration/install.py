"""Install only the extension's immutable history tables; no customer imports."""
import frappe
from erp_extensions.knitting.install import field

SCOPE='Migration Scope'
RECORD='Historical Business Record'
AUTHORITY='Historical Posting Authority'
SCHEMAS={
    SCOPE:[field('source_instance',reqd=1,unique=1),
        *(field(f'company_{i}','Link','Company',reqd=1) for i in range(1,5)),
        field('scope_data','JSON',reqd=1),field('data_sha256',reqd=1)],
    RECORD:[field('source_scope','Link',SCOPE,reqd=1),field('source_key',reqd=1,unique=1),
        field('company','Link','Company'),field('source_company_id'),field('source_book'),
        field('namespace',reqd=1),field('native_id',reqd=1),field('family',reqd=1),
        field('original_reference'),field('original_date_raw'),field('effective_date','Date'),
        field('date_basis'),field('shared_cash','Check'),field('shared_reference','Check'),
        field('title'),field('summary','Small Text'),field('record_data','JSON',reqd=1),field('data_sha256',reqd=1)],
    AUTHORITY:[field('source_scope','Link',SCOPE,reqd=1),field('record','Link',RECORD,reqd=1),
        field('authority_key',reqd=1,unique=1),field('economic_key',reqd=1),field('effect_kind',reqd=1),
        field('company','Link','Company'),field('target_doctype','Link','DocType',reqd=1),
        field('target_name',reqd=1),field('proof_sha256',reqd=1)],
}


def install():
    for name,fields in SCHEMAS.items():
        if frappe.db.exists('DocType',name):
            doc=frappe.get_doc('DocType',name);known={f.fieldname for f in doc.fields}
            missing=[f for f in fields if f['fieldname'] not in known]
            for definition in missing:doc.append('fields',definition)
            if missing:doc.save()
        else:
            frappe.get_doc({'doctype':'DocType','name':name,'module':'Custom','custom':1,'autoname':'hash',
                'track_changes':0,'fields':fields,'permissions':[{'role':'System Manager','read':1}]}).insert()
    frappe.db.add_index(RECORD,['source_scope','company','family','effective_date'],'history_company_family')
    frappe.db.add_index(RECORD,['source_scope','shared_cash','effective_date'],'history_shared_cash')
    frappe.clear_cache();frappe.local.doc_events_hooks=None
