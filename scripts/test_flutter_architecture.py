"""Regression fixtures for Flutter architectural dependency linting. GPL-3.0."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CHECKER = Path(__file__).with_name('check_flutter_architecture.py')


class FlutterArchitectureTests(unittest.TestCase):
    def check(self, files, legacy=None, cycles=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, source in files.items():
                target = root / 'lib' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(source)
            baseline = root / 'baseline.json'
            baseline.write_text(json.dumps({
                'files': [{'path': 'lib/' + name, 'directives': directives}
                          for name, directives in (legacy or {}).items()],
                'graph': {'cycles': [['lib/' + n for n in c] for c in (cycles or [])]},
            }))
            return subprocess.run([sys.executable, str(CHECKER), '--root', str(root),
                                   '--baseline', str(baseline)], capture_output=True, text=True)

    def test_valid_mvvm_and_constructor_composition_pass(self):
        result = self.check({
            'app/composition.dart': "import '../features/tasks/presentation/task_view.dart';",
            'features/tasks/presentation/task_view.dart': "import 'task_view_model.dart'; import 'package:flutter/material.dart';",
            'features/tasks/presentation/task_view_model.dart': "import '../data/task_repository.dart';",
            'features/tasks/data/task_repository.dart': "import '../models/task.dart';",
            'features/tasks/data/erp_task_repository.dart': "import '../../../core/services/erp_api.dart'; import 'task_repository.dart';",
            'features/tasks/models/task.dart': 'class Task {}',
            'core/services/erp_api.dart': "import 'dart:io';",
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_forbidden_edges_are_reported(self):
        for source, target in [
            ('features/tasks/presentation/task_view.dart', 'core/services/api.dart'),
            ('features/tasks/data/task_repository.dart', 'features/tasks/presentation/task_view.dart'),
            ('features/tasks/presentation/task_view_model.dart', 'features/tasks/presentation/task_view.dart'),
            ('features/tasks/presentation/task_view_model.dart', 'features/tasks/data/erp_task_repository.dart'),
            ('features/tasks/data/task_repository.dart', 'features/team/data/team_repository.dart'),
            ('core/models/value.dart', 'features/tasks/models/task.dart'),
        ]:
            with self.subTest(source=source, target=target):
                result = self.check({source: f"import 'package:erp_client/{target}';", target: ''})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('forbidden dependency', result.stdout)

    def test_widget_and_io_imports_cannot_enter_view_models(self):
        for uri in ['package:flutter/material.dart', 'dart:io', 'dart:ui', 'package:file_selector/file_selector.dart']:
            result = self.check({'features/tasks/presentation/task_view_model.dart': f"import '{uri}';"})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('forbidden dependency', result.stdout)

    def test_view_models_can_use_erp_named_core_value_models(self):
        result = self.check({
            'features/tasks/presentation/task_view_model.dart': "import '../../../core/models/erp_exception.dart';",
            'core/models/erp_exception.dart': 'class ErpException {}',
        })
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_exports_and_conditional_imports_cannot_hide_service_access(self):
        for directive in [
            "export '../../../core/services/api.dart';",
            "import 'task.dart' if (dart.library.io) '../../../core/services/api.dart';",
        ]:
            result = self.check({'features/tasks/presentation/task_view.dart': directive,
                                 'features/tasks/presentation/task.dart': '', 'core/services/api.dart': ''})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('forbidden dependency', result.stdout)

    def test_new_cycle_is_rejected(self):
        result = self.check({'features/tasks/models/a.dart': "import 'b.dart';",
                             'features/tasks/models/b.dart': "import 'a.dart';"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('dependency cycle', result.stdout)

    def test_library_metadata_cannot_disable_checks(self):
        result = self.check({'features/tasks/presentation/task_view_model.dart':
                             "@Deprecated('old') library; import 'package:flutter/widgets.dart'; class Model {}"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('forbidden dependency', result.stdout)

    def test_external_facades_cannot_hide_widget_dependencies(self):
        result = self.check({'widgets.dart': "export 'package:flutter/widgets.dart';",
                             'features/tasks/presentation/task_view_model.dart': "import '../../../widgets.dart';"},
                            {'widgets.dart': []})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('forbidden dependency', result.stdout)

    def test_services_allow_io_but_cannot_depend_on_widgets(self):
        for uri in ['package:flutter/material.dart', 'package:flutter/widgets.dart', 'dart:ui']:
            result = self.check({'core/services/api.dart': f"import '{uri}';"})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('forbidden dependency', result.stdout)

    def test_only_invoice_logo_decoder_may_use_the_platform_image_engine(self):
        path = 'features/invoices/data/invoice_logo_service.dart'
        result = self.check({path: "import 'dart:ui' as ui;"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for uri in ['package:flutter/material.dart', 'package:flutter/widgets.dart']:
            result = self.check({path: f"import '{uri}';"})
            self.assertNotEqual(result.returncode, 0)
        for caller in ['features/invoices/presentation/invoice_view.dart',
                       'features/invoices/presentation/invoice_view_model.dart']:
            result = self.check({path: "import 'dart:ui' as ui;",
                                 caller: "import '../data/invoice_logo_service.dart';"})
            self.assertNotEqual(result.returncode, 0)

    def test_conditional_values_are_not_uris_and_export_combinators_are_supported(self):
        result = self.check({
            'model.dart': "export 'features/tasks/models/task.dart' show Task;",
            'features/tasks/models/task.dart': '',
            'features/tasks/models/other.dart': '',
            'features/tasks/presentation/task_view_model.dart':
                "import '../../../model.dart' if (dart.library.io == 'true') '../models/other.dart';",
        }, {'model.dart': []})
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_unknown_layer_and_missing_local_target_are_rejected(self):
        for files in [{'misc.dart': 'class Misc {}'},
                      {'features/tasks/other/a.dart': ''},
                      {'features/tasks/models/task.dart': "import 'missing.dart';"}]:
            result = self.check(files)
            self.assertNotEqual(result.returncode, 0)

    def test_legacy_edges_are_frozen_but_can_shrink(self):
        legacy = {'old.dart': ["import 'service.dart';"], 'service.dart': []}
        for source in ["import 'service.dart';", '']:
            result = self.check({'old.dart': source, 'service.dart': ''}, legacy)
            self.assertEqual(result.returncode, 0, result.stdout)
        result = self.check({'old.dart': "import 'new.dart';", 'service.dart': '', 'new.dart': ''}, legacy)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('new legacy dependency', result.stdout)

    def test_facade_cannot_bypass_layer_rules(self):
        result = self.check({
            'api.dart': "export 'core/services/api.dart';",
            'core/services/api.dart': '',
            'features/tasks/presentation/task_view.dart': "import '../../../api.dart';",
        }, {'api.dart': []})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('forbidden dependency', result.stdout)

    def test_comments_and_string_contents_are_not_imports(self):
        result = self.check({'features/tasks/models/task.dart': '''
// import 'missing.dart';
/* nested /* import 'x.dart'; */ comment */
const note = "import 'missing.dart';";
const text = r"""export 'missing.dart';""";
class Task {}
'''})
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_import_like_identifiers_in_bodies_are_not_directives(self):
        result = self.check({'features/tasks/models/task.dart': "class Task { void export() { print('Amount'); } }"})
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_interpolated_strings_are_not_directives(self):
        result = self.check({'features/tasks/models/task.dart': """
const label = 'Total: ${value ?? 'none'}';
const nested = '${rows.map((r) => '${r['name']}').join(',')}';
const csv = '"${text.replaceAll('"', '""')}"';
"""})
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_part_ownership_does_not_create_a_false_cycle(self):
        result = self.check({'features/tasks/models/a.dart': "part 'b.dart';",
                             'features/tasks/models/b.dart': "part of 'a.dart';"})
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_legacy_cycle_may_not_expand(self):
        legacy = {'a.dart': ["import 'b.dart';"], 'b.dart': ["import 'a.dart';"]}
        result = self.check({'a.dart': "import 'b.dart';", 'b.dart': "import 'a.dart';"},
                            legacy, [['a.dart', 'b.dart']])
        self.assertEqual(result.returncode, 0, result.stdout)


if __name__ == '__main__':
    unittest.main()
