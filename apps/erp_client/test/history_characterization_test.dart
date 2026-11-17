import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/imported_history.dart';
import 'package:erp_client/original_production_report.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081')) {
    access('B', 1);
    access('A', 1);
  }
  void access(String company, int version) => publishContext(
    WorkspaceContext.fromJson({
      'company': company,
      'companies': [
        {'name': 'A'},
        {'name': 'B'},
      ],
      'can_read_imported_history': true,
      'access_fingerprint': '$company-$version',
    }),
  );
  Completer<Map<String, dynamic>>? detail, summary, production;
  final detailReads = <(String, String)>[];
  final productionReads = <String>[];
  Map<String, dynamic> _detail(String company, String name) => {
    'version': 1,
    'company': company,
    'name': name,
    'family': 'job',
    'title': 'Original $company $name',
    'fields': [],
    'tables': [],
    'review_notes': [],
    'target_links': [],
    'printable': false,
  };
  Map<String, dynamic> _summary(String company) => {
    'version': 1,
    'company': company,
    'families': [
      {'key': 'job', 'label': 'Jobs', 'count': 1},
    ],
    'shared_cash_available': false,
  };
  Map<String, dynamic> _production(String company, String group, int start) => {
    'version': 1,
    'company': company,
    'family': 'production',
    'group_by': group,
    'start': start,
    'page_length': 100,
    'row_count': 1,
    'has_more': false,
    'available_filters': [],
    'totals': _totals,
    'rows': [
      {
        'value': '$company original',
        'label': '$company original',
        'drillable': false,
        ..._totals,
      },
    ],
  };
  Map<String, dynamic> get _totals => {
    'source_record_count': 1,
    'quantity_kg': '-0.125',
    'recorded_count': '0.25',
    'missing_quantity_rows': 0,
    'missing_count_rows': 0,
  };
  @override
  Future<Map<String, dynamic>> importedHistoryDetail(
    String company,
    String name,
  ) {
    detailReads.add((company, name));
    return detail?.future ?? Future.value(_detail(company, name));
  }

  @override
  Future<Map<String, dynamic>> importedHistorySummary(String company) =>
      company == 'A' && summary != null
      ? summary!.future
      : Future.value(_summary(company));
  @override
  Future<Map<String, dynamic>> importedHistoryRecords(
    String company,
    String family, {
    String query = '',
    int start = 0,
    int pageLength = 40,
    Map<String, dynamic> filters = const {},
  }) async => {
    'version': 1,
    'company': company,
    'family': family,
    'start': start,
    'page_length': pageLength,
    'has_more': false,
    'row_count': 1,
    'available_filters': [],
    'rows': [
      {
        'name': '$company-1',
        'family': family,
        'title': 'Visible history $company',
        'summary': 'Synthetic',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> originalProductionSummary(
    String company, {
    String groupBy = 'original_date',
    Map<String, dynamic> filters = const {},
    int start = 0,
    int pageLength = 100,
  }) {
    productionReads.add(company);
    return company == 'A' && production != null
        ? production!.future
        : Future.value(_production(company, groupBy, start));
  }
}

void main() {
  for (final changed in ['company', 'record']) {
    testWidgets(
      'original detail replaces its pending read when $changed changes',
      (t) async {
        final api = _Api(), old = Completer<Map<String, dynamic>>();
        api.detail = old;
        addTearDown(api.close);
        Widget view(String company, String name) => MaterialApp(
          home: ImportedHistoryDetailScreen(
            api: api,
            company: company,
            name: name,
          ),
        );
        await t.pumpWidget(view('A', 'old'));
        await t.pump();
        api.detail = null;
        final company = changed == 'company' ? 'B' : 'A';
        final name = changed == 'record' ? 'new' : 'old';
        await t.pumpWidget(view(company, name));
        old.complete(api._detail('A', 'old'));
        await t.pumpAndSettle();
        expect(api.detailReads, contains((company, name)));
        expect(find.text('Original $company $name'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final screen in ['register', 'production']) {
    testWidgets(
      'an old original $screen refresh cannot hide a replacement company',
      (t) async {
        final api = _Api();
        addTearDown(api.close);
        Widget view(String company) => MaterialApp(
          home: screen == 'register'
              ? ImportedHistoryScreen(api: api, company: company)
              : OriginalProductionReport(api: api, company: company),
        );
        await t.pumpWidget(view('A'));
        await t.pumpAndSettle();
        final old = Completer<Map<String, dynamic>>();
        if (screen == 'register') {
          api.summary = old;
        } else {
          api.production = old;
        }
        api.access('A', 2);
        if (screen == 'production') {
          // Publishing A's new permissions clears the whole client cache.
          // The replacement company must have its freshly authorized context.
          api.access('B', 2);
          expect(api.contextFor('B')?.canReadImportedHistory, isTrue);
        }
        await t.pump();
        await t.pumpWidget(view('B'));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 10));
        }
        try {
          if (screen == 'production') {
            expect(api.productionReads, contains('B'));
          }
          expect(
            find.text(
              screen == 'register' ? 'Visible history B' : 'B original',
            ),
            findsOneWidget,
          );
        } finally {
          old.complete(
            screen == 'register'
                ? api._summary('A')
                : api._production('A', 'original_date', 0),
          );
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);
      },
    );
  }
}
