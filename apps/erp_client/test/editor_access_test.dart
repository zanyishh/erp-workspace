import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/workspace_context.dart';

class AccessEditorApi extends ErpApi {
  AccessEditorApi() : super(Uri.parse('http://localhost:8081'));
  bool finance = true;
  String reference = 'Before';
  bool available = true;
  int mapped = 0;
  bool conflict = false;
  @override
  Future<NativeSchema> nativeSchema(
    String type,
  ) async => NativeSchema.fromJson({
    'doctype': type,
    'fields': [
      {'fieldname': 'description', 'label': 'Description', 'fieldtype': 'Data'},
      {'fieldname': 'reference', 'label': 'Reference', 'fieldtype': 'Data'},
      {'fieldname': 'quantity', 'label': 'Quantity', 'fieldtype': 'Float'},
      if (finance)
        {'fieldname': 'rate', 'label': 'Private rate', 'fieldtype': 'Currency'},
    ],
  });
  @override
  Future<NativeDocument> nativeDocument(
    String type, {
    String? name,
    String? company,
    String? treeParent,
  }) async {
    if (!available) throw const ErpException('Connection unavailable');
    return NativeDocument.fromJson({
      'doc': {
        'doctype': type,
        'name': 'TEST-1',
        'modified': 'current',
        'description': 'Original',
        'reference': reference,
        'quantity': 10,
        if (finance) 'rate': 123.45,
      },
      'permissions': {'read': true, 'write': true},
    });
  }

  NativeDocument linkedDraft() => NativeDocument.fromJson({
    'doc': {
      'doctype': 'Example',
      '__islocal': 1,
      'description': 'Mapped values',
      '__native_origin': {
        'doctype': 'Sales Order',
        'name': 'SO-1',
        'action': 'Sales Invoice',
        'modified': 'v1',
      },
    },
    'permissions': {'create': true},
  });

  @override
  Future<NativeDocument> newFromNative(
    String type,
    String name,
    String action,
    String modified,
  ) async {
    expect(
      [type, name, action, modified],
      ['Sales Order', 'SO-1', 'Sales Invoice', 'v1'],
    );
    mapped++;
    return linkedDraft();
  }

  @override
  Future<NativeDocument> saveNative(
    NativeSchema schema,
    Map<String, dynamic> values, {
    String action = 'Save',
  }) async {
    if (conflict) {
      throw const ErpException(
        'Someone changed this document.',
        staleDocument: true,
      );
    }
    return NativeDocument.fromJson({
      'doc': {...values, 'name': 'TEST-1'},
      'permissions': {'write': 1},
    });
  }
}

void main() {
  testWidgets(
    'stale save can recover in place and only discards edits after the fresh version loads',
    (tester) async {
      final api = AccessEditorApi()..conflict = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(api: api, doctype: 'Example', name: 'TEST-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Unsaved entry',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reload latest version'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved entry'), findsOneWidget);
      api.available = false;
      await tester.tap(find.text('Reload latest version'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard and reload'));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(find.text('Unsaved entry'), findsOneWidget);
      api.available = true;
      api.reference = 'Changed on server';
      await tester.tap(find.text('Reload latest version'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard and reload'));
      await tester.pumpAndSettle();
      expect(find.text('Changed on server'), findsOneWidget);
      expect(find.text('Unsaved entry'), findsNothing);
      expect(find.text('Reload latest version'), findsNothing);
    },
  );
  testWidgets(
    'core editor refreshes permissions and keeps only allowed draft input',
    (tester) async {
      final api = AccessEditorApi();
      addTearDown(api.close);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': 'before',
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(
            api: api,
            doctype: 'Example',
            name: 'TEST-1',
            company: 'Demo',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Keep edited description',
      );
      expect(find.text('Keep edited description'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '-',
      );
      api.reference = 'Corrected server reference';
      api.finance = false;
      api.available = false;
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': 'after',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check access again'), findsOneWidget);
      expect(find.text('Keep edited description'), findsNothing);
      api.available = true;
      await tester.tap(find.text('Check access again'));
      await tester.pumpAndSettle();
      expect(find.text('Keep edited description'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('Corrected server reference'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(find.text('Private rate'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'access refresh regenerates linked drafts from their original source',
    (tester) async {
      final api = AccessEditorApi();
      addTearDown(api.close);
      void publish(String fingerprint) => api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': fingerprint,
        }),
      );
      publish('before');
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentEditor(
            api: api,
            doctype: 'Example',
            company: 'Demo',
            initial: api.linkedDraft(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Keep linked edit',
      );
      publish('after');
      await tester.pumpAndSettle();
      expect(api.mapped, 1);
      expect(find.text('Keep linked edit'), findsOneWidget);
      expect(find.text('New Example'), findsOneWidget);
    },
  );
}
