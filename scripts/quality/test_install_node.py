import unittest

from install_node import matches_manifest


class NodeSecurityLockTests(unittest.TestCase):
    def test_stale_security_override_cannot_reuse_old_lock(self):
        manifest = {"devDependencies": {"tool": "1.0.0"}, "overrides": {"axios": "1.21.1"}}
        lock = {"lockfileVersion": 3, "packages": {
            "": {"devDependencies": {"tool": "1.0.0"}},
            "node_modules/tool": {"version": "1.0.0"},
            "node_modules/axios": {"version": "1.21.1"},
            "node_modules/tool/node_modules/axios": {"version": "1.18.0"},
        }}
        self.assertFalse(matches_manifest(lock, manifest))
        lock["packages"]["node_modules/tool/node_modules/axios"]["version"] = "1.21.1"
        self.assertTrue(matches_manifest(lock, manifest))

    def test_scoped_override_must_exist_in_resolved_lock(self):
        manifest = {"overrides": {"@faker-js/faker": "10.5.0"}}
        lock = {"lockfileVersion": 3, "packages": {"": {}}}
        self.assertFalse(matches_manifest(lock, manifest))
        lock["packages"]["node_modules/tool/node_modules/@faker-js/faker"] = {"version": "10.5.0"}
        self.assertTrue(matches_manifest(lock, manifest))


if __name__ == "__main__":
    unittest.main()
