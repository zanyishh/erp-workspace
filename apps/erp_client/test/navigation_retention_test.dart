import 'package:erp_client/widgets.dart';

import 'dart:async';

import 'package:erp_client/design.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/invoice_composer.dart';
import 'package:erp_client/local_workspace.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/module_browser.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _NavigationApi extends ErpApi {
  _NavigationApi() : super(Uri.parse('http://127.0.0.1:8081'));
  Completer<ErpSnapshot>? pendingOverview;
  final requests = <(String, int)>[];
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      WorkspaceContext.fromJson({
        'company': 'Test Mill',
        'companies': [
          {'name': 'Test Mill'},
        ],
        'can_manage_team': true,
        'readable_records': ['Item', 'Sales Invoice'],
        'creatable_records': ['Sales Invoice'],
      });
  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async =>
      pendingOverview?.future ??
      ErpSnapshot(
        company: 'Test Mill',
        currency: 'INR',
        counts: {ErpModule.stock: 100, ErpModule.accounts: 2},
      );
  @override
  Future<Map<String, dynamic>> invoiceDefaults(String company) async => {
    'posting_date': '2026-11-17',
  };
  @override
  Future<NativeCatalog> nativeCatalog({String? company}) async =>
      NativeCatalog.fromJson({'version': 1, 'types': [], 'reports': []});
  @override
  Future<List<ErpRecord>> records(
    ErpModule module, {
    required String company,
    ReportingPeriod period = ReportingPeriod.month,
    DateTime? now,
    String query = '',
    int start = 0,
    int limit = 50,
    bool unpaidOnly = false,
  }) async {
    requests.add((query, start));
    return List.generate(
      50,
      (i) => ErpRecord({
        'name': 'ITEM-${start + i}',
        'item_name': 'Cotton ${start + i}',
      }, module),
    );
  }

  @override
  Future<NativeSchema> nativeSchema(String doctype) async =>
      NativeSchema.fromJson({
        'doctype': doctype,
        'fields': [
          {'fieldname': 'item_name', 'label': 'Item name', 'fieldtype': 'Data'},
        ],
      });
  @override
  Future<NativeDocument> nativeDocument(
    String doctype, {
    String? name,
    String? company,
    String? treeParent,
  }) async => NativeDocument.fromJson({
    'doc': {
      'doctype': doctype,
      'name': name,
      'item_name': name,
      'modified': 'v1',
    },
    'permissions': {'read': true},
  });
}

