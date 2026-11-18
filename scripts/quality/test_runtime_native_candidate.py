"""Exact native-addon additions preserve the verified baseline and providers."""
import copy
import importlib.util
from pathlib import Path
import unittest

SECURITY=Path(__file__).resolve().parents[2]/'infrastructure/erpnext/security'
spec=importlib.util.spec_from_file_location('builder',SECURITY/'build-runtime-image.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)


class NativeCandidateTests(unittest.TestCase):
    def fixture(self):
        baseline={'schema':1,'files':{'/old.node':{'sha256':'a'*64}},
                  'node_needed':['libc.so.6'],'runtime_libraries':{'/lib/libc.so.6':{'sha256':'b'*64,'needed':[]}},
                  'foreign_platform_addons':[]}
        additions={name:{'sha256':'c'*64,'target_imports':[],'search_paths':[],
                         'elf_machine':183,'needed':['libc.so' if '-musl/' in name else 'libc.so.6']}
                   for name in builder.NATIVE_CANDIDATE_ADDITIONS}
        candidate=copy.deepcopy(baseline);candidate['files'].update(copy.deepcopy(additions))
        candidate['foreign_platform_addons']=sorted(name for name in additions if '-musl/' in name)
        return baseline,candidate,additions

    def test_exact_four_reviewed_additions_pass(self):
        builder.verify_native_candidate_inventory(*self.fixture())

    def test_changed_sha_path_unexpected_file_and_provider_fail(self):
        for changed in ('sha','path','extra','provider','original','import','search','new_dependency'):
            with self.subTest(changed=changed):
                baseline,candidate,additions=self.fixture();name=next(iter(additions))
                if changed=='sha':candidate['files'][name]['sha256']='d'*64
                elif changed=='path':additions[name+'/other']=additions.pop(name)
                elif changed=='extra':candidate['files']['/unreviewed.node']={}
                elif changed=='provider':candidate['runtime_libraries']['/lib/libc.so.6']['sha256']='d'*64
                elif changed=='original':candidate['files']['/old.node']['sha256']='d'*64
                elif changed=='import':additions[name]['target_imports']=['gzwrite']
                elif changed=='search':additions[name]['search_paths']=['/unreviewed']
                else:
                    name=next(n for n in additions if '-gnu/' in n);additions[name]['needed']=['libunreviewed.so']
                with self.assertRaises(ValueError):builder.verify_native_candidate_inventory(baseline,candidate,additions)


if __name__=='__main__':unittest.main()
