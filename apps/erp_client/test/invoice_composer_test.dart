import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_composer.dart';

class ComposerApi extends ErpApi {
  ComposerApi() : super(Uri.parse('http://localhost:8081'));
  final saves = <String>[];
  final reviewedStyles = <String>[];
  @override
  Future<List<Map<String, dynamic>>> searchLinks(
    String doctype,
    String query, {
    String? parent,
    String? field,
    Map<String, String>? contextValues,
  }) async {
    if (doctype == 'Item' &&
        parent == 'Sales Invoice' &&
        field == 'item_code' &&
        contextValues?['company'] == 'Test mill') {
      return [
        {'value': 'YARN-30', 'description': 'Combed yarn'},
      ];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> invoiceDefaults(String company) async => {
    'posting_date': '2026-11-14',
    'currency': 'INR',
    'template_id': 'cobalt',
  };
  @override
  Future<Map<String, dynamic>> reviewInvoice(Map<String, Object?> d) async {
    reviewedStyles.add(d['template_id'] as String);
    return {
      'review': 'current',
      'due_date': '2026-11-18',
      'currency': 'INR',
      'precision': 2,
      'net_total': '120',
      'grand_total': '132',
      'rounded_total': '132',
      'rounding_adjustment': '0',
      'taxes': [
        {'label': 'Sales tax', 'amount': '12'},
      ],
      'items': [
        {'qty': '2', 'uom': 'Nos', 'rate': '60', 'amount': '120'},
      ],
    };
  }

  @override
  Future<String> saveInvoiceDraft(
    Map<String, Object?> d,
    String key,
    String review,
  ) async {
    saves.add(key);
    if (saves.length == 1) throw const ErpException('Connection interrupted.');
    return 'SINV-1';
  }
}

void main() {
  testWidgets('typing an item keeps focus until the operator presses Next', (
    t,
  ) async {
    final api = ComposerApi();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: InvoiceComposer(api: api, company: 'Test mill'),
      ),
    );
    await t.pumpAndSettle();
    final item = find.widgetWithText(TextFormField, 'Item or service');
    final quantity = find.widgetWithText(TextFormField, 'Quantity');
    FocusNode focus(Finder field) => t
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .focusNode;
    await t.ensureVisible(item);
    await t.tap(item);
    for (final prefix in ['Y', 'YA', 'YARN-24']) {
      t.testTextInput.enterText(prefix);
      await t.pumpAndSettle();
      expect(focus(item).hasPrimaryFocus, isTrue);
    }
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    expect(focus(quantity).hasPrimaryFocus, isTrue);
    expect(find.text('YARN-24'), findsOneWidget);
  });
  testWidgets(
    'item lookup uses selling filters and selection advances to quantity',
    (t) async {
      final api = ComposerApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          home: InvoiceComposer(api: api, company: 'Test mill'),
        ),
      );
      await t.pumpAndSettle();
      final lookup = find.byTooltip('Find Item or service');
      await t.ensureVisible(lookup);
      await t.tap(lookup);
      await t.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Search records…');
      await t.enterText(search, 'YARN-30');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      final quantity = find.widgetWithText(TextFormField, 'Quantity');
      final editable = find.descendant(
        of: quantity,
        matching: find.byType(EditableText),
      );
      expect(
        t.widget<EditableText>(editable).focusNode.hasPrimaryFocus,
        isTrue,
      );
      expect(find.text('YARN-30'), findsOneWidget);
    },
  );

  testWidgets(
    'phone entry retains optional details and moves from quantity to rate',
    (t) async {
      final api = ComposerApi();
      addTearDown(api.close);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 690);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        MaterialApp(
          home: InvoiceComposer(
            api: api,
            company: 'Sample company',
            templateId: 'grove',
          ),
        ),
      );
      await t.pumpAndSettle();
      final quantity = find.widgetWithText(TextFormField, 'Quantity');
      final rate = find.widgetWithText(TextFormField, 'Rate override');
      await t.ensureVisible(quantity);
      await t.tap(quantity);
      await t.enterText(quantity, '3');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      bool focused(Finder field) => t
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus;
      expect(focused(rate), isTrue);
      expect(t.getTopLeft(rate).dy, greaterThan(t.getBottomLeft(quantity).dy));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();

      final more = find.text('More details');
      await t.ensureVisible(more);
      await t.tap(more);
      await t.pumpAndSettle();
      expect(find.text('Olive Grove'), findsOneWidget);
      await t.tap(more);
      await t.pumpAndSettle();
      expect(find.text('Olive Grove'), findsNothing);
      await t.ensureVisible(find.text('Review invoice'));
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      expect(focused(find.widgetWithText(TextFormField, 'Customer')), isTrue);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'review edits, retain the selected style, retry the exact save and return the created invoice',
    (t) async {
      final api = ComposerApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(1000, 1250);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      String? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                child: const Text('Create'),
                onPressed: () async {
                  result = await Navigator.push<String>(
                    c,
                    MaterialPageRoute(
                      builder: (_) => InvoiceComposer(
                        api: api,
                        company: 'Sample company',
                        templateId: 'grove',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Create'));
      await t.pumpAndSettle();
      expect(find.text('Olive Grove'), findsOneWidget);
      await t.tap(find.text('Review invoice'));
      await t.pump();
      expect(find.textContaining('Choose a customer'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Customer'),
        'Sample customer',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Item or service'),
        'Service',
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Quantity'), '2');
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      expect(find.text('INR 132.00'), findsOneWidget);
      expect(find.text('Sales tax'), findsOneWidget);
      await t.tap(find.text('Save draft'));
      await t.pumpAndSettle();
      expect(find.text('Retry same save'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Quantity'),
            )
            .enabled,
        false,
      );
      await t.tap(find.text('Retry same save'));
      await t.pumpAndSettle();
      expect(result, 'SINV-1');
      expect(api.reviewedStyles.last, 'grove');
      expect(api.saves.length, 2);
      expect(api.saves[0], api.saves[1]);
    },
  );

  testWidgets(
    'ordinary drafts follow the company default and can explicitly choose Trade Ledger',
    (t) async {
      final api = ComposerApi();
      addTearDown(api.close);
      t.view.physicalSize = const Size(1000, 1250);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: InvoiceComposer(api: api, company: 'Sample company'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Company default · Cobalt Fold'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Customer'),
        'Sample customer',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Item or service'),
        'Service',
      );
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      expect(api.reviewedStyles.last, '');
      await t.tap(find.text('Company default · Cobalt Fold'));
      await t.pumpAndSettle();
      await t.tap(find.text('Trade Ledger').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Review invoice'));
      await t.pumpAndSettle();
      expect(api.reviewedStyles.last, 'ledger');
    },
  );
}
