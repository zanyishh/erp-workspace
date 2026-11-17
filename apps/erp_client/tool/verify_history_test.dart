// Fresh synthetic History fixtures on native-test.localhost only. GPL-3.0.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/imported_history/data/erp_history_repository.dart';
import 'package:erp_client/features/imported_history/data/imported_record_pdf_service.dart';
import 'package:erp_client/features/imported_history/presentation/history_detail_view_model.dart';
import 'package:erp_client/features/imported_history/presentation/history_register_view_model.dart';
import 'package:erp_client/features/imported_history/presentation/original_production_view_model.dart';
import 'package:erp_client/features/imported_history/presentation/original_record_preview_view_model.dart';
import 'package:erp_client/imported_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  testWidgets('fresh synthetic History paging, source PDF and production', (
    t,
  ) async {
    final password = Platform.environment['ERP_PASSWORD'];
    final raw = Platform.environment['ERP_HISTORY_FIXTURE'];
    if (password == null || raw == null) {
      throw StateError('Require synthetic credentials and fixture.');
    }
    final fixture = jsonDecode(raw) as Map<String, dynamic>;
    final companies = (fixture['companies'] as List).cast<String>();
    if (fixture['site'] != 'native-test.localhost' ||
        companies.length != 4 ||
        companies.any((v) => !v.startsWith('Architecture History '))) {
      throw StateError('Refusing unrelated fixture material.');
    }
    final company = companies.first;
    final jobs = (fixture['jobs'] as List).cast<Map<String, dynamic>>();
    final api = ErpApi(Uri.parse('http://127.0.0.1:8081'));
    addTearDown(api.close);
    await t.runAsync(() async {
      await api.login('Administrator', password);
      expect((await api.nativeCatalog()).site, 'native-test.localhost');
      expect(
        (await api.workspaceContext(company: company)).canReadImportedHistory,
        isTrue,
      );
      final repository = ErpImportedHistoryRepository(
        api: api,
        company: company,
      );
      final register = HistoryRegisterViewModel(
        repository,
        initialFamily: 'job',
      );
      final production = OriginalProductionViewModel(repository);
      final detail = HistoryDetailViewModel(
        repository,
        name: jobs.first['name'] as String,
      );
      final preview = OriginalRecordPreviewViewModel(
        repository,
        name: jobs.first['name'] as String,
        render: renderOriginalRecordPdf,
      );
      try {
        await register.settled;
        expect(register.rows, hasLength(40));
        expect(register.rowCount, 41);
        expect(register.hasMore, isTrue);
        await register.nextPage();
        expect(register.start, 40);
        expect(register.rows, hasLength(1));
        expect(register.hasMore, isFalse);
        await register.search(jobs.first['reference'] as String);
        expect(register.start, 0);
        expect(register.rows.single['name'], jobs.first['name']);
        final record = await detail.result;
        expect(record.data['name'], jobs.first['name']);
        expect(record.data['record_printable'], isTrue);
        expect(
          (record.data['fields'] as List).any(
            (dynamic v) => v['value'] == '-0.1250',
          ),
          isTrue,
        );
        final pdf = await preview.result;
        expect(ascii.decode(pdf.bytes.take(5).toList()), '%PDF-');
        expect(
          pdf.filename,
          '${jobs.first['reference']} - Orders - Original source copy.pdf',
        );
        expect(preview.canUse(pdf), isTrue);
        await production.settled;
        expect(production.totals, {
          'source_record_count': 3,
          'quantity_kg': '1.1250',
          'recorded_count': '0.25',
          'missing_quantity_rows': 1,
          'missing_count_rows': 1,
        });
        await production.chooseGroup('machine');
        expect(production.rows, hasLength(2));
        final machine = production.rows.singleWhere(
          (v) => v['value'] == 'Machine A',
        );
        expect(machine['source_record_count'], 2);
        final drilled = await repository.records(
          'production',
          filters: Map<String, dynamic>.from(machine['filters'] as Map),
        );
        expect(drilled.rows, hasLength(2));
        final savedJob = jobs.first['name'] as String;
        final filtered = await repository.records(
          'production',
          filters: {'source_job': jobs.first['native']},
        );
        expect(filtered.rows, hasLength(2));
        expect(filtered.filterLabels['source_job'], jobs.first['reference']);
        final choices = await repository.options('production', 'source_job');
        expect(choices.data['rows'], hasLength(2));
        await register.chooseFamily('shared_cash');
        expect(register.rows.single['name'], fixture['cash']);
        expect(register.rows.single['original_date'], isNull);
        expect(register.rows.single['effective_date'], '2023-04-01');
        expect(register.rows.single['date_basis'], 'approved_opening');
        final other = ErpImportedHistoryRepository(
          api: api,
          company: companies[1],
        );
        final otherSummary = await other.summary();
        expect(otherSummary.families, isEmpty);
        expect(otherSummary.sharedAvailable, isTrue);
        final otherCash = await other.records('shared_cash');
        expect(otherCash.rows.single['name'], fixture['cash']);
        await expectLater(other.detail(savedJob), throwsA(isA<ErpException>()));
      } finally {
        register.dispose();
        production.dispose();
        detail.dispose();
        preview.dispose();
      }
    });

    Future<void> wait(Finder finder) async {
      for (var i = 0; i < 240; i++) {
        await t.pump(const Duration(milliseconds: 50));
        if (finder.evaluate().isNotEmpty) return;
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      fail('Connected History did not reach $finder');
    }

    await t.runAsync(() => api.workspaceContext(company: company));
    await t.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: ImportedHistoryScreen(
          api: api,
          company: company,
          initialFamily: 'job',
        ),
      ),
    );
    await wait(find.text('1–40 of 41'));
    await t.tap(find.text('Next'));
    await wait(find.text('41–41 of 41'));
    final last = find.textContaining('ARCH-').last;
    await t.ensureVisible(last);
    await t.tap(last);
    await wait(find.text('Print original record'));
    await t.tap(find.text('Print original record'));
    await wait(find.text('Export PDF'));
    expect(find.text('Original record preview'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.runAsync(api.signOut);
    api.close();
    await t.pump(const Duration(seconds: 30));
    stdout.writeln(
      jsonEncode({
        'site': fixture['site'],
        'company': company,
        'sourceRecords': 45,
        'registerPages': '40+1',
        'productionGroups': 2,
        'signedAndMissingTotals': 'passed',
        'sourceJobLabels': 'passed',
        'sharedCashIdentity': 'passed',
        'wrongCompanyRead': 'denied',
        'sourcePdfAndNavigation': 'passed',
        'businessMutationsDuringReads': 0,
      }),
    );
  }, timeout: const Timeout(Duration(minutes: 4)));
}
