"""Exact master category reads using rollback-only native-test fixtures."""
from datetime import datetime

import frappe

from erp_extensions.tests import test_knitting as fixtures


class MasterRegisterTests(fixtures.KnittingTests):
    def seed_master(self, name, **values):
        if frappe.local.site != 'native-test.localhost':
            raise RuntimeError('Synthetic masters require native-test.localhost')
        frappe.get_doc({'doctype': 'Knitting Master', 'name': name, 'company': fixtures.COMPANY,
            'creation': datetime(2020, 1, 1), 'modified': datetime(2020, 1, 1),
            'owner': 'Administrator', 'modified_by': 'Administrator', 'category': 'Fabric',
            'title': name, 'enabled': 1, 'specification': '{}', **values}).db_insert()
        return name

    def test_category_filters_before_paging_and_retains_complete_disabled_master_settings(self):
        self.fixtures()
        prefix = 'SYN-MASTER-' + frappe.generate_hash(length=7)
        settings = {'description': 'Synthetic definition', 'value': 0, 'severity': False,
                    'order': 0, 'unit': 'kg', 'boundary_kg': '100.000'}
        names = [self.seed_master(f'{prefix}-{i:03}', enabled=int(i != 102),
            specification=frappe.as_json(settings)) for i in range(103)]
        self.seed_master(prefix+'-yarn', category='Yarn variety')
        self.seed_master(prefix+'-foreign', company='ERP Native Verification')
        found=[]
        for start, size in ((0,100),(100,3)):
            try:page=self.knitting().register(fixtures.COMPANY, 'masters', query=prefix,
                category='Fabric', start=start)
            except (TypeError,frappe.ValidationError) as error:
                self.fail('Exact master category filtering is required: '+str(error))
            self.assertEqual(page['category'],'Fabric')
            self.assertEqual(page['page'],{'start':start,'limit':100,'has_more':start==0,'total':103})
            self.assertEqual(len(page['rows']),size)
            for row in page['rows']:
                self.assertEqual(row.category,'Fabric')
                self.assertEqual(frappe.parse_json(row.specification),settings)
                self.assertTrue(row.modified)
                found.append(row.name)
        self.assertEqual(set(found),set(names))
        disabled=self.knitting().register(fixtures.COMPANY,'masters',query=names[-1],category='Fabric')['rows']
        self.assertEqual(disabled[0].enabled,0)

    def test_master_category_contract_rejects_unsupported_values_and_other_registers(self):
        self.fixtures()
        for category in ('','fabric','Unknown category',True,['Fabric'],{'value':'Fabric'}):
            with self.subTest(category=category),self.assertRaises(frappe.ValidationError):
                self.knitting().register(fixtures.COMPANY,'masters',category=category)
        with self.assertRaises(frappe.ValidationError):
            self.knitting().register(fixtures.COMPANY,'jobs',category='Fabric')
        page=self.knitting().register(fixtures.COMPANY,'masters')
        self.assertIsNone(page['category'])

    def test_master_category_read_retains_company_and_record_permissions(self):
        self.fixtures()
        prefix='SYN-MASTER-ACCESS-'+frappe.generate_hash(length=7)
        allowed=self.seed_master(prefix+'-allowed')
        hidden=self.seed_master(prefix+'-hidden')
        user='knit-operator@example.invalid'
        frappe.get_doc({'doctype':'User Permission','user':user,'allow':'Company',
            'for_value':fixtures.COMPANY,'apply_to_all_doctypes':1}).insert()
        frappe.get_doc({'doctype':'User Permission','user':user,'allow':'Knitting Master',
            'for_value':allowed,'apply_to_all_doctypes':1}).insert()
        frappe.set_user(user)
        page=self.knitting().register(fixtures.COMPANY,'masters',query=prefix,category='Fabric')
        self.assertEqual([row.name for row in page['rows']],[allowed])
        self.assertEqual(page['page']['total'],1)
        self.assertNotIn(hidden,[row.name for row in page['rows']])
        with self.assertRaises(frappe.PermissionError):
            self.knitting().register('ERP Native Verification','masters',category='Fabric')

    def test_existing_master_settings_and_disabled_state_survive_reviewed_edit_and_stale_rejection(self):
        self.fixtures()
        settings={'description':'Before','value':0,'severity':False,'order':0,'unit':'kg'}
        created=self.call('save_master',{'category':'QC defect','title':'Synthetic setting preservation',
            'settings':settings})['data']['master']
        frappe.db.set_value('Knitting Master',created,'enabled',0)
        old=str(frappe.db.get_value('Knitting Master',created,'modified'))
        edited={**settings,'description':'After'}
        self.call('save_master',{'master':created,'master_modified':old,'category':'QC defect',
            'title':'Synthetic renamed definition','enabled':0,'settings':edited})
        current=frappe.get_doc('Knitting Master',created)
        self.assertEqual(frappe.parse_json(current.specification),edited)
        self.assertEqual(current.enabled,0)
        self.assertNotEqual(str(current.modified),old)
        before=current.as_dict()
        with self.assertRaises(frappe.TimestampMismatchError):
            self.call('save_master',{'master':created,'master_modified':old,'category':'QC defect',
                'title':'Stale name must not save','enabled':1,'settings':{'value':'lost'}})
        self.assertEqual(frappe.get_doc('Knitting Master',created).as_dict(),before)
        frappe.set_user('knit-operator@example.invalid')
        with self.assertRaises(frappe.PermissionError):
            self.call('save_master',{'master':created,'master_modified':str(current.modified),
                'category':'QC defect','title':'Read-only change must not save','settings':{}})
        self.assertEqual(frappe.get_doc('Knitting Master',created).as_dict(),before)

    def test_explicit_empty_settings_clear_definition_without_legacy_field_contamination(self):
        self.fixtures()
        created=self.call('save_master',{'category':'Fabric','title':'Synthetic cleared definition',
            'settings':{'description':'Old description','unit':'kg','order':0}})['data']['master']
        version=str(frappe.db.get_value('Knitting Master',created,'modified'))
        self.call('save_master',{'master':created,'master_modified':version,'category':'Fabric',
            'title':'Synthetic cleared definition','settings':{},'unit':'Stale other definition',
            'description':'Stale legacy field'})
        self.assertEqual(frappe.parse_json(frappe.db.get_value('Knitting Master',created,'specification')), {})

