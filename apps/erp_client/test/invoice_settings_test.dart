import 'dart:convert';
import 'dart:io';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/invoice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _CompanyApi extends ErpApi {
  _CompanyApi() : super(Uri.parse('http://localhost:8081'));
  var manager = true;
  int revision = 0, writes = 0;
  bool loseResponse = false;
  var profile = <String, String>{
    'template_id': 'ledger',
    'accent_color': '',
    'logo_base64': '',
    'signatory_name': '',
    'print_footer': '',
    'bank_name': '',
    'account_holder': '',
    'account_number': '',
    'ifsc': '',
    'upi_name': '',
    'upi_id': '',
  };
  Map<String, dynamic> get response => {
    'company': 'Mill A',
    'can_manage': manager,
    'revision': revision.toString(),
    'settings': {...profile},
  };
  @override
  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) async => {
    'rows': [],
    'statuses': ['All'],
    'default_template_id': profile['template_id'],
    'can_manage_settings': manager,
    'can_create': true,
  };
  @override
  Future<Map<String, dynamic>> invoiceSettings(String company) async {
    expect(company, 'Mill A');
    return response;
  }

  @override
  Future<Map<String, dynamic>> saveInvoiceSettings(
    String company,
    Map<String, String> settings,
    String version,
  ) async {
    expect(company, 'Mill A');
    if (revision.toString() != version) {
      throw const ErpException('Settings changed.', staleDocument: true);
    }
    expect(manager, true);
    writes++;
    revision++;
    profile = {...settings};
    if (loseResponse) throw const ErpException('Response lost');
    return response;
  }
}

void main() {
  late _CompanyApi api;
  setUp(() => api = _CompanyApi());
  tearDown(() => api.close());
  Future<void> hub(WidgetTester t, {double width = 900}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 920);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        home: InvoiceHub(api: api, company: 'Mill A', canCreate: true),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t) async {
    await t.tap(find.byTooltip('Invoice settings'));
    await t.pumpAndSettle();
    expect(find.byType(InvoiceSettingsScreen), findsOneWidget);
  }

  Future<void> change(WidgetTester t, String label, String value) async {
    final field = find.widgetWithText(TextFormField, label);
    await t.ensureVisible(field);
    await t.enterText(field, value);
    await t.pump();
  }

  Future<void> save(WidgetTester t) async {
    final button = find.text('Save settings');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
  }

  testWidgets(
    'company print footer and signatory can be saved and cleared on a phone',
    (t) async {
      await hub(t, width: 390);
      await open(t);
      await change(t, 'Signatory name', 'Demo Manager');
      await change(t, 'Printed footer', 'Thank you for your order');
      await save(t);
      expect(api.profile['signatory_name'], 'Demo Manager');
      expect(api.profile['print_footer'], 'Thank you for your order');
      await open(t);
      await change(t, 'Printed footer', '');
      await save(t);
      expect(api.profile['print_footer'], '');
      expect(api.profile['signatory_name'], 'Demo Manager');
    },
  );

  testWidgets(
    'company accent persists across reopening and resets to each template color',
    (t) async {
      await hub(t, width: 390);
      await open(t);
      Future<void> select(String old, String next) async {
        final current = find.text(old);
        await t.ensureVisible(current);
        await t.tap(current);
        await t.pumpAndSettle();
        await t.tap(find.text(next).last);
        await t.pumpAndSettle();
      }

      await select('Use template colors', 'Burgundy');
      await save(t);
      expect(api.profile['accent_color'], '#722C37');
      await open(t);
      await select('Burgundy', 'Use template colors');
      await save(t);
      expect(api.profile['accent_color'], '');
      expect(api.profile['template_id'], 'ledger');
    },
  );

  testWidgets(
    'lost settings save response verifies saved values before reporting success',
    (t) async {
      await hub(t);
      await open(t);
      await change(t, 'Bank name', 'Verified Bank');
      await change(t, 'Account number', '0042');
      api.loseResponse = true;
      await save(t);
      expect(api.writes, 1);
      expect(find.byType(InvoiceSettingsScreen), findsNothing);
      expect(api.profile['account_number'], '0042');
    },
  );

  testWidgets(
    'company default and payment details save together; bank information can be cleared',
    (t) async {
      await hub(t);
      await open(t);
      await t.tap(find.byTooltip('Choose default template'));
      await t.pumpAndSettle();
      await t.tap(find.text('Light Ribbon'));
      await t.pumpAndSettle();
      await change(t, 'Bank name', 'Demo Bank');
      await change(t, 'Account number', '00002345');
      await change(t, 'UPI ID', 'mill@demo');
      await save(t);
      expect(api.profile['template_id'], 'ribbon');
      expect(api.profile['account_number'], '00002345');
      expect(api.profile['upi_id'], 'mill@demo');
      await open(t);
      await change(t, 'Bank name', '');
      await change(t, 'Account number', '');
      await save(t);
      expect(api.profile['account_number'], '');
      expect(api.profile['upi_id'], 'mill@demo');
    },
  );

  testWidgets(
    'owner can remove the stored logo on a phone and stale writes offer reload',
    (t) async {
      api.profile['logo_base64'] = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO9WKS8AAAAASUVORK5CYII=';
      await hub(t, width: 360);
      await open(t);
      await t.tap(find.byTooltip('Remove logo'));
      await t.pumpAndSettle();
      api.revision++;
      await save(t);
      await t.ensureVisible(find.text('Reload settings'));
      await t.tap(find.text('Reload settings'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Remove logo'), findsOneWidget);
      await t.ensureVisible(find.byTooltip('Remove logo'));
      await t.tap(find.byTooltip('Remove logo'));
      await t.pumpAndSettle();
      await save(t);
      expect(api.profile['logo_base64'], isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('staff receive no settings editor button', (t) async {
    api.manager = false;
    await hub(t);
    expect(find.byTooltip('Invoice settings'), findsNothing);
  });

  testWidgets(
    'logo picker rejects an unreadable file and saves the selected PNG',
    (t) async {
      final dir = Directory.systemTemp.createTempSync('invoice-logo-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/logo.png')
        ..writeAsStringSync('not a valid image');
      const picker = MethodChannel('plugins.flutter.io/file_selector');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        expect(call.method, 'openFile');
        return [file.path];
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      await hub(t);
      await open(t);
      Future<void> chooseUntil(String text) async {
        await t.tap(find.text('Add logo'));
        for (var i = 0; i < 75 && find.text(text).evaluate().isEmpty; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(find.text(text), findsOneWidget);
      }

      await chooseUntil('Choose a PNG or JPEG image.');
      final fixture = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO9WKS8AAAAASUVORK5CYII=',
      );
      file.writeAsBytesSync(fixture);
      await chooseUntil('Replace logo');
      await save(t);
      expect(api.profile['logo_base64'], base64Encode(fixture));
    },
  );
}
