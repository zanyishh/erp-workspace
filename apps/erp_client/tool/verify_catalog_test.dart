// Fresh synthetic Catalog fixtures on native-test.localhost only. GPL-3.0.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/catalog/data/erp_catalog_repository.dart';
import 'package:erp_client/features/catalog/presentation/native_tree_view_model.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  testWidgets('fresh synthetic hierarchy and CSV import preserve contracts', (
    t,
  ) async {
    final password = Platform.environment['ERP_PASSWORD'];
    if (password == null) throw StateError('Require synthetic credentials.');
    final admin = ErpApi(Uri.parse('http://127.0.0.1:8081'));
    final owner = ErpApi(Uri.parse('http://127.0.0.1:8081'));
    addTearDown(admin.close);
    addTearDown(owner.close);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final company = 'Architecture Catalog $stamp';
    final username = 'architecture-catalog-$stamp@example.invalid';
    final secret = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );

    await t.runAsync(() async {
      await admin.login('Administrator', password);
      final catalog = await admin.nativeCatalog();
      if (catalog.site != 'native-test.localhost') {
        throw StateError('Refusing mutations outside native-test.localhost.');
      }
      const treeCompany = 'ERP Native Verification';
      final context = await admin.workspaceContext(company: treeCompany);
      expect(context.company, treeCompany);
      final type = catalog.types.singleWhere((v) => v.name == 'Item Group');
      final schema = await admin.nativeSchema('Item Group');
      final draft = await admin.nativeDocument(
        'Item Group',
        company: treeCompany,
        treeParent: 'All Item Groups',
      );
      final original = 'Architecture Catalog Group $stamp';
      final renamed = '$original renamed';
      final values = draft.editCopy()
        ..['item_group_name'] = original
        ..['parent_item_group'] = 'All Item Groups'
        ..['is_group'] = 0;
      await admin.saveNative(schema, values, company: treeCompany);
      final model = NativeTreeViewModel(
        ErpCatalogRepository(api: admin, company: treeCompany),
        type: type,
        company: treeCompany,
        parent: 'All Item Groups',
      );
      try {
        var page = await model.result;
        for (
          var i = 0;
          !page.nodes.any((v) => v.name == original) && page.hasMore && i < 100;
          i++
        ) {
          page = await model.nextPage();
        }
        final node = page.nodes.singleWhere((v) => v.name == original);
        final intent = model.prepareChange(node, 'rename');
        expect(intent, isNotNull);
        expect(await model.change(intent!, newName: renamed), isTrue);
        await model.result;
        final saved = await admin.nativeDocument(
          'Item Group',
          name: renamed,
          company: treeCompany,
        );
        expect(saved.data['name'], renamed);
      } finally {
        model.dispose();
      }
      // A separate guest client provisions only this newly named test company.
      await owner.registerOwner(
        fullName: 'Architecture Catalog Owner',
        email: username,
        password: secret,
        company: company,
        industry: 'general',
      );
      await owner.login(username, secret);
      expect(
        (await owner.nativeCatalog(company: company)).site,
        'native-test.localhost',
      );
      expect((await owner.workspaceContext(company: company)).company, company);
    });

    final catalog = (await t.runAsync(
      () => owner.nativeCatalog(company: company),
    ))!;
    final customer = catalog.types.singleWhere((v) => v.name == 'Customer');
    expect(customer.canImport, isTrue);
    final name = 'Architecture imported shop $stamp';
    final directory = Directory.systemTemp.createTempSync('erp-catalog-check-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/customers.csv')
      ..writeAsStringSync(
        'customer_name,customer_type,customer_group,territory\r\n'
        '$name,Company,Commercial,India\r\n',
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
    Future<void> wait(Finder finder) async {
      for (var i = 0; i < 240; i++) {
        await t.pump(const Duration(milliseconds: 50));
        if (finder.evaluate().isNotEmpty) return;
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 45)),
        );
      }
      fail('Connected Catalog did not reach $finder');
    }

    Future<void> tap(Finder finder) async {
      await wait(finder);
      await t.ensureVisible(finder.first);
      await t.tap(finder.first);
    }

    await t.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: NativeRecordScreen(api: owner, company: company, type: customer),
      ),
    );
    await tap(find.byTooltip('Import CSV'));
    await tap(find.text('Choose CSV'));
    await wait(find.text(name));
    expect(
      await t.runAsync(
        () => owner.nativeRecords('Customer', query: name, company: company),
      ),
      isEmpty,
    );
    await tap(find.text('Import 1 record'));
    await wait(find.text('Imported 1 record.'));
    await tap(find.text('Choose another CSV'));
    await wait(find.text('Already imported · 1 record.'));
    final records = (await t.runAsync(
      () => owner.nativeRecords('Customer', query: name, company: company),
    ))!;
    expect(records, hasLength(1));
    final saved = (await t.runAsync(
      () => owner.nativeDocument(
        'Customer',
        name: records.single['name'] as String,
        company: company,
      ),
    ))!;
    expect(saved.data['customer_name'], name);
    await t.pumpWidget(const SizedBox.shrink());
    await t.runAsync(() async {
      await owner.signOut();
      await admin.signOut();
    });
    owner.close();
    admin.close();
    await t.pump(const Duration(seconds: 30));
    stdout.writeln(
      jsonEncode({
        'site': catalog.site,
        'company': company,
        'createdSyntheticCustomers': 1,
        'createdSyntheticItemGroups': 1,
        'hierarchyRename': 'passed',
        'previewConfirmAndDuplicateReceipt': 'passed',
      }),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
