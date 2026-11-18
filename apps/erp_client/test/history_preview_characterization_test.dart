import 'package:erp_client/imported_record_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'imported_record_preview_test.dart' show OriginalRecordApi;

void main() {
  testWidgets(
    'a rejected original-record refresh hides the cached preview actions',
    (t) async {
      final api = OriginalRecordApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: ImportedRecordPreviewScreen(
            api: api,
            company: 'Synthetic Knitting',
            name: 'history-job-42',
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('Export PDF'), findsOneWidget);
      api.denied = true;
      await t.tap(find.text('Export PDF'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('Original record access was revoked.'), findsWidgets);
      expect(find.text('Export PDF'), findsNothing);
      expect(find.text('Print'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
