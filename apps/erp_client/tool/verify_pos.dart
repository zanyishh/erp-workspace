// Live, synthetic owner-to-cashier rehearsal. The admin session only confirms
// the local site identity. All setup and posting use the new app accounts.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:erp_client/erp_api.dart';

Future<void> main() async {
  final uri = Uri.parse('http://localhost:8081');
  final admin = ErpApi(uri),
      guest = ErpApi(uri),
      owner = ErpApi(uri),
      staff = ErpApi(uri);
  final stamp = DateTime.now().microsecondsSinceEpoch.toString();
  final company = 'Register rehearsal $stamp',
      email = 'register-owner-$stamp@example.invalid',
      cashier = 'register-cashier-$stamp@example.invalid';
  final random = Random.secure();
  String secret() =>
      base64Url.encode(List.generate(24, (_) => random.nextInt(256)));
  final password = secret(), staffPassword = secret();
  void check(bool ok, String msg) {
    if (!ok) throw StateError(msg);
  }

  try {
    await admin.login(
      'Administrator',
      Platform.environment['ERP_LOCAL_PILOT_PASSWORD'] ??
          (throw StateError('Set the isolated verification password.')),
    );
    check(
      (await admin.nativeCatalog()).site == 'native-test.localhost',
      'Wrong test site',
    );
    await admin.signOut();
    await guest.registerOwner(
      fullName: 'Register Owner',
      email: email,
      password: password,
      company: company,
      industry: 'general',
    );
    await owner.login(email, password);
    final ctx = await owner.workspaceContext();
    check(
      ctx.canOperatePos && !ctx.cashierHome,
      'Owner register access missing',
    );
    final profile = (await owner.posConfigure(company))['profile'] as String;
    final invitation = await owner.inviteMember(company, cashier, 'cashier');
    await guest.acceptInvitation(
      invitation['token'] as String,
      email: cashier,
      password: staffPassword,
      fullName: 'Store Cashier',
    );
    Future<Map<String, dynamic>> create(
      String type,
      Map<String, dynamic> fields,
    ) async {
      final schema = await owner.nativeSchema(type);
      final doc = (await owner.nativeDocument(
        type,
        company: company,
      )).editCopy()..addAll(fields);
      return (await owner.saveNative(schema, doc)).data;
    }

    final registerDoc = await owner.nativeDocument(
      'POS Profile',
      name: profile,
      company: company,
    );
    final shopper = await create('Customer', {
      'customer_name': 'Register shopper $stamp',
      'customer_type': 'Company',
      'customer_group': 'Commercial',
      'territory': 'India',
    });
    final item = await create('Item', {
      'item_code': 'REGISTER-SERVICE-$stamp',
      'item_name': 'Register service',
      'item_group': 'Services',
      'stock_uom': 'Nos',
      'is_stock_item': 0,
    });
    await create('Item Price', {
      'item_code': item['name'],
      'price_list': registerDoc.data['selling_price_list'],
      'price_list_rate': 45,
      'uom': 'Nos',
    });
    await staff.login(cashier, staffPassword);
    final staffCtx = await staff.workspaceContext();
    check(
      staffCtx.cashierHome &&
          staffCtx.canOperatePos &&
          !staffCtx.canManageTeam &&
          !staffCtx.canOpenDesk,
      'Incorrect cashier workspace',
    );
    final register = await staff.posRegister(company);
    check(
      (register['profiles'] as List).contains(profile),
      'Cashier not assigned',
    );
    final opening =
        (await staff.posOpenShift(company, profile, '100'))['opening']
            as String;
    final cart = [
      {'item': item['name'], 'qty': 2},
    ];
    final quote = await staff.posQuote(company, opening, shopper['name'], cart);
    check(double.parse(quote['amount'].toString()) == 90, 'Unexpected price');
    final token = secret();
    final receipt = await staff.posCheckout(
      company,
      opening,
      shopper['name'],
      cart,
      quote['amount'].toString(),
      token,
    );
    final retry = await staff.posCheckout(
      company,
      opening,
      shopper['name'],
      cart,
      quote['amount'].toString(),
      token,
    );
    check(receipt['invoice'] == retry['invoice'], 'Duplicate checkout');
    final checkOut = await staff.posClosing(company, opening);
    final balance = (checkOut['payments'] as List).single;
    check(
      double.parse(balance['expected'].toString()) == 190,
      'Wrong closing balance',
    );
    final close = await staff.posCloseShift(company, opening, {
      balance['mode'] as String: '190',
    }, checkOut['revision']);
    check(
      (await staff.posRegister(company))['opening'] == null,
      'Register did not close',
    );
    final returnShift =
        (await staff.posOpenShift(company, profile, '100'))['opening']
            as String;
    final original = receipt['invoice'] as String;
    final review = await staff.posRefundReview(company, returnShift, original);
    final refundToken = secret();
    final credit = await staff.posRefund(
      company,
      returnShift,
      original,
      review['amount'].toString(),
      refundToken,
    );
    final retriedCredit = await staff.posRefund(
      company,
      returnShift,
      original,
      review['amount'].toString(),
      refundToken,
    );
    check(
      retriedCredit['invoice'] == credit['invoice'],
      'Duplicate cash refund',
    );
    check(
      double.parse(credit['amount'].toString()) == -90,
      'Incorrect credit amount',
    );
    final refunded = await staff.posClosing(company, returnShift);
    final after = (refunded['payments'] as List).single;
    check(
      double.parse(after['expected'].toString()) == 10,
      'Wrong drawer balance after refund',
    );
    final refundClose = await staff.posCloseShift(company, returnShift, {
      after['mode'] as String: '10',
    }, refunded['revision']);
    stdout.writeln(
      jsonEncode({
        'site': 'native-test.localhost',
        'company': company,
        'profile': profile,
        'cashier_home': true,
        'opening': opening,
        'invoice': receipt['invoice'],
        'paid': receipt['amount'],
        'closing': close['closing'],
        'drawer_expected': balance['expected'],
        'credit': credit['invoice'],
        'refunded': credit['amount'],
        'refund_closing': refundClose['closing'],
        'refund_drawer': after['expected'],
      }),
    );
  } finally {
    for (final api in [admin, guest, owner, staff]) {
      try {
        await api.signOut();
      } catch (_) {
      } finally {
        api.close();
      }
    }
  }
}
