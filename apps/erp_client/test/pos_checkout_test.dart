import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/pos_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Register extends ErpApi {
  _Register() : super(Uri.parse('http://localhost:8081'));
  bool active = false;
  Completer<Map<String, dynamic>>? pendingCheckout;
  bool configured = true;
  @override
  Future<Map<String, dynamic>> posConfigure(String company) async {
    configured = true;
    return {'profile': 'Shop'};
  }

  final keys = <String>[];
  final refundKeys = <String>[];
  @override
  Future<Map<String, dynamic>> posRefundReview(
    String company,
    String opening,
    String invoice,
  ) async {
    expect(invoice, 'INV-1');
    return {
      'customer': 'Customer A',
      'amount': '90',
      'currency': 'INR',
      'items': [
        {'item': 'Item A', 'qty': 2, 'amount': 90},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> posRefund(
    String company,
    String opening,
    String invoice,
    String expected,
    String token,
  ) async {
    refundKeys.add(token);
    if (refundKeys.length == 1) {
      throw const ErpException('Connection interrupted.');
    }
    return {'invoice': 'CREDIT-1', 'amount': '-90', 'currency': 'INR'};
  }

  @override
  Future<Map<String, dynamic>> posRegister(String company) async => {
    'profiles': configured ? ['Shop'] : [],
    'can_configure': !configured,
    'opening': active ? 'SHIFT-1' : null,
    'profile': active ? 'Shop' : null,
  };
  @override
  Future<Map<String, dynamic>> posOpenShift(
    String company,
    String profile,
    String amount,
  ) async {
    active = true;
    return {'opening': 'SHIFT-1'};
  }

  @override
  Future<Map<String, dynamic>> posQuote(
    String company,
    String opening,
    String customer,
    List<Map<String, dynamic>> items,
  ) async {
    expect(customer, 'Customer A');
    expect(items.single['item'], 'Item A');
    return {
      'amount': '90',
      'currency': 'INR',
      'items': [
        {'item': 'Item A', 'qty': 2, 'rate': 45, 'amount': 90},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> posCheckout(
    String company,
    String opening,
    String customer,
    List<Map<String, dynamic>> items,
    String expected,
    String token,
  ) async {
    keys.add(token);
    if (pendingCheckout != null) return pendingCheckout!.future;
    if (keys.length == 1) throw const ErpException('Connection interrupted.');
    return {
      'doctype': 'Sales Invoice',
      'invoice': 'INV-1',
      'amount': '90',
      'currency': 'INR',
    };
  }

  @override
  Future<Map<String, dynamic>> posClosing(
    String company,
    String opening,
  ) async => {
    'sales': 1,
    'revision': 'v1',
    'payments': [
      {'mode': 'Cash', 'expected': '190.0'},
    ],
  };
  @override
  Future<Map<String, dynamic>> posCloseShift(
    String company,
    String opening,
    Map<String, String> amounts,
    String revision,
  ) async {
    expect(amounts, {'Cash': '190'});
    expect(revision, 'v1');
    active = false;
    return {'closing': 'CLOSE-1', 'status': 'Submitted'};
  }
}

void main() {
  Future<void> open(
    WidgetTester t,
    _Register api, {
    VoidCallback? onAccount,
  }) async {
    t.view.physicalSize = const Size(900, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                c,
                MaterialPageRoute(
                  builder: (_) => PosCheckoutScreen(
                    api: api,
                    company: 'Store',
                    onAccount: onAccount,
                  ),
                ),
              ),
              child: const Text('Open POS'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open POS'));
    await t.pumpAndSettle();
  }

  Future<void> sale(WidgetTester t) async {
    await t.enterText(find.widgetWithText(TextField, 'Customer'), 'Customer A');
    await t.enterText(find.widgetWithText(TextField, 'Item'), 'Item A');
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '2');
    await t.tap(find.text('Add to sale'));
    await t.pumpAndSettle();
    await t.tap(find.text('Review sale'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'checkout blocks Back in flight and Account after an uncertain response',
    (t) async {
      final api = _Register()..active = true;
      addTearDown(api.close);
      var accounts = 0;
      await open(t, api, onAccount: () => accounts++);
      await sale(t);
      api.pendingCheckout = Completer<Map<String, dynamic>>();
      await t.tap(find.text('Confirm cash received'));
      await t.pump();
      await t.pageBack();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(PosCheckoutScreen), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      api.pendingCheckout!.completeError(
        const ErpException('Connection interrupted.'),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Account'));
      await t.pumpAndSettle();
      expect(accounts, 0);
      expect(find.text('Discard'), findsNothing);
      expect(find.textContaining('Retry same checkout'), findsWidgets);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      api.pendingCheckout = null;
      await t.tap(find.text('Retry same checkout'));
      await t.pumpAndSettle();
      expect(api.keys.toSet().length, 1);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Open POS'), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain refund retains its token and cannot be abandoned with Back',
    (t) async {
      final api = _Register()..active = true;
      addTearDown(api.close);
      await open(t, api);
      await t.tap(find.text('Refund a sale'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Original invoice number'),
        'INV-1',
      );
      await t.tap(find.text('Review refund'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm cash refund'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Keep editing'), findsOneWidget);
      expect(find.text('Discard'), findsNothing);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      await t.tap(find.text('Retry same refund'));
      await t.pumpAndSettle();
      expect(api.refundKeys.toSet().length, 1);
      expect(find.textContaining('CREDIT-1'), findsOneWidget);
    },
  );

  testWidgets('cart removal can be undone and Back protects the entry', (
    t,
  ) async {
    final api = _Register()..active = true;
    addTearDown(api.close);
    t.view.physicalSize = const Size(900, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                c,
                MaterialPageRoute(
                  builder: (_) => PosCheckoutScreen(api: api, company: 'Store'),
                ),
              ),
              child: const Text('Open POS'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open POS'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Customer'),
      'Customer A',
    );
    await t.enterText(find.widgetWithText(TextFormField, 'Item'), 'Item A');
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '2');
    await t.tap(find.text('Add to sale'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Item'), 'Item B');
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '3');
    await t.tap(find.text('Add to sale'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Remove Item A'));
    await t.pumpAndSettle();
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(find.text('Quantity 2.0'), findsOneWidget);
    expect(find.text('Quantity 3.0'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Quantity 2.0')).dy,
      lessThan(t.getTopLeft(find.text('Quantity 3.0')).dy),
    );
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Keep editing'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(find.text('Quantity 2.0'), findsOneWidget);
  });
  testWidgets('owner creates a register from the empty state', (t) async {
    final api = _Register()..configured = false;
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: PosCheckoutScreen(api: api, company: 'Store'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Create company register'));
    await t.pumpAndSettle();
    expect(find.text('Open register'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
  });
  testWidgets(
    'cashier reviews and recovers the same sale before counting the drawer',
    (t) async {
      final api = _Register();
      addTearDown(api.close);
      t.view.physicalSize = const Size(390, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: PosCheckoutScreen(api: api, company: 'Test Shop'),
        ),
      );
      await t.pumpAndSettle();
      Future<void> press(String label) async {
        final f = find.text(label);
        await t.ensureVisible(f.last);
        await t.tap(f.last);
        await t.pumpAndSettle();
      }

      Future<void> input(String label, String value) async {
        final f = find.widgetWithText(TextField, label);
        await t.ensureVisible(f);
        await t.enterText(f, value);
        await t.pump();
      }

      await input('Opening cash', '100');
      await press('Open register');
      await input('Customer', 'Customer A');
      await input('Item', 'Item A');
      await input('Quantity', '2');
      await press('Add to sale');
      await press('Review sale');
      expect(find.text('Cash due · INR 90'), findsOneWidget);
      await press('Confirm cash received');
      expect(find.text('Edit sale'), findsNothing);
      await press('Retry same checkout');
      expect(api.keys.first, api.keys.last);
      expect(api.keys.length, 2);
      expect(find.textContaining('INV-1'), findsOneWidget);
      await press('Refund a sale');
      await press('Review refund');
      expect(find.text('Cash refund · INR 90'), findsOneWidget);
      await press('Confirm cash refund');
      await press('Retry same refund');
      expect(api.refundKeys.length, 2);
      expect(api.refundKeys.first, api.refundKeys.last);
      expect(find.textContaining('CREDIT-1'), findsOneWidget);
      await press('Close shift');
      await input('Counted Cash', '190');
      await press('Confirm close');
      expect(find.textContaining('CLOSE-1'), findsOneWidget);
      expect(find.text('Open register'), findsOneWidget);
    },
  );
}
