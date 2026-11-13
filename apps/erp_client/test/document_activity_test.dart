import 'package:erp_client/document_activity.dart';
import 'package:erp_client/erp_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ActivityApi extends ErpApi {
  ActivityApi() : super(Uri.parse('http://localhost:8081'));
  final comments = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> documentActivity(
    String type,
    String name,
  ) async => {
    'permissions': <String, dynamic>{},
    'attachments': [],
    'assignments': [],
    'comments': List.of(comments),
    'versions': [],
  };
  @override
  Future<void> comment(String type, String name, String content) async {
    comments.add({
      'content': content,
      'owner': 'Tester',
      'creation': '2026-11-12',
      'comment_type': 'Comment',
    });
  }
}

void main() {
  testWidgets(
    'posting a comment refreshes activity without a framework error',
    (tester) async {
      final api = ActivityApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentActivityScreen(api: api, type: 'Example', name: 'EX-1'),
        ),
      );
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(TextButton, 'Add comment');
      expect(tester.widget<TextButton>(submit).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<TextButton>(submit).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Native review comment');
      await tester.ensureVisible(find.text('Add comment'));
      await tester.tap(find.text('Add comment'));
      await tester.pumpAndSettle();
      expect(find.text('Native review comment'), findsOneWidget);
      expect(
        find.textContaining('setState() callback argument returned a Future'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
