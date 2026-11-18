import unittest
from prepare_knitpack_operations import compile_job


class OperationPreparationTests(unittest.TestCase):
    def sample(self):
        return {'job':{'id':'14','companymas_id':'1','invoice_type':'service','completed':'0',
            'jobdate':'2023-06-03','jobno':'1','partymas_id':'2','billed_to':'3','duedate':'0000-00-00',
            'sec_acc':'1','total_prgrm_qty':'100.000'},'fabs':[{'id':'7','jobmas_id':'14','fabName':'Jersey',
            'billrate':'30.50','dias':[{'id':'9','jobfabric_id':'7','diaorsize':'30','programqty':'100.000',
            'stock_kgs':'88.123','stock_rolls':'7.000','prod_qty':'90.000'}]}]}, {'id':'14','yarn_mas':[]}

    def test_preserves_dates_roles_counts_and_negative_source_values(self):
        context,yarn=self.sample()
        result=compile_job('Synthetic',context,yarn,{'2':'Customer A','3':'Customer B'})
        self.assertEqual(result['job']['job_date'],'2023-06-03')
        self.assertEqual(result['job']['customer'],'Customer A')
        self.assertEqual(result['job']['billing_customer'],'Customer B')
        self.assertEqual((result['batches'][0]['quantity_kg'],result['batches'][0]['rolls']),('88.123','7'))
        self.assertNotIn('weight_kg',result['batches'][0])
        context['fabs'][0]['dias'][0]['stock_kgs']='-0.125'
        self.assertEqual(compile_job('Synthetic',context,yarn,{'2':'A','3':'B'})['batches'][0]['quantity_kg'],'-0.125')

    def test_refuses_fractional_rolls_and_changed_scope(self):
        context,yarn=self.sample();context['fabs'][0]['dias'][0]['stock_rolls']='0.5'
        with self.assertRaises(ValueError):compile_job('Synthetic',context,yarn,{'2':'A','3':'B'})
        context,yarn=self.sample();yarn['id']='15'
        with self.assertRaises(ValueError):compile_job('Synthetic',context,yarn,{'2':'A','3':'B'})


if __name__=='__main__':unittest.main()
