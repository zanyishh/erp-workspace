import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/native_models.dart';

void main() {
  testWidgets(
    'new heading is escaped, cancellation preserves the draft, and read-only notes have no edit action',
    (t) async {
      final schema = NativeSchema.fromJson({
        'doctype': 'Task',
        'fields': [
          {
            'fieldname': 'description',
            'fieldtype': 'Text Editor',
            'label': 'Description',
          },
        ],
      });
      final record = <String, dynamic>{'description': '<p>Instructions</p>'};
      Future<void> form(bool editable) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, refresh) => DocumentFields(
                schema: schema,
                data: record,
                editable: editable,
                onChanged: () => refresh(() {}),
              ),
            ),
          ),
        ),
      );
      await form(true);
      await t.tap(find.byTooltip('Edit Description'));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Heading').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Add text'),
        '<Dispatch & pack>',
      );
      await t.tap(find.text('Apply'));
      await t.pumpAndSettle();
      expect(
        record['description'],
        '<p>Instructions</p><h2>&lt;Dispatch &amp; pack&gt;</h2>',
      );
      await t.tap(find.byTooltip('Edit Description'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Instructions'),
        'New instructions',
      );
      await t.tap(find.byTooltip('Cancel edits'));
      await t.pumpAndSettle();
      expect(record['description'], contains('<p>Instructions</p>'));
      await form(false);
      await t.pumpAndSettle();
      expect(find.byTooltip('Edit Description'), findsNothing);
    },
  );
  testWidgets(
    'a text editor previews formatting locally and preserves unsupported markup while editing a text run',
    (t) async {
      const original =
          '<div data-custom="keep"><p>Hello <strong>mill</strong>.</p><img src="https://example.invalid/photo.png"><script>ignored()</script></div>';
      final schema = NativeSchema.fromJson({
        'doctype': 'Task',
        'fields': [
          {
            'fieldname': 'description',
            'fieldtype': 'Text Editor',
            'label': 'Description',
          },
        ],
      });
      final record = <String, dynamic>{'description': original};
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentFields(
              schema: schema,
              data: record,
              onChanged: () {},
            ),
          ),
        ),
      );
      expect(find.text('Hello mill.', findRichText: true), findsOneWidget);
      expect(find.textContaining('ignored()'), findsNothing);
      expect(find.byType(Image), findsNothing);
      await t.tap(find.byTooltip('Edit Description'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'mill'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'mill'),
        'team & dispatch',
      );
      await t.tap(find.text('Apply'));
      await t.pumpAndSettle();
      expect(
        record['description'],
        original.replaceFirst('>mill<', '>team &amp; dispatch<'),
      );
      await t.tap(find.byTooltip('Edit Description'));
      await t.pumpAndSettle();
      await t.tap(find.text('Apply'));
      await t.pumpAndSettle();
      expect(
        record['description'],
        original.replaceFirst('>mill<', '>team &amp; dispatch<'),
      );
    },
  );
}
