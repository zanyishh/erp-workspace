// Connected, opt-in rehearsal. The fixture provisions only synthetic local data.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/widgets.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  testWidgets(
    'new clerk purchases stock, delivers an order and settles invoices',
    (t) async {
      final dir = Directory(
        Platform.environment['PILOT_DIR'] ??
            (throw StateError(
              'Set PILOT_DIR to the isolated trade fixture directory.',
            )),
      );
      final cfg = jsonDecode(
        File('${dir.path}/erp-fixture.json').readAsStringSync(),
      ) as Map;
      final flow = Platform.environment['PILOT_FLOW'] ?? 'Purchase';
      if (!{'Purchase', 'Sales'}.contains(flow) ||
          !(cfg['company'] == 'ERP Native Verification' ||
              RegExp(r'^Pilot Trade [0-9a-f]{12}$')
                  .hasMatch(cfg['company'] as String)) ||
          !(cfg['username'] as String).endsWith('@example.invalid')) {
        throw StateError(
          'Use the synthetic trade fixture and select Purchase or Sales.',
        );
      }
      final purchase = flow == 'Purchase';
      final order = purchase ? 'Purchase Order' : 'Sales Order';
      final shipment = purchase ? 'Purchase Receipt' : 'Delivery Note';
      final bill = purchase ? 'Purchase Invoice' : 'Sales Invoice';
      final results = File('${dir.path}/${flow.toLowerCase()}-records.json');
      if (results.existsSync()) {
        throw StateError(
          'Use a fresh trade fixture before starting this journey.',
        );
      }
      final records = <String, String>{};
      final qty = purchase ? '5' : '2';
      final price = purchase ? '30' : '50';
      var step = '';
      late ErpApi api;
      final address = Uri.parse('http://localhost:8081');
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 1000);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      List<String> texts() => t
          .widgetList<Text>(find.byType(Text))
          .map((e) => e.data ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      Future<void> wait(bool Function() ok, String why) async {
        for (var n = 0; n < 105; n++) {
          await t.pump(const Duration(milliseconds: 75));
          if (ok()) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 75)),
          );
        }
        final errors = t
            .widgetList<TextField>(find.byType(TextField))
            .where((e) => e.decoration?.errorText != null)
            .map(
              (e) => '${e.decoration?.labelText}: ${e.decoration?.errorText}',
            )
            .toList();
        throw StateError(
          '$step: $why. Visible text: ${texts().where((s) => s.contains('required') || s.contains('ERPNext') || s.contains('this account') || s.contains('must') || s.contains('cannot') || s.contains('does not') || s.contains('Could not') || s.contains('Missing')).take(25).join(" | ")}. Field errors: $errors',
        );
      }

      Future<void> ready(Finder f) =>
          wait(() => f.evaluate().isNotEmpty, 'waiting for $f');
      Future<void> tap(Finder f) async {
        await ready(f);
        await t.ensureVisible(f.first);
        await t.pump(const Duration(milliseconds: 250));
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 300));
      }

      Future<void> press(String label) => tap(find.text(label));
      Future<void> fill(String key, String value) async {
        final container = find.byKey(ValueKey(key));
        final scoped = find.byType(Dialog).evaluate().isNotEmpty
            ? find.descendant(of: find.byType(Dialog).last, matching: container)
            : container;
        final field = find.descendant(
          of: scoped,
          matching: find.byType(TextField),
        );
        await ready(field);
        await t.ensureVisible(field.first);
        await t.enterText(field.first, value);
        await t.pump();
      }

      DocumentFields form() =>
          t.widgetList<DocumentFields>(find.byType(DocumentFields)).last;
      void log(String value) {
        step = value;
        debugPrint('Pilot: $step');
      }

      void record(String key, String name) {
        records[key] = name;
        results.writeAsStringSync(jsonEncode(records));
        debugPrint('Pilot submitted $key $name');
      }

      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(
            connect: (uri) {
              expect(uri, address);
              return api = ErpApi(uri);
            },
          ),
        ),
      );
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), cfg['username'] as String);
      await t.enterText(fields.at(1), cfg['password'] as String);
      log('sign in as scoped trade clerk');
      await press('Enter workspace');
      await ready(find.text('New document'));
      final catalog = await t.runAsync(
        () => api.nativeCatalog(company: cfg['company'] as String),
      );
      expect(catalog?.site, 'native-test.localhost');
      log('open $order from the permitted catalogue');
      await press('New document');
      await ready(find.byType(TextField));
      await t.enterText(find.byType(TextField).first, order);
      await t.pump();
      await tap(find.widgetWithText(ListTile, order).first);
      await ready(find.text('New $order'));
      {
        log('select party and load its defaults');
        final party = purchase ? 'supplier' : 'customer';
        await fill(party, cfg[party] as String);
        await press('Load party details');
        await ready(find.text('Party details updated'));
        final dateKey = purchase ? 'schedule_date' : 'delivery_date';
        await fill(dateKey, cfg['date'] as String);
        log('add $qty cartons to $order');
        final group = find.ancestor(
          of: find.text('ITEMS · 0'),
          matching: find.byType(Panel),
        );
        await tap(
          find.descendant(of: group.first, matching: find.text('Add row')),
        );
        await ready(find.byType(Dialog));
        await wait(
          () =>
              find.byKey(const ValueKey('item_code')).evaluate().isNotEmpty &&
              t
                  .widgetList<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator),
                  )
                  .isEmpty,
          'item entry',
        );
        await fill('item_code', cfg['item'] as String);
        await fill('qty', qty);
        await press('Load item details');
        await wait(
          () =>
              form().data['stock_uom'] == 'Nos' &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'item defaults',
        );
        await fill('qty', qty);
        await fill('rate', price);
        if (find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byKey(ValueKey(dateKey)),
            )
            .evaluate()
            .isNotEmpty) {
          await fill(dateKey, cfg['date'] as String);
        }
        if (find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byKey(const ValueKey('warehouse')),
            )
            .evaluate()
            .isNotEmpty) {
          await fill('warehouse', cfg['warehouse'] as String);
        }
        await press('Done');
        await wait(
          () => find.byType(Dialog).evaluate().isEmpty,
          'finish item entry',
        );
      }
      Future<void> submit(String type) async {
        log('save and submit $type');
        await press('Save');
        await ready(find.text('Saved successfully'));
        await press('Submit');
        await tap(find.widgetWithText(FilledButton, 'Submit document'));
        await ready(find.text('Submit completed'));
        final name = form().data['name'] as String;
        expect(form().data['docstatus'], 1);
        record(type, name);
      }

      await submit(order);
      for (final target in [shipment, bill, 'Payment Entry']) {
        log('create linked $target');
        await press('Create / copy ▾');
        await tap(find.widgetWithText(PopupMenuItem<String>, target));
        await ready(find.text('New $target'));
        if (target == 'Payment Entry') {
          final key = purchase ? 'paid_from' : 'paid_to';
          if ((form().data[key] ?? '').toString().isEmpty) {
            await fill(key, cfg['cash'] as String);
          }
        }
        await submit(target);
      }
      log('return to the paid invoice');
      await t.pageBack();
      await t.pump(const Duration(milliseconds: 300));
      await ready(find.text(records[bill]!));
      await wait(
        () =>
            num.tryParse(
              (form().data['outstanding_amount'] ?? '').toString(),
            ) ==
            0,
        'parent invoice shows the settled balance',
      );
      await press('Create / copy ▾');
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Payment Entry'),
        findsNothing,
        reason: 'A fully settled invoice cannot take another payment.',
      );
      final invoice = await t.runAsync(
        () => api.nativeDocument(bill, name: records[bill]!),
      );
      expect(num.parse(invoice!.data['outstanding_amount'].toString()), 0);
      expect(
        num.parse(invoice.data['grand_total'].toString()),
        purchase ? 150 : 100,
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 30));
      expect(t.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
