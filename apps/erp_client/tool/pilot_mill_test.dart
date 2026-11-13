// Opt-in connected Flutter rehearsal. Run only on the dedicated local test site.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/main.dart';

class PilotBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  final binding = PilotBinding();
  testWidgets(
    'New mill user completes a customer-material job through the connected Flutter UI',
    (t) async {
      final path = Platform.environment['PILOT_DIR'];
      if (path == null) {
        throw StateError(
          'Set PILOT_DIR to the isolated mill fixture directory.',
        );
      }
      final auth = jsonDecode(
        File('$path/mill-credentials.json').readAsStringSync(),
      );
      final progress = File('$path/mill-progress.json');
      final state = progress.existsSync()
          ? jsonDecode(progress.readAsStringSync()) as Map
          : {};
      final user = auth['user'];
      const company = 'ERP Native Verification';
      late ErpApi api;
      expect(user.endsWith('@example.invalid'), true);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 1000);
      await binding.setSurfaceSize(const Size(1440, 1000));
      String visible() => t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .where((s) => s.isNotEmpty)
          .join(' | ');
      Future<void> wait(Finder f) async {
        for (var i = 0; i < 170 && f.evaluate().isEmpty; i++) {
          await t.runAsync(
            () => Future.delayed(const Duration(milliseconds: 100)),
          );
          await t.pump(const Duration(milliseconds: 120));
        }
        if (f.evaluate().isEmpty) {
          throw StateError('Waiting for $f. Screen: ${visible()}');
        }
        await t.pump(const Duration(milliseconds: 350));
      }

      Future<void> tap(Finder f) async {
        await wait(f);
        await t.ensureVisible(f.first);
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 350));
      }

      Future<void> label(String s) => tap(find.text(s));
      Future<void> input(String name, String value, {int index = 0}) async {
        final fields = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == name,
          description: name,
        );
        await wait(fields);
        final f = fields.at(index);
        await wait(f);
        await t.ensureVisible(f);
        await t.enterText(f, value);
        await t.pump();
      }

      Future<void> pick(String name, String query) async {
        await tap(
          find.byWidgetPredicate(
            (w) => w is InputDecorator && w.decoration.labelText == name,
          ),
        );
        await input('Search by reference or name', query);
        await t.pump(const Duration(milliseconds: 500));
        await tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining(query),
          ),
        );
      }

      Future<void> next(String name) async {
        stdout.writeln('MILL next $name');
        final f = find.byKey(const ValueKey('next-job-action'));
        await wait(f);
        expect(
          find.descendant(of: f, matching: find.text(name)),
          findsOneWidget,
          reason: visible(),
        );
        await tap(f);
      }

      Future<void> post(String step) async {
        stdout.writeln('MILL review $step');
        await label('Review entry');
        await label('Confirm & post');
        await wait(find.text('SAVED IN ERP'));
        if (step == 'create_job') {
          state['job'] = t
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((w) => w.data ?? '')
              .firstWhere((s) => s.startsWith('Job · '))
              .substring(6);
        }
        state[step] = true;
        progress.writeAsStringSync(jsonEncode(state));
        stdout.writeln('MILL posted $step for ${state['job']}');
        await label('Done');
      }

      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: WorkspaceShell(
            connect: (uri) {
              if (uri.toString() != 'http://localhost:8081') {
                throw StateError('Pilot refuses an external server');
              }
              return api = ErpApi(uri);
            },
          ),
        ),
      );
      await input('Username', user);
      await input('Password', auth['password']);
      await label('Enter workspace');
      await wait(find.text('Mill overview'));
      await label('Jobs');
      await t.runAsync(() async {
        expect(api.account, user);
        expect(
          (await api.nativeCatalog(company: company)).site,
          'native-test.localhost',
        );
        final ctx = await api.workspaceContext();
        expect(ctx.company, company);
        expect(ctx.companies.length, 1);
        expect(ctx.allows('new_job'), isTrue);
      });
      expect(t.takeException(), isNull);
      stdout.writeln('MILL signed in with scoped staff account');
      if (state['job'] == null) {
        await label('New job');
        await pick('Customer', 'Demo Knitting Mills');
        await input('Target · kg', '12');
        await input('Rate per kg', '100');
        await label('Add fabric programme');
        await input('Fabric', 'Pilot single jersey');
        await input('Colour', 'Natural');
        await input('Target · kg', '12', index: 1);
        await input('Notes', 'Synthetic connected Flutter pilot');
        await post('create_job');
      } else {
        await label('Find any job');
        await input('Search by reference or name', state['job']);
        await t.pump(const Duration(milliseconds: 500));
        await tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining(state['job']),
          ),
        );
      }
      if (state['receive_yarn'] != true) {
        await next('Receive yarn');
        await tap(
          find.byWidgetPredicate(
            (w) => w is InputDecorator && w.decoration.labelText == 'Yarn item',
          ),
        );
        await input('Search by reference or name', 'DEMO-KNIT-SERVICE');
        await t.pump(const Duration(milliseconds: 500));
        await wait(find.text('No matching records.'));
        await input('Search by reference or name', 'DEMO-KNIT-YARN');
        await t.pump(const Duration(milliseconds: 500));
        await tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.textContaining('DEMO-KNIT-YARN'),
          ),
        );
        await input('Quantity · kg', '15');
        await input('Bags / units', '1');
        await post('receive_yarn');
      }
      if (state['produce'] != true) {
        await next('Record production');
        await input('Shift', 'A');
        await input('Individual roll weights · kg', '12');
        await input('Quantity · kg', '16');
        await input('Declared loss · kg', '4');
        await label('Review entry');
        await label('Confirm & post');
        await wait(
          find.text('Yarn consumption exceeds the selected lot allocation.'),
        );
        expect(find.text('Review entry'), findsOneWidget);
        expect(find.text('Check save status'), findsNothing);
        expect(find.text('16'), findsOneWidget);
        await input('Quantity · kg', '13');
        await input('Declared loss · kg', '1');
        await post('produce');
        state['correctedExcessInput'] = true;
      }
      if (state['hold'] != true) {
        await next('Inspect roll');
        await input('Inspection notes', 'Hold pending second inspection');
        await label('Review entry');
        await wait(find.text('Choose an inspection decision.'));
        await tap(find.byType(DropdownButton<String>));
        await label('On Hold');
        await post('hold');
      }
      if (state['quality'] != true) {
        await next('Inspect roll');
        await input('Inspection notes', 'Second inspection passed');
        await tap(find.byType(DropdownButton<String>));
        await label('Released');
        await post('quality');
      }
      if (state['deliver'] != true) {
        await next('Create delivery');
        await input('Delivery destination', 'Pilot packing desk');
        await post('deliver');
      }
      if (state['invoice'] != true) {
        await next('Create invoice');
        await post('invoice');
      }
      if (state['return_yarn'] != true) {
        await next('Return yarn');
        await input('Quantity · kg', '2');
        await input('Bags / cones moved or emptied', '1');
        await post('return_yarn');
      }
      if (state['close_job'] != true) {
        await next('Complete job');
        await post('close_job');
      }
      await wait(find.text('Job complete'));
      await t.runAsync(() async {
        final data = await api.knittingSnapshot(company, job: state['job']);
        final row = data.rows('jobs').single;
        final balances = row['balances'] as Map;
        for (final e in {
          'received_kg': '15.000',
          'consumed_kg': '13.000',
          'produced_kg': '12.000',
          'loss_kg': '1.000',
          'delivered_kg': '12.000',
          'billed_kg': '12.000',
          'returned_kg': '2.000',
          'fabric_kg': '0.000',
          'yarn_kg': '0.000',
          'unbilled_kg': '0.000',
          'subcontract_kg': '0.000',
        }.entries) {
          expect(balances[e.key], e.value, reason: e.key);
        }
        expect(row['status'], 'Completed');
        final bills = await api.knittingReport(company, 'billing', {
          'job': state['job'],
        });
        final entry = (bills['rows'] as List).single;
        final invoice = await api.nativeDocument(
          'Sales Invoice',
          name: entry['invoice'],
          company: company,
        );
        expect(invoice.data['docstatus'], 1);
        expect(double.parse(invoice.data['grand_total'].toString()), 1200);
        state['invoice'] = entry['invoice'];
        state['invoiceAmount'] = invoice.data['grand_total'];
        state['site'] = 'native-test.localhost';
        state['company'] = company;
        state['account'] = user;
        state['balances'] = balances;
        state['status'] = row['status'];
        File(
          '$path/mill-result.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(state));
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      t.view.resetDevicePixelRatio();
      t.view.resetPhysicalSize();
      await binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
