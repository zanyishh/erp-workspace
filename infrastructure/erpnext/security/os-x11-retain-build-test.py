#!/usr/bin/env python3
"""Retention boundaries for ordinary compiled-tree fixtures."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('retain_x11',HERE/'os-x11-retain-build.py')
retain=importlib.util.module_from_spec(spec);spec.loader.exec_module(retain)


class RetentionBoundaries(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.source=Path(self.folder.name)/'source';self.source.mkdir()
        (self.source/'ordinary').write_text('test')

    def test_internal_link_and_canonical_parent(self):
        (self.source/'alias').symlink_to('ordinary')
        paths,size=retain.inventory(self.source)
        self.assertEqual(size,4);self.assertEqual(len(paths),3)

    def test_external_link_rejected(self):
        (self.source/'external').symlink_to('../unavailable')
        with self.assertRaises((ValueError,FileNotFoundError)):retain.inventory(self.source)

    def test_byte_budget_rejected(self):
        with patch.object(retain,'LIMIT',3),self.assertRaises(ValueError):retain.inventory(self.source)

    def test_outside_owned_hook_rejected(self):
        with self.assertRaises(ValueError):retain.main()


if __name__=='__main__':unittest.main()