void main() {
  Future<_NavigationApi> open(
    WidgetTester t, {
    TargetPlatform platform = TargetPlatform.macOS,
    Size size = const Size(1280, 900),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = _NavigationApi();
    await t.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme.copyWith(platform: platform),
        home: WorkspaceShell(
          openLocal: () async => LocalWorkspace(api, 'Test Mill'),
        ),
      ),
    );
    await t.pumpAndSettle();
    return api;
  }

  testWidgets('iOS edge swipe closes the catalog and preserves the overview', (
    t,
  ) async {
    await open(t, platform: TargetPlatform.iOS, size: const Size(390, 844));
    await t.tap(find.text('All modules'));
    await t.pumpAndSettle();
    expect(find.byType(NativeCatalogScreen), findsOneWidget);
    final gesture = await t.startGesture(const Offset(2, 350));
    await gesture.moveBy(const Offset(40, 0));
    await t.pump();
    await gesture.moveBy(const Offset(230, 0));
    await t.pump();
    expect(
      t.state<NavigatorState>(find.byType(Navigator)).userGestureInProgress,
      isTrue,
    );
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.byType(OverviewScreen), findsOneWidget);
    expect(find.byType(NativeCatalogScreen), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'a rotated phone retains touch navigation and the selected workspace',
    (t) async {
      await open(t, platform: TargetPlatform.iOS, size: const Size(844, 390));
      expect(t.getTopLeft(find.text('BILLED SALES')).dy, lessThan(220));
      expect(t.getTopLeft(find.text('INVENTORY')).dx, greaterThan(400));
      expect(
        t.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
        isNotNull,
      );
      await t.tap(find.text('Workspaces'));
      await t.pumpAndSettle();
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isFalse);
      expect(
        t
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Business overview'),
            )
            .selected,
        isTrue,
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Search workspaces'),
        'Stock',
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.widgetWithText(ListTile, 'Stock'));
      await t.tap(find.widgetWithText(ListTile, 'Stock'));
      await t.pumpAndSettle();
      await t.tap(find.text('Workspaces'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Search workspaces'),
        'Stock',
      );
      await t.pumpAndSettle();
      expect(
        t.widget<ListTile>(find.widgetWithText(ListTile, 'Stock')).selected,
        isTrue,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop toolbar follows the overview grid and shows company once',
    (t) async {
      await open(t);
      expect(find.text('Test Mill'), findsOneWidget);
      final header = find
          .ancestor(of: find.text('General ERP'), matching: find.byType(Panel))
          .first;
      final gutter = t.getTopLeft(find.text('BUSINESS OVERVIEW')).dx;
      expect(t.getRect(header).left, closeTo(gutter, 1));
      expect(t.getRect(header).right, closeTo(1280 - gutter, 1));
    },
  );

  for (final (platform, size) in [
    (TargetPlatform.android, const Size(320, 640)),
    (TargetPlatform.iOS, const Size(390, 844)),
  ]) {
    testWidgets(
      '$platform phone navigation works above the home indicator and keyboard',
      (t) async {
        t.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(t.view.resetPadding);
        addTearDown(t.view.resetViewInsets);
        final api = await open(t, platform: platform, size: size);
        expect(find.text('Test Mill'), findsOneWidget);
        expect(
          t.getTopLeft(find.byIcon(Icons.business_outlined)).dx,
          t.getTopLeft(find.text('BUSINESS OVERVIEW')).dx,
        );
        final browse = find.text('Workspaces');
        final all = find.text('All modules');
        expect(all.hitTestable(), findsOneWidget);
        expect(t.getCenter(browse).dy, greaterThan(size.height / 2));
        expect(t.getRect(all).bottom, lessThanOrEqualTo(size.height - 24));

        final overviewScroll = find
            .descendant(
              of: find.byType(OverviewScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        await t.drag(overviewScroll, const Offset(0, -300));
        await t.pumpAndSettle();
        final offset = t.state<ScrollableState>(overviewScroll).position.pixels;
        expect(offset, greaterThan(0));
        await t.tap(browse);
        await t.pumpAndSettle();
        expect(t.testTextInput.isVisible, isFalse);
        await t.enterText(find.byType(TextField), 'Item');
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpAndSettle();
        final stock = find.widgetWithText(ListTile, 'Stock');
        await t.ensureVisible(stock);
        await t.tap(stock);
        await t.pumpAndSettle();
        expect(all, findsNothing);
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        expect(find.byType(ModuleBrowser), findsOneWidget);
        expect(find.text('Test Mill'), findsOneWidget);
        await t.enterText(find.byType(TextField), 'Cotton');
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pump(const Duration(milliseconds: 400));
        await t.pumpAndSettle();
        expect(api.requests.last, ('Cotton', 0));
        expect(all, findsNothing);
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Back to business overview'));
        await t.pumpAndSettle();
        expect(
          t.state<ScrollableState>(overviewScroll).position.pixels,
          closeTo(offset, 1),
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Accounts creates invoices in the company composer and opens existing records in the editor',
    (t) async {
      final api = await open(t);
      await t.tap(find.text('Workspaces'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ListTile, 'Accounts'));
      await t.pumpAndSettle();
      await t.tap(find.text('New sales invoice'));
      await t.pumpAndSettle();
      final composer = t.widget<InvoiceComposer>(find.byType(InvoiceComposer));
      expect(composer.api, same(api));
      expect(composer.company, 'Test Mill');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await t.tap(find.text('ITEM-0').last);
      await t.pumpAndSettle();
      final editor = t.widget<DocumentEditor>(find.byType(DocumentEditor));
      expect(editor.doctype, 'Sales Invoice');
      expect(editor.name, 'ITEM-0');
      expect(editor.company, 'Test Mill');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'opening a record preserves query page and scroll while shell refreshes',
    (t) async {
      final api = await open(t);
      t
          .widget<OverviewScreen>(find.byType(OverviewScreen))
          .onModule(ErpModule.stock);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Cotton');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Next page'));
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, -350));
      await t.pumpAndSettle();
      final browserState = t.state(find.byType(ModuleBrowser));
      final scrollable = find.descendant(
        of: find.descendant(
          of: find.byType(ModuleBrowser),
          matching: find.byType(ListView),
        ),
        matching: find.byType(Scrollable),
      );
      final offset = t.state<ScrollableState>(scrollable).position.pixels;
      final target =
          find
                  .byWidgetPredicate((w) => w is InkWell && w.onTap != null)
                  .hitTestable()
                  .evaluate()
                  .where(
                    (e) => e.findAncestorWidgetOfExactType<ListView>() != null,
                  )
                  .first
                  .widget
              as InkWell;
      final sourceFocus = target.focusNode;
      target.onTap!();
      await t.pumpAndSettle();
      expect(find.byType(DocumentEditor), findsOneWidget);
      api.pendingOverview = Completer<ErpSnapshot>();
      await t.pageBack();
      await t.pump(const Duration(milliseconds: 350));
      expect(find.byType(ModuleBrowser), findsOneWidget);
      expect(t.state(find.byType(ModuleBrowser)), same(browserState));
      expect(
        t
            .widget<TextField>(
              find.descendant(
                of: find.byType(ModuleBrowser),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'Cotton',
      );
      expect(find.text('Showing 51–100'), findsOneWidget);
      expect(t.state<ScrollableState>(scrollable).position.pixels, offset);
      api.pendingOverview!.complete(
        ErpSnapshot(
          company: 'Test Mill',
          currency: 'INR',
          counts: {ErpModule.stock: 100},
        ),
      );
      await t.pumpAndSettle();
      expect(api.requests.last, ('Cotton', 50));
      expect(sourceFocus, isNotNull);
      expect(FocusManager.instance.primaryFocus, same(sourceFocus));
      expect(t.state(find.byType(ModuleBrowser)), same(browserState));
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets(
      '$platform command shortcut opens picker and Escape restores focus',
      (t) async {
        await open(t, platform: platform);
        t
            .widget<OverviewScreen>(find.byType(OverviewScreen))
            .onModule(ErpModule.stock);
        await t.pumpAndSettle();
        await t.tap(find.byType(TextField));
        await t.pumpAndSettle();
        final invokingFocus = FocusManager.instance.primaryFocus;
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await t.sendKeyDownEvent(modifier);
        await t.sendKeyEvent(LogicalKeyboardKey.keyK);
        await t.sendKeyUpEvent(modifier);
        await t.pumpAndSettle();
        expect(find.text('Search workspaces'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('Search workspaces'), findsNothing);
        expect(FocusManager.instance.primaryFocus, same(invokingFocus));
      },
    );
  }
}
