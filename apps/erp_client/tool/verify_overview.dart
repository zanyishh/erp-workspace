// Read-only connected contract check for the isolated synthetic native-test site.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/features/overview/data/erp_overview_repository.dart';
import 'package:erp_client/features/overview/data/module_record_repository.dart';
import 'package:erp_client/features/overview/presentation/module_browser_view_model.dart';
import 'package:erp_client/features/overview/presentation/overview_view_model.dart';
import 'package:erp_client/features/overview/presentation/sales_chart_view_model.dart';

Future<void> main() async {
  final origin = Uri.parse(
    Platform.environment['ERP_URL'] ?? 'http://127.0.0.1:8081',
  );
  if (!{'localhost', '127.0.0.1'}.contains(origin.host) ||
      origin.scheme != 'http' ||
      origin.port != 8081 ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      !{'', '/'}.contains(origin.path)) {
    throw StateError('Require the isolated local test origin.');
  }
  final username = Platform.environment['ERP_USERNAME'];
  final password = Platform.environment['ERP_PASSWORD'];
  if (username == null || password == null) {
    throw StateError('Require synthetic verification credentials.');
  }
  final api = ErpApi(origin);
  try {
    await api.login(username, password);
    final catalog = await api.nativeCatalog();
    if (catalog.site != 'native-test.localhost') {
      throw StateError('Refusing to verify outside native-test.localhost.');
    }
    final results = <Map<String, Object?>>[];
    for (final company in ['ERP Native Verification', 'Meridian Trading']) {
      final context = await api.workspaceContext(company: company);
      if (context.company != company) {
        throw StateError('Synthetic company unavailable.');
      }
      final repository = ErpOverviewRepository(api: api, company: company);
      final model = OverviewViewModel(repository, period: ReportingPeriod.year);
      ModuleBrowserViewModel? browser;
      try {
        final data = await model.result;
        if (data.company != company ||
            data.currency.isEmpty ||
            data.count(ErpModule.stock) == null) {
          throw StateError('Invalid synthetic overview.');
        }
        browser = ModuleBrowserViewModel(
          CallbackModuleRecordRepository(
            (query, start) =>
                model.records(ErpModule.stock, query: query, start: start),
          ),
          company: company,
          currency: data.currency,
          module: ErpModule.stock,
          scope: repository.scope,
        );
        final first = await browser.result;
        if (first.length == 50) {
          await browser.nextPage();
          await browser.previousPage();
        }
        final searched = await browser.reload(
          query:
              'architecture-no-match-${DateTime.now().microsecondsSinceEpoch}',
        );
        if (searched.isNotEmpty || browser.start != 0) {
          throw StateError(
            'The connected module search did not reset/filter its page.',
          );
        }
        if (data.invoicesAvailable) {
          await model.records(ErpModule.accounts, unpaidOnly: true);
        }
        final chart = SalesChartViewModel(
          data,
          range: ReportingPeriod.year.range(DateTime.now()),
        );
        if (chart.buckets.isNotEmpty &&
            (chart.selected < 0 || chart.selected >= chart.buckets.length)) {
          throw StateError('The connected chart has no valid selected bucket.');
        }
        results.add({
          'company': company,
          'currency': data.currency,
          'firstStockPage': first.length,
          'snapshotAndSearch': 'passed',
        });
      } finally {
        browser?.dispose();
        model.dispose();
      }
    }
    stdout.writeln(
      jsonEncode({
        'site': catalog.site,
        'companies': results,
        'createdBusinessRecords': 0,
      }),
    );
  } finally {
    try {
      await api.signOut();
    } finally {
      api.close();
    }
  }
}
