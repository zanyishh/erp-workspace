#!/usr/bin/env python3
"""Boundary checks for the exact reviewed libXi exception."""
import importlib.util
import json
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('x11_abi',HERE/'os-x11-abi-check.py')
abi=importlib.util.module_from_spec(spec);spec.loader.exec_module(abi)
CONTRACT=json.loads((HERE/'os-x11-abi-contract.json').read_text())
BASELINE=('\n'.join(sorted(set(CONTRACT['preserved_symbols'])|abi.MARKERS))+'\n').encode()
CANDIDATE=('\n'.join(sorted(CONTRACT['preserved_symbols']))+'\n').encode()


class Boundaries(unittest.TestCase):
    def test_exact_reviewed_delta(self):
        result=abi.check('libXi.so.6',BASELINE,CANDIDATE,CONTRACT)
        self.assertEqual(result['required_original_exports'],88)
        self.assertEqual(set(result['removed_reviewed_linker_markers']),abi.MARKERS)

    def test_public_api_removal_rejected(self):
        with self.assertRaises(ValueError):
            abi.check('libXi.so.6',BASELINE,CANDIDATE.replace(b'XIQueryVersion\n',b''),CONTRACT)

    def test_exception_not_applied_to_other_library(self):
        with self.assertRaises(ValueError):abi.check('libXrender.so.1',b'_end\n',b'',CONTRACT)

    def test_changed_baseline_rejected(self):
        with self.assertRaises(ValueError):abi.check('libXi.so.6',BASELINE+b'Unexpected\n',CANDIDATE,CONTRACT)

    def test_broadened_contract_rejected(self):
        modified=dict(CONTRACT,allowed_removed_symbols=[*abi.MARKERS,'XIQueryVersion'])
        with self.assertRaises(ValueError):abi.check('libXi.so.6',BASELINE,CANDIDATE,modified)

    def test_other_library_preserves_all_exports(self):
        self.assertEqual(abi.check('libX11.so.6',b'XOpenDisplay\n',b'XOpenDisplay\nXNew\n',CONTRACT)['required_original_exports'],1)


if __name__=='__main__':unittest.main()
