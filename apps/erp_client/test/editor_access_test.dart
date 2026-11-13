import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/workspace_context.dart';

class AccessEditorApi extends ErpApi {
  AccessEditorApi() : super(Uri.parse('http://localhost:8081'));
  bool finance = true;
  @override
  Future<NativeSchema> nativeSchema(
    String type,
  ) async => NativeSchema.fromJson({
    'doctype': type,
    'fields': [
      {'fieldname': 'description', 'label': 'Description', 'fieldtype': 'Data'},
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
  }) async => NativeDocument.fromJson({
    'doc': {
      'doctype': type,
      'name': 'TEST-1',
      'modified': 'current',
      'description': 'Original',
      if (finance) 'rate': 123.45,
    },
    'permissions': {'read': true, 'write': true},
  });
}

void main() {
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
      api.finance = false;
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': 'after',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keep edited description'), findsOneWidget);
      expect(find.text('Private rate'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
