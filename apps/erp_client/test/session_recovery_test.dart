import 'package:erp_client/session_recovery.dart';
import 'package:erp_client/erp_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecoveryApi extends ErpApi {
  RecoveryApi() : super(Uri.parse('http://localhost:8081'));
  String? receivedAccount, receivedPassword;
  @override
  Future<void> login(String user, String password) async {
    receivedAccount = user;
    receivedPassword = password;
  }
}

void main() {
  testWidgets('system back cannot sign out and discard a draft from recovery', (
    tester,
  ) async {
    final api = RecoveryApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => SessionRecoveryDialog(api: api),
              ),
              child: const Text('Recover'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SessionRecoveryDialog), findsOneWidget);
  });

  testWidgets(
    'sign-in recovery keeps the underlying draft and uses the same account',
    (tester) async {
      final api = RecoveryApi()..account = 'native-user';
      addTearDown(api.close);
      bool? restored;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const TextField(
                    decoration: InputDecoration(labelText: 'Draft title'),
                  ),
                  TextButton(
                    onPressed: () async {
                      restored = await showDialog<bool>(
                        context: context,
                        builder: (_) => SessionRecoveryDialog(api: api),
                      );
                    },
                    child: const Text('Recover'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Keep my unsaved work');
      await tester.tap(find.text('Recover'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'test-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(restored, true);
      expect(api.receivedAccount, 'native-user');
      expect(find.text('Keep my unsaved work'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
