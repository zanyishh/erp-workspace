import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from install_runtime_node import install


class RuntimeNodeInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'image'
        self.payload = self.base / 'payload'
        self.payload.mkdir()
        self.target_path = '/home/frappe/frappe-bench/apps/frappe/node_modules/example'
        self.target = self.root / self.target_path.lstrip('/')
        self.target.mkdir(parents=True)
        (self.target / 'package.json').write_text(json.dumps({'name':'example','version':'1.0.0'}))
        (self.target / 'stale.js').write_text('old implementation')
        self.archive = self.payload / 'example.tgz'
        self.make_archive()
        self.manifest = {'packages':[{'name':'example','version':'1.0.1','archive':'example.tgz'}],
                         'replacements':[{'package':'example','target_path':self.target_path,
                         'installed_version':'1.0.0','replacement_version':'1.0.1','archive':'example.tgz',
                         'installed_package_sha256':hashlib.sha256((self.target/'package.json').read_bytes()).hexdigest(),
                         'tar_sha256':hashlib.sha256(self.archive.read_bytes()).hexdigest()}]}

    def make_archive(self, unsafe=False, package_name='example'):
        files = {'package/package.json':json.dumps({'name':package_name,'version':'1.0.1'}),
                 'package/index.js':'module.exports = 1;', 'package/LICENSE':'Original license notice'}
        if unsafe:
            files['package/../../outside.txt'] = 'must not escape'
        with tarfile.open(self.archive,'w:gz') as archive:
            for name, value in files.items():
                data=value.encode(); member=tarfile.TarInfo(name); member.size=len(data)
                archive.addfile(member,io.BytesIO(data))

    def run_install(self):
        return install(self.manifest,self.payload,self.root,self.base/'receipt.json')

    def test_tampered_archive_leaves_existing_package_untouched(self):
        with self.archive.open('ab') as stream: stream.write(b'changed')
        with self.assertRaisesRegex(ValueError,'checksum'): self.run_install()
        self.assertEqual(json.loads((self.target/'package.json').read_text())['version'],'1.0.0')
        self.assertTrue((self.target/'stale.js').exists())

    def test_preimage_mismatch_aborts_before_any_replacement(self):
        self.manifest['replacements'].append({**self.manifest['replacements'][0],
            'target_path':self.target_path+'-second','installed_package_sha256':'0'*64})
        other=self.root/(self.target_path+'-second').lstrip('/');other.mkdir()
        (other/'package.json').write_text((self.target/'package.json').read_text())
        with self.assertRaisesRegex(ValueError,'preimage'): self.run_install()
        self.assertTrue((self.target/'stale.js').exists())

    def test_unsafe_archive_path_is_rejected_before_extraction(self):
        self.make_archive(unsafe=True)
        self.manifest['replacements'][0]['tar_sha256']=hashlib.sha256(self.archive.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError,'archive path'): self.run_install()
        self.assertFalse((self.base/'outside.txt').exists())
        self.assertTrue((self.target/'stale.js').exists())

    def test_package_identity_cannot_be_changed_by_archive(self):
        self.make_archive(package_name='unexpected')
        self.manifest['replacements'][0]['tar_sha256']=hashlib.sha256(self.archive.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError,'package contract'): self.run_install()
        self.assertTrue((self.target/'stale.js').exists())

    def test_replacement_removes_stale_code_and_retains_notice(self):
        result=self.run_install()
        self.assertFalse((self.target/'stale.js').exists())
        self.assertEqual((self.target/'LICENSE').read_text(),'Original license notice')
        self.assertEqual(json.loads((self.target/'package.json').read_text())['version'],'1.0.1')
        self.assertEqual(result['replaced'],1)
        self.assertFalse(result['browser_assets_rebuilt'])

    def test_proven_orphan_requires_exact_preimage_before_removal(self):
        orphan=self.target.parent/'old-helper';orphan.mkdir()
        metadata=orphan/'package.json';metadata.write_text(json.dumps({'name':'old-helper','version':'1.0.0'}))
        entry={'target_path':self.target_path.rsplit('/',1)[0]+'/old-helper',
               'package':'old-helper','installed_version':'1.0.0','installed_package_sha256':'0'*64,
               'consumer_replacement':{'package':'example','version':'1.0.1'}}
        self.manifest['orphan_package_removals']=[entry]
        with self.assertRaisesRegex(ValueError,'preimage'):self.run_install()
        self.assertTrue(orphan.exists());self.assertTrue((self.target/'stale.js').exists())
        entry['installed_package_sha256']=hashlib.sha256(metadata.read_bytes()).hexdigest()
        self.assertEqual(self.run_install()['orphan_packages_removed'],1)
        self.assertFalse(orphan.exists())


if __name__=='__main__': unittest.main()
