// Rehearse a real CSV import through the Flutter record list on native-test.localhost.
// Use PILOT_DIR from the isolated provision-owner trading fixture.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _LocalBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _LocalBinding();
  testWidgets(
    'owner previews, imports and reopens a customer from the record list',
    (t) async {
      final fixture = File(
        '${Platform.environment['PILOT_DIR']}/erp-fixture.json',
      );
      final fields = jsonDecode(fixture.readAsStringSync()) as Map;
      final username = fields['username'] as String,
          company = fields['company'] as String;
      expect(username, endsWith('@example.invalid'));
      expect(company, startsWith('Pilot Trade '));
      final api = ErpApi(Uri.parse('http://localhost:8081'));
      addTearDown(api.close);
      await t.runAsync(() => api.login(username, fields['password'] as String));
      final catalog = (await t.runAsync(
        () => api.nativeCatalog(company: company),
      ))!;
      expect(catalog.site, 'native-test.localhost');
      final customer = catalog.types.singleWhere((v) => v.name == 'Customer');
      expect(customer.canImport, isTrue);
      final row = (await t.runAsync(
        () => api.nativeDocument(
          'Customer',
          name: fields['customer'] as String,
          company: company,
        ),
      ))!.data;
      final group = row['customer_group'], territory = row['territory'];
      final name = 'Imported shop ${DateTime.now().microsecondsSinceEpoch}';
      final dir = Directory.systemTemp.createTempSync('erp-local-import');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/customers.csv')
        ..writeAsStringSync(
          'customer_name,customer_type,customer_group,territory\r\n$name,Company,$group,$territory\r\n',
        );
      const picker = MethodChannel('plugins.flutter.io/file_selector');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        (call) async => call.method == 'openFile' ? [file.path] : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      Future<void> wait(Finder view) async {
        for (var i = 0; i < 220; i++) {
          await t.pump(const Duration(milliseconds: 50));
          if (view.evaluate().isNotEmpty) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 45)),
          );
        }
        fail('The import screen did not reach $view');
      }

      Future<void> tap(Finder view) async {
        await wait(view);
        await t.ensureVisible(view.first);
        await t.tap(view.first);
      }

      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: NativeRecordScreen(api: api, company: company, type: customer),
        ),
      );
      await tap(find.byTooltip('Import CSV'));
      await tap(find.text('Choose CSV'));
      await wait(find.text(name));
      expect(
        await t.runAsync(
          () => api.nativeRecords('Customer', query: name, company: company),
        ),
        isEmpty,
      );
      await tap(find.text('Import 1 record'));
      await wait(find.text('Imported 1 record.'));
      await tap(find.text('Choose another CSV'));
      await wait(find.text('Already imported · 1 record.'));
      final records = (await t.runAsync(
        () => api.nativeRecords('Customer', query: name, company: company),
      ))!;
      expect(records.length, 1);
      final saved = await t.runAsync(
        () => api.nativeDocument(
          'Customer',
          name: records.single['name'] as String,
          company: company,
        ),
      );
      expect(saved!.data['customer_name'], name);
      await t.runAsync(api.signOut);
      api.close();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 30));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
