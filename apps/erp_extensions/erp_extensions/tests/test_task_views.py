"""Check status-board and calendar reads on the isolated native ERP."""
import os
import unittest

import frappe


class TaskViewsTests(unittest.TestCase):
    def setUp(self):
        os.chdir('/home/frappe/frappe-bench/sites')
        frappe.init(site='native-test.localhost', sites_path='.')
        frappe.connect()
        self.addCleanup(frappe.destroy)
        self.addCleanup(frappe.db.rollback)
        frappe.set_user('Administrator')
        from erp_extensions import onboarding
        frappe.set_user('Guest')
        key = frappe.generate_hash(length=10)
        self.owner = f'task-{key}@example.invalid'
        self.company = f'Planning {key}'
        onboarding.register_owner('Planner', self.owner, 'River 7! winter sample 29', self.company, 'general')
        frappe.set_user(self.owner)

    def test_calendar_overlap_paging_and_status_edit_use_real_company_records(self):
        from erp_extensions import api
        def create(subject, start=None, end=None):
            values = {'doctype':'Task', '__islocal':1, 'company':self.company, 'subject':subject}
            if start: values['exp_start_date'] = start
            if end: values['exp_end_date'] = end
            return api.save(values)['doc']
        span = create('Inspect shipment', '2031-03-31 12:15:00', '2031-04-02 08:00:00')
        cutoff = create('Issue shipment', '2031-05-01 00:00:00')
        due = create('Due without start', end='2031-04-18 11:00:00')
        unscheduled = create('Arrange pickup')
        month = api.task_view(self.company, month='2031-04')
        self.assertEqual({r.name for r in month['rows']}, {span['name'], due['name']})
        self.assertFalse(month['has_more'])
        board = api.task_view(self.company)
        self.assertEqual({r.name for r in board['rows']},
                         {span['name'], cutoff['name'], due['name'], unscheduled['name']})
        self.assertIn('Working', board['statuses'])
        self.assertEqual(api.task_view(self.company, start=4)['rows'], [])
        updated = api.save({'doctype':'Task','name':span['name'], 'modified':span['modified'],'status':'Working'})
        self.assertEqual(updated['doc']['status'], 'Working')
        self.assertEqual([r.name for r in api.task_view(self.company, status='Working')['rows']], [span['name']])
        with self.assertRaises(frappe.PermissionError):
            api.task_view('ERP Native Verification')
        with self.assertRaises(frappe.ValidationError):
            api.task_view(self.company, month='tomorrow')
        upstream_task = create("Check invoice")
        dependent = api.save({'doctype':'Task', '__islocal':1, 'company':self.company, 'subject':'Approve invoice',
                              'depends_on':[{'task':upstream_task['name']}]})['doc']
        def finish(task):
            return api.save({'doctype':'Task','name':task['name'], 'modified':task['modified'],'status':'Completed'})['doc']
        with self.assertRaises(frappe.ValidationError):
            finish(dependent)
        self.assertEqual(api.document('Task', dependent['name'])['doc']['status'], 'Open')
        finish(upstream_task)
        self.assertEqual(finish(dependent)['status'], 'Completed')


    def test_project_template_creates_scheduled_tasks_and_remaps_dependencies(self):
        from erp_extensions import api
        def task(subject, offset, dependencies=()):
            return api.save({'doctype':'Task', '__islocal':1, 'company':self.company,
                             'subject':subject, 'is_template':1, 'start':offset, 'duration':1,
                             'depends_on':[{'task':name} for name in dependencies]})['doc']['name']
        cut = task('Cut fabric', 0)
        inspect = task('Inspect fabric', 2, [cut])
        template = api.save({'doctype':'Project Template', '__islocal':1, '__newname':'Cut and inspect ' + self.company,
                             'tasks':[{'task':cut}, {'task':inspect}]})['doc']['name']
        self.assertIn(template, [row['value'] for row in api.search_link('Project Template')])
        project = api.save({'doctype':'Project','__islocal':1,'company':self.company, 'project_name':'Trial ' + self.company, 'project_template':template,
                            'expected_start_date':'2031-04-02','expected_end_date':'2031-04-10'})['doc']
        plan = [r for r in api.task_view(self.company, month='2031-04')['rows'] if r.project == project['name']]
        self.assertEqual(len(plan), 2)
        copies = {r.subject:api.document('Task', r.name)['doc'] for r in plan}
        self.assertEqual(str(copies['Inspect fabric']['exp_start_date'])[:10], '2031-04-04')
        self.assertEqual(copies['Inspect fabric']['depends_on'][0]['task'], copies['Cut fabric']['name'])
        self.assertNotEqual(copies['Cut fabric']['name'], cut)
