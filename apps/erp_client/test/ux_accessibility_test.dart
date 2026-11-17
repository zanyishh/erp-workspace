import 'dart:async';

import 'package:erp_client/widgets.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/ui/access_gate.dart';
import 'package:erp_client/ui/date_entry.dart';
import 'package:erp_client/invoice_gallery.dart';
import 'package:erp_client/invoice_templates.dart';
import 'package:erp_client/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _GateApi extends ErpApi {
  _GateApi() : super(Uri.parse('http://localhost:8081'));
  final listeners = <VoidCallback>{};
  @override
  void addAccessListener(VoidCallback listener) => listeners.add(listener);
  @override
  void removeAccessListener(VoidCallback listener) =>
      listeners.remove(listener);
  void revoke() {
    accessRevision++;
    accessReady = false;
    for (final fn in List.of(listeners)) {
      fn();
    }
  }
}

void main() {
  testWidgets(
    'replacement service access is rechecked and old listeners detach',
    (t) async {
      final a = _GateApi(), b = _GateApi();
      final selected = ValueNotifier<ErpApi>(a);
      final checked = Completer<void>();
      addTearDown(a.close);
      addTearDown(b.close);
      addTearDown(selected.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: selected,
            builder: (_, api, _) => AccessGate(
              api: api,
              revalidate: () => checked.future,
              child: const Text('Protected record'),
            ),
          ),
        ),
      );
      expect(find.text('Protected record'), findsOneWidget);
      selected.value = b;
      await t.pump();
      expect(find.text('Protected record'), findsNothing);
      expect(a.listeners, isEmpty);
      expect(b.listeners.length, 1);
      checked.complete();
      await t.pumpAndSettle();
      expect(find.text('Protected record'), findsOneWidget);
      b.revoke();
      await t.pumpAndSettle();
      expect(find.text('Protected record'), findsNothing);
    },
  );
  testWidgets('shared button hit areas remain at least 48 logical pixels', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: Scaffold(
          body: Column(
            children: [
              CircleControl(
                icon: Icons.search,
                label: 'Find records',
                onPressed: () {},
              ),
              Pill('Save', onPressed: () {}),
              FilledButton(onPressed: () {}, child: const Text('Review')),
              OutlinedButton(onPressed: () {}, child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
    for (final finder in [
      find.byType(CircleControl),
      find.byType(Pill),
      find.byType(FilledButton),
      find.byType(OutlinedButton),
    ]) {
      expect(t.getSize(finder).height, greaterThanOrEqualTo(48));
      expect(t.getSize(finder).width, greaterThanOrEqualTo(48));
    }
    expect(find.byTooltip('Find records'), findsOneWidget);
  });
  testWidgets(
    'sample paper keeps shared identity and becomes static for reduced motion',
    (t) async {
      Widget preview(bool reduced) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: InvoicePaperContinuity(
            tag: ('synthetic-company', invoiceTemplates.first.id),
            template: invoiceTemplates.first,
            child: const Text('Sample paper'),
          ),
        ),
      );
      await t.pumpWidget(preview(false));
      expect(find.byType(Hero), findsOneWidget);
      await t.pumpWidget(preview(true));
      expect(find.byType(Hero), findsNothing);
      expect(find.text('Sample paper'), findsOneWidget);
    },
  );
  test(
    'date entry rejects normalized impossible dates and incomplete times',
    () {
      expect(validEntryDate('2026-02-31', withTime: false), isFalse);
      expect(validEntryDate('2024-02-29', withTime: false), isTrue);
      expect(validEntryDate('2026-02-29', withTime: false), isFalse);
      expect(validEntryDate('2026-11-16 23:59', withTime: true), isTrue);
      expect(validEntryDate('2026-11-16 24:00', withTime: true), isFalse);
      expect(validEntryDate('2026-11-16', withTime: true), isFalse);
    },
  );
  testWidgets('large metrics preserve text scaling without shrinking value', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: MetricTile(
                  label: 'Outstanding invoices',
                  value: '₹12,345,678.90',
                  footer: 'Current company · this month',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(FittedBox), findsNothing);
    expect(t.takeException(), isNull);
    expect(find.text('₹12,345,678.90'), findsOneWidget);
  });
  testWidgets(
    'date picker keeps direct typing and updates the same form value',
    (t) async {
      String saved = '';
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateEntry(
              label: 'Job date',
              initialValue: '2026-11-16',
              onChanged: (v) => saved = v,
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextFormField), '2026-11-17');
      expect(saved, '2026-11-17');
      await t.tap(find.byTooltip('Choose Job date'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(saved, '2026-11-17');
    },
  );
}
