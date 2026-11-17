import 'dart:async';

import 'package:erp_client/document_editor.dart';
import 'package:erp_client/document_recovery.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecoveryApi extends ErpApi {
  RecoveryApi() : super(Uri.parse('http://localhost:8081'));
  int writes = 0;
  String? prepared, sent;
  String state = 'completed';
  bool reject = false;
  bool beginFails = false;
  bool atomicSupport = true, existing = false;
  Completer<void>? preparation;
  final acknowledgements = <String>[];
  @override
  bool supportsOperationRecovery(String company) => true;
  Map<String, dynamic> result() => {
    'doc': {
      'doctype': 'Example',
      'name': 'EX-1',
      'company': 'Demo',
      'description': 'Saved description',
    },
    'permissions': {'write': 1},
  };
  @override
  Future<NativeSchema> nativeSchema(String doctype) async =>
      NativeSchema.fromJson({
        'doctype': doctype,
        'operation_recovery_supported': atomicSupport,
        'fields': [
          {
            'fieldname': 'description',
            'label': 'Description',
            'fieldtype': 'Data',
          },
        ],
      });
  @override
  Future<NativeDocument> nativeDocument(
    String doctype, {
    String? name,
    String? company,
    String? treeParent,
  }) async => NativeDocument.fromJson({
    'doc': existing
        ? {
            'doctype': doctype,
            'name': 'EX-1',
            'company': 'Demo',
            'modified': 'v1',
            'description': writes > 0 ? 'Saved description' : '',
          }
        : {'doctype': doctype, 'company': 'Demo', '__islocal': 1},
    'permissions': {'create': 1, 'write': 1},
  });
  @override
  Future<Map<String, dynamic>> beginOperation(
    String company,
    String kind,
    String requestId, {
    String? doctype,
    String? name,
    String? action,
  }) async {
    if (beginFails) throw const ErpException('Preparation unavailable');
    prepared = requestId;
    await preparation?.future;
    return {'state': 'prepared', 'request_id': requestId};
  }

  @override
  Future<NativeDocument> saveNative(
    NativeSchema schema,
    Map<String, dynamic> document, {
    String action = 'Save',
    String? requestId,
    String? company,
  }) async {
    writes++;
    sent = requestId;
    if (reject) {
      throw const ErpException(
        'Description rejected',
        validationRejected: true,
      );
    }
    throw const ErpException('Response lost');
  }

  @override
  Future<Map<String, dynamic>> operationStatus(
    String company,
    String requestId,
  ) async => {
    'request_id': requestId,
    'state': state,
    if (state == 'completed') 'result': result(),
  };
  @override
  Future<Map<String, dynamic>> closeOperation(
    String company,
    String requestId,
  ) async => {'request_id': requestId, 'state': 'closed'};
  @override
  Future<void> acknowledgeOperation(String company, String requestId) async {
    acknowledgements.add(requestId);
  }
}

Future<void> open(WidgetTester tester, RecoveryApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DocumentEditor(api: api, doctype: 'Example', company: 'Demo'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Description'),
    'Saved description',
  );
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'a response arriving after changed access keeps its unresolved reference',
    () async {
      final api = RecoveryApi();
      addTearDown(api.close);
      final response = Completer<NativeDocument>();
      final attempted = Completer<void>();
      final operation = DocumentOperation(
        api,
        'Demo',
        'native_save',
        'Example',
        null,
        'Save',
      );
      final result = operation.perform((_) {
        attempted.complete();
        return response.future;
      });
      await attempted.future;
      api.accessRevision++;
      response.complete(NativeDocument.fromJson(api.result()));
      await expectLater(result, throwsA(isA<DocumentWriteUncertain>()));
      expect(operation.confirmed, isNull);
    },
  );

  testWidgets('company round trip during preparation prevents the old write', (
    tester,
  ) async {
    final api = RecoveryApi()..preparation = Completer<void>();
    addTearDown(api.close);
    var company = 'Demo';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return DocumentEditor(
              api: api,
              doctype: 'Example',
              company: company,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Saved description',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    update(() => company = 'Other');
    await tester.pumpAndSettle();
    update(() => company = 'Demo');
    await tester.pumpAndSettle();
    api.preparation!.complete();
    await tester.pumpAndSettle();
    expect(api.writes, 0);
  });

  testWidgets(
    'explicit non-atomic documents use legacy save and inspect unknown outcomes before editing',
    (tester) async {
      final api = RecoveryApi()
        ..atomicSupport = false
        ..existing = true;
      addTearDown(api.close);
      await open(tester, api);
      expect(api.prepared, isNull);
      expect(api.sent, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.text('Check current record'));
      await tester.pumpAndSettle();
      expect(api.writes, 1);
      expect(find.text('Saved description'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
    },
  );

  testWidgets(
    'lost save response reconciles original request without duplicate write',
    (tester) async {
      final api = RecoveryApi();
      addTearDown(api.close);
      await open(tester, api);
      expect(api.sent, api.prepared);
      expect(api.sent, isNotNull);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.text('Check outcome'));
      await tester.pumpAndSettle();
      expect(find.text('EX-1'), findsOneWidget);
      expect(api.writes, 1);
      expect(api.acknowledgements, [api.sent]);
    },
  );
  testWidgets(
    'prepared uncertainty stays locked until explicit close seals it',
    (tester) async {
      final api = RecoveryApi()..state = 'prepared';
      addTearDown(api.close);
      await open(tester, api);
      await tester.tap(find.text('Check outcome'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.text('Close unposted attempt'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(find.text('Saved description'), findsOneWidget);
      expect(api.writes, 1);
    },
  );
  testWidgets(
    'confirmed rejection retains editable input and never reports success',
    (tester) async {
      final api = RecoveryApi()..reject = true;
      addTearDown(api.close);
      await open(tester, api);
      expect(find.text('Description rejected'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(find.text('Saved description'), findsOneWidget);
      expect(find.text('Saved successfully'), findsNothing);
    },
  );
  testWidgets('failed preparation never sends the write', (tester) async {
    final api = RecoveryApi()..beginFails = true;
    addTearDown(api.close);
    await open(tester, api);
    expect(api.writes, 0);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(find.text('Saved description'), findsOneWidget);
  });
}
