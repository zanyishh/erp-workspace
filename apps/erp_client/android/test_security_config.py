"""Release/debug Android security policy checks; no device or private data needed."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
ANDROID = '{http://schemas.android.com/apk/res/android}'


class AndroidSecurityConfigTests(unittest.TestCase):
    def test_release_network_policy_rejects_all_cleartext(self):
        config = ET.parse(ROOT / 'app/src/main/res/xml/network_security_config.xml').getroot()
        self.assertEqual(config.find('base-config').get('cleartextTrafficPermitted'), 'false')
        self.assertFalse(any(node.get('cleartextTrafficPermitted') == 'true' for node in config.iter()))

    def test_debug_network_exceptions_are_loopback_only(self):
        config = ET.parse(ROOT / 'app/src/debug/res/xml/network_security_config.xml').getroot()
        self.assertEqual(config.find('base-config').get('cleartextTrafficPermitted'), 'false')
        domains = config.findall('domain-config/domain')
        self.assertEqual({node.text for node in domains}, {'localhost', '127.0.0.1', '10.0.2.2'})
        self.assertTrue(all(node.get('includeSubdomains') == 'false' for node in domains))
        self.assertEqual(config.find('domain-config').get('cleartextTrafficPermitted'), 'true')

    def test_credentials_are_excluded_from_backup_and_device_transfer(self):
        app = ET.parse(ROOT / 'app/src/main/AndroidManifest.xml').getroot().find('application')
        self.assertEqual(app.get(ANDROID + 'allowBackup'), 'false')
        self.assertEqual(app.get(ANDROID + 'fullBackupContent'), 'false')
        self.assertEqual(app.get(ANDROID + 'dataExtractionRules'), '@xml/data_extraction_rules')
        rules = ET.parse(ROOT / 'app/src/main/res/xml/data_extraction_rules.xml').getroot()
        domains = {'root', 'file', 'database', 'sharedpref', 'external',
                   'device_root', 'device_file', 'device_database', 'device_sharedpref'}
        for mode in ('cloud-backup', 'device-transfer', 'cross-platform-transfer[@platform="ios"]'):
            with self.subTest(mode=mode):
                section = rules.find(mode)
                self.assertIsNotNone(section)
                self.assertFalse(section.findall('include'))
                self.assertEqual({node.get('domain') for node in section.findall('exclude')
                                  if node.get('path') == '.'}, domains)

    def test_minimum_platform_includes_the_task_hijacking_os_fix(self):
        build = (ROOT / 'app/build.gradle.kts').read_text()
        minimum = re.search(r'^\s*minSdk\s*=\s*(\d+)\s*$', build, re.MULTILINE)
        self.assertIsNotNone(minimum, 'Keep the supported Android security floor explicit.')
        self.assertGreaterEqual(int(minimum.group(1)), 30)
        activity = ET.parse(ROOT / 'app/src/main/AndroidManifest.xml').getroot().find('application/activity')
        self.assertEqual(activity.get(ANDROID + 'taskAffinity'), '')


if __name__ == '__main__':
    unittest.main()
