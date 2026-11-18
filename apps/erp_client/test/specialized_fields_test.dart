import 'package:erp_client/document_fields.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'field editor shows private file controls and a drawable signature',
    (t) async {
      final data = <String, dynamic>{};
      final schema = NativeSchema.fromJson({
        'doctype': 'Fixture',
        'fields': [
          {'fieldtype': 'Attach', 'fieldname': 'proof', 'label': 'Proof'},
          {'fieldtype': 'Data', 'fieldname': 'source', 'label': 'Source'},
          {
            'fieldtype': 'Signature',
            'fieldname': 'signed',
            'label': 'Received by',
          },
          {
            'fieldtype': 'Barcode',
            'fieldname': 'code',
            'label': 'Label code',
            'options': '{"valueField":"source"}',
          },
        ],
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (c, setState) => DocumentFields(
                  schema: schema,
                  data: data,
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Choose file'), findsOneWidget);
      await t.tap(find.text('Add signature'));
      await t.pumpAndSettle();
      final pad = find.byKey(const ValueKey('signature-pad'));
      final pen = await t.startGesture(t.getCenter(pad));
      await pen.moveBy(const Offset(40, 16));
      await pen.moveBy(const Offset(20, -14));
      await pen.up();
      await t.pump();
      await t.tap(find.text('Use signature'));
      for (var i = 0; i < 30 && data['signed'] == null; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(data['signed'], startsWith('data:image/png;base64,'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Label code'), '000127');
      await t.pump();
      expect(data['source'], '000127');
      expect(
        schema.payload(data)['code'],
        contains('data-barcode-value="000127"'),
      );
      expect(find.byTooltip('Clear signature'), findsOneWidget);
    },
  );
}
