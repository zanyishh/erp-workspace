import 'dart:convert';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _workspace = WorkspaceContext.fromJson({
  'company': 'Synthetic Mill',
  'knitting_enabled': true,
  'capabilities': ['jobs', 'lifecycle', 'financial_read'],
});

Map<String, dynamic> _importedJob(String version) => {
  'name': 'SYNTHETIC-IMPORTED-JOB',
  'modified': version,
  'source_record': 'SYNTHETIC-ORIGINAL',
  'programme': [
    {
      'id': 'source-fabric-7-size-9',
      'source_fabric_id': '7',
      'source_size_id': '9',
      'fabric': 'Synthetic original fabric',
      'target_kg': '0.000',
      'gsm': ['0'],
      'll': [],
      'dia': '',
      'dia_display': '',
      'dia_basis': 'unrecorded',
      'excess_percent': '0',
    },
  ],
};

void main() {
  KnitAction action() =>
      knitActions.where((a) => a.id == 'revise_rate').firstOrNull ??
      knitActions.firstWhere((a) => a.id == 'revise_job');

  test(
    'commercial revision has a distinct action identity and permission gates',
    () {
      final revisions = knitActions.where((a) => a.id == 'revise_rate');
      expect(revisions, hasLength(1));
      expect(
        knitActions.firstWhere((a) => a.id == 'revise_job').title,
        'Revise programme',
      );
      expect(revisions.single.availableIn(_workspace), isTrue);
      for (final capabilities in [
        ['jobs', 'lifecycle'],
        ['jobs', 'financial_read'],
      ]) {
        expect(
          revisions.single.availableIn(
            WorkspaceContext.fromJson({
              'company': 'Synthetic Mill',
              'knitting_enabled': true,
              'capabilities': capabilities,
            }),
          ),
          isFalse,
        );
      }
      expect(
        revisions.single.availableIn(
          WorkspaceContext.fromJson({
            'company': 'Synthetic Mill',
            'knitting_enabled': true,
            'capabilities': ['jobs', 'lifecycle', 'financial_read'],
            'unavailable_knitting_actions': ['revise_job'],
          }),
        ),
        isFalse,
      );
    },
  );

  for (final stale in [false, true]) {
    testWidgets('rate-only review preserves imported programme; stale=$stale', (
      tester,
    ) async {
      final api = _RevisionApi()..stale = stale;
      addTearDown(api.close);
      final job = _importedJob('v1');
      final before = jsonEncode(job);
      await tester.pumpWidget(
        MaterialApp(
          home: KnittingCommandForm(
            api: api,
            workspace: _workspace,
            action: action(),
            job: job,
            initial: {
              'reason': 'Synthetic new commercial agreement',
              'rate': '125.50',
              // A source projection or previous form seed must never enter this command.
              'programme': job['programme'],
              'pricing': {'source-fabric-7-size-9': '900'},
              'refresh_rates': true,
              'dia_display': 'read companion',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fabric programme'), findsNothing);
      expect(
        find.textContaining(
          'Existing programme and earlier delivery prices stay unchanged.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Review entry'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm & post'), findsOneWidget);
      expect(api.posts, isEmpty);
      await tester.tap(find.text('Confirm & post'));
      await tester.pumpAndSettle();
      if (stale) {
        expect(find.text('Reload current sources'), findsOneWidget);
        await tester.tap(find.text('Reload current sources'));
        await tester.pumpAndSettle();
        // The old rate must be reconsidered against the newly loaded version.
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Rate per kg'),
              )
              .initialValue,
          isEmpty,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Rate per kg'),
          '126.00',
        );
        await tester.tap(find.text('Review entry'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm & post'));
        await tester.pumpAndSettle();
      }
      expect(api.posts.last, {
        'action': 'revise_job',
        'modified': stale ? 'v2' : 'v1',
        'values': {
          'job': job['name'],
          'reason': 'Synthetic new commercial agreement',
          'rate': stale ? '126.00' : '125.50',
        },
      });
      expect(jsonEncode(job), before);
      expect(tester.takeException(), isNull);
    });
  }
}

class _RevisionApi extends ErpApi {
  _RevisionApi() : super(Uri.parse('http://localhost:8081'));
  bool stale = false;
  final posts = <Map<String, dynamic>>[];

  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
    String? before,
    String? asOf,
  }) async => KnittingSnapshot(company, {
    'jobs': [_importedJob('v2')],
  });

  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posts.add({'action': action, 'values': values, 'modified': modified});
    if (stale && posts.length == 1) {
      throw const ErpException(
        'Synthetic source changed.',
        staleDocument: true,
      );
    }
    return {'event': 'SYNTHETIC-REVISION', 'data': {}};
  }
}
