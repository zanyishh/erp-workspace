import unittest
from local_launch_profiles import merge


class LocalProfileTests(unittest.TestCase):
    def legacy(self):
        return {'workspaces':[{'site':'native-test.localhost','company':kind,'account':kind+'@example.invalid',
            'industry':kind,'key':'fixture-key','secret':'fixture-secret'} for kind in ('general','knitting')]}

    def test_customer_and_demo_refresh_preserve_each_other(self):
        customer={'id':'customer','label':'Your companies','site':'customer-migration.localhost',
            'origin':'http://127.0.0.1:8082','account':'fixture@example.invalid','key':'key','secret':'secret','company':'One'}
        initial=merge(self.legacy(),[customer],select='customer')
        refreshed=merge(initial,[{**initial['workspaces'][0],'key':'rotated'}])
        self.assertEqual(refreshed['selected_workspace'],'customer')
        self.assertEqual(refreshed['workspaces'][2],customer)
        self.assertEqual(len(refreshed['workspaces']),3)

    def test_identity_collision_does_not_overwrite_other_origin(self):
        with self.assertRaises(ValueError):merge(self.legacy(),[{'id':'demo-general','origin':'https://unexpected.invalid'}])


if __name__=='__main__':unittest.main()
