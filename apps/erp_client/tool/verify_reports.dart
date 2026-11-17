// Synthetic connected report contracts; never connects to customer material.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/reports/data/erp_report_repository.dart';
import 'package:erp_client/features/reports/presentation/report_view_model.dart';

Future<void> main() async {
  final origin = Uri.parse(
    Platform.environment['ERP_URL'] ?? 'http://127.0.0.1:8081',
  );
  if (!{'127.0.0.1', 'localhost'}.contains(origin.host) ||
      origin.scheme != 'http' ||
      origin.port != 8081 ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      !{'', '/'}.contains(origin.path)) {
    throw StateError('Require the isolated native-test origin.');
  }
  final username = Platform.environment['ERP_USERNAME'];
  final password = Platform.environment['ERP_PASSWORD'];
  if (username == null || password == null) {
    throw StateError('Require synthetic verification credentials.');
  }
  final api = ErpApi(origin);
  var queued = 0;
  final results = <Map<String, Object?>>[];
  try {
    await api.login(username, password);
    final catalog = await api.nativeCatalog();
    if (catalog.site != 'native-test.localhost') {
      throw StateError('Refusing verification outside native-test.localhost.');
    }
    for (final company in ['ERP Native Verification', 'Meridian Trading']) {
      if ((await api.workspaceContext(company: company)).company != company) {
        throw StateError('Synthetic report company unavailable.');
      }
      for (final name in [
        'Sales Register',
        'Stock Balance',
        'Sales Order Analysis',
      ]) {
        final model = ReportViewModel(
          ErpReportRepository(api: api, company: company, name: name),
        );
        try {
          final definition = await model.definition;
          final fields = definition.schema.fields;
          if (fields.any((f) => f.name == 'from_date')) {
            model.values!['from_date'] = '2026-01-01';
          }
          if (fields.any((f) => f.name == 'to_date')) {
            model.values!['to_date'] = '2026-12-31';
          }
          model.changed();
          model.run();
          if (model.errors.isNotEmpty || model.result == null) {
            throw StateError(
              'Synthetic report defaults did not validate: $name',
            );
          }
          var applied = await model.result!;
          if (applied.report.pending) {
            // One explicit Generate action; subsequent polling only reads.
            await model.queue(applied.filters);
            queued++;
            applied = await model.result!;
            for (var i = 0; applied.report.pending && i < 30; i++) {
              await Future<void>.delayed(const Duration(seconds: 1));
              model.runFilters(applied.filters);
              applied = await model.result!;
            }
          }
          if (applied.report.pending ||
              name != 'Sales Order Analysis' &&
                  applied.report.columns.isEmpty) {
            throw StateError('Synthetic report did not produce columns: $name');
          }
          final report = applied.report;
          for (final entry in {
            'company': company,
            'from_date': '2026-01-01',
            'to_date': '2026-12-31',
          }.entries) {
            if (fields.any((field) => field.name == entry.key) &&
                applied.filters[entry.key] != entry.value) {
              throw StateError(
                'Connected report lost applied ${entry.key}: $name',
              );
            }
          }
          if (report.chart case final chart?) {
            if (chart.labels.isEmpty ||
                chart.series.any(
                  (series) => series.values.length != chart.labels.length,
                )) {
              throw StateError('Invalid connected chart projection.');
            }
          }
          if (definition.canExport && report.rows.isNotEmpty) {
            final csv = model.csv(applied);
            if (!csv.endsWith('\r\n')) throw StateError('CSV lost CRLF rows.');
            if (fields.any((field) => field.name == 'to_date')) {
              model.values!['to_date'] = '2031-12-31';
              model.changed();
              if (!model.filtersChanged(applied.filters) ||
                  model.csv(applied) != csv) {
                throw StateError('Draft filters changed the displayed export.');
              }
            }
          }
          final companyFields = fields.where(
            (f) =>
                f.name == 'company' &&
                f.type == 'Link' &&
                f.options == 'Company',
          );
          if (companyFields.isNotEmpty) {
            final links = await model.links(
              'Company',
              company,
              companyFields.first,
            );
            if (!links.any((row) => row['value'] == company)) {
              throw StateError('Synthetic company lookup failed.');
            }
          }
          results.add({
            'company': company,
            'report': name,
            'rows': report.rows.length,
            'columns': report.columns.length,
            'chart': report.chart != null,
            'appliedCompany': applied.filters['company'],
            'appliedFrom': applied.filters['from_date'],
            'appliedTo': applied.filters['to_date'],
          });
        } finally {
          model.dispose();
        }
      }
    }
    stdout.writeln(
      jsonEncode({
        'site': catalog.site,
        'reports': results,
        'createdBusinessRecords': 0,
        'explicitPreparedReportRequests': queued,
      }),
    );
    await api.signOut();
  } finally {
    api.close();
  }
}
