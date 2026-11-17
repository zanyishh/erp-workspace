import 'dart:async';
import 'dart:convert';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceContext factoryAccess({
  String company = 'Mill',
  bool configure = true,
  String fingerprint = 'before',
}) => WorkspaceContext.fromJson({
  'company': company,
  'knitting_enabled': true,
  'setup_state': 'Active',
  'can_configure': configure,
  'capabilities': ['jobs', 'factory', if (configure) 'configure'],
  'access_fingerprint': fingerprint,
});

const savedSettings = <String, dynamic>{
  'description': 'Saved description',
  'value': 0,
  'severity': false,
  'boundary_kg': 0,
  'order': 0,
  'unit': 'PCS',
};

Map<String, dynamic> masterRow({
  String name = 'MASTER-1',
  String category = 'Dia',
  String version = 'v2',
}) => {
  'name': name,
  'category': category,
  'title': 'Saved definition',
  'enabled': 0,
  'modified': version,
  'specification': jsonEncode(savedSettings),
};

class FactoryApi extends ErpApi {
  FactoryApi() : super(Uri.parse('http://127.0.0.1:8081'));
  final requests = <Map<String, dynamic>>[];
  final posts = <Map<String, dynamic>>[];
  final lookups = <(String, String, String)>[];
  Completer<Map<String, dynamic>>? delayed;
  List<Map<String, dynamic>>? masterChoices;
  bool wrongCategory = false,
      wrongLookup = false,
      stale = false,
      blankSettings = false;
  WorkspaceContext current = factoryAccess();
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async => current;
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot.fromJson({
    'version': 1,
    'company': company,
    'scope_job': job,
    'pagination': <String, dynamic>{},
    'jobs': <Map<String, dynamic>>[],
  });
  @override
  Future<Map<String, dynamic>> knittingRegister(
    String company,
    String collection, {
    String? job,
    int start = 0,
    String query = '',
    String? state,
    String? productionDate,
    String? fromDate,
    String? toDate,
    String? customer,
    String? category,
  }) async {
    requests.add({
      'company': company,
      'collection': collection,
      'start': start,
      'category': category,
    });
    if (delayed != null && collection == 'masters' && category == 'Dia') {
      return delayed!.future;
    }
    return page(company, collection, start, category);
  }

  Map<String, dynamic> page(
    String company,
    String collection,
    int start,
    String? category,
  ) => {
    'version': 1,
    'company': company,
    'collection': collection,
    'scope_job': null,
    if (collection == 'masters')
      'category': wrongCategory ? 'Fabric' : category,
    'rows': collection == 'masters'
        ? [masterRow(category: category ?? 'Dia', version: 'v1')]
        : collection == 'machines'
        ? [
            {
              'name': 'MACHINE-1',
              'title': 'Independent machine',
              'dia': '30',
              'gauge': '24',
              'knit_type': 'Circular',
              'capacity_kg': '10.000',
              'enabled': 1,
            },
          ]
        : <Map<String, dynamic>>[],
    'page': {
      'start': start,
      'limit': 100,
      'has_more': collection == 'masters' && start == 0,
      'total': collection == 'masters'
          ? 101
          : collection == 'machines'
          ? 1
          : 0,
    },
  };
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    String? job,
    int start = 0,
  }) async {
    lookups.add((company, entity, query));
    return {
      'rows':
          masterChoices ??
          [
            masterRow(name: wrongLookup ? 'OTHER-MASTER' : 'MASTER-1')
              ..['specification'] = blankSettings
                  ? ''
                  : jsonEncode(savedSettings),
          ],
      'has_more': false,
    };
  }

  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posts.add({
      'company': company,
      'action': action,
      'values': jsonDecode(jsonEncode(values)),
    });
    if (stale && posts.length == 1) {
      throw const ErpException('Definition changed.', staleDocument: true);
    }
    return {
      'event': 'SYNTHETIC-MASTER-EDIT',
      'data': {'master': 'MASTER-1'},
    };
  }
}

void desktop(WidgetTester t) {
  t.view.physicalSize = const Size(1440, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> showFactory(
  WidgetTester t,
  FactoryApi api, {
  bool configure = true,
  String company = 'Mill',
}) async {
  api.current = factoryAccess(company: company, configure: configure);
  await t.pumpWidget(
    MaterialApp(
      theme: WorkspaceTheme.theme,
      home: KnittingScreen(
        api: api,
        workspace: api.current,
        onContextChanged: (_) {},
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('Factory').first);
  await t.pumpAndSettle();
}

Future<void> showEdit(WidgetTester t, FactoryApi api) async {
  final row = masterRow();
  await t.pumpWidget(
    MaterialApp(
      theme: WorkspaceTheme.theme,
      home: KnittingCommandForm(
        api: api,
        workspace: factoryAccess(),
        action: knitActions.firstWhere((a) => a.id == 'save_master'),
        initial: {
          'master': 'MASTER-1',
          'category': 'Dia',
          'title': 'Updated name',
          'enabled': false,
          ...savedSettings,
        },
        initialReferences: {'master': row},
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> post(WidgetTester t) async {
  await t.tap(find.text('Review entry'));
  await t.pumpAndSettle();
  await t.tap(find.text('Confirm & post'));
  await t.pumpAndSettle();
}

Future<void> selectCategory(WidgetTester t, String category) async {
  await t.tap(find.byKey(const ValueKey('factory-master-category')));
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text(category).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Factory category pages only masters and retains machine register state',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      await showFactory(t, api);
      expect(
        find.byKey(const ValueKey('factory-master-category')),
        findsOneWidget,
      );
      final machineReads = api.requests
          .where((r) => r['collection'] == 'machines')
          .length;
      await selectCategory(t, 'Dia');
      expect(api.requests.where((r) => r['collection'] == 'masters').last, {
        'company': 'Mill',
        'collection': 'masters',
        'start': 0,
        'category': 'Dia',
      });
      await t.tap(find.byKey(const ValueKey('masters-next')));
      await t.pumpAndSettle();
      expect(
        api.requests.where((r) => r['collection'] == 'masters').last['start'],
        100,
      );
      await selectCategory(t, 'Fabric');
      expect(
        api.requests.where((r) => r['collection'] == 'masters').last['start'],
        0,
      );
      expect(
        api.requests.where((r) => r['collection'] == 'machines').length,
        machineReads,
      );
      expect(
        api.requests
            .where((r) => r['collection'] != 'masters')
            .every((r) => r['category'] == null),
        isTrue,
      );
    },
  );

  testWidgets(
    'direct master editing rereads its version and preserves complete settings',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      await showFactory(t, api);
      await t.tap(find.text('Saved definition'));
      await t.pumpAndSettle();
      expect(api.lookups.single, ('Mill', 'Master', 'MASTER-1'));
      expect(find.text('Sort order'), findsOneWidget);
      expect(find.text('PCS'), findsOneWidget);
      await t.tap(find.text('Edit definition'));
      await t.pumpAndSettle();
      final form = t.widget<KnittingCommandForm>(
        find.byType(KnittingCommandForm),
      );
      expect(form.initialReferences['master']?['modified'], 'v2');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Updated name',
      );
      await post(t);
      final values = api.posts.single['values'] as Map;
      expect(values['master'], 'MASTER-1');
      expect(values['master_modified'], 'v2');
      expect(values['enabled'], false);
      expect(values['title'], 'Updated name');
      expect(values['settings'], savedSettings);
    },
  );

  testWidgets(
    'name-only master edit retains unshown keys and zero or false types',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      await showEdit(t, api);
      await post(t);
      final values = api.posts.single['values'] as Map;
      expect(values['settings'], savedSettings);
      expect((values['settings'] as Map)['value'], isA<int>());
      expect((values['settings'] as Map)['severity'], false);
      expect(values['master_modified'], 'v2');
    },
  );

  for (final description in ['Changed description', '']) {
    testWidgets(
      'master description edit applies without replacing hidden settings: $description',
      (t) async {
        desktop(t);
        final api = FactoryApi();
        addTearDown(api.close);
        await showEdit(t, api);
        await t.enterText(
          find.widgetWithText(TextFormField, 'Description'),
          description,
        );
        await post(t);
        final settings = (api.posts.single['values'] as Map)['settings'] as Map;
        expect(settings['order'], 0);
        expect(settings['unit'], 'PCS');
        expect(settings['value'], 0);
        if (description.isEmpty) {
          expect(settings.containsKey('description'), false);
        } else {
          expect(settings['description'], description);
        }
      },
    );
  }

  testWidgets(
    'changing from a master with hidden settings to an empty master cannot copy those settings',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      api.masterChoices = [
        masterRow(name: 'MASTER-A')
          ..['title'] = 'Definition A'
          ..['specification'] = jsonEncode({'unit': 'PCS', 'order': 0}),
        masterRow(name: 'MASTER-B')
          ..['title'] = 'Definition B'
          ..['specification'] = '{}',
      ];
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: KnittingCommandForm(
            api: api,
            workspace: factoryAccess(),
            action: knitActions.firstWhere((a) => a.id == 'save_master'),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final title in ['Definition A', 'Definition B']) {
        await t.tap(find.text('Existing definition (optional)'));
        await t.pumpAndSettle();
        await t.tap(find.text(title));
        await t.pumpAndSettle();
      }
      await post(t);
      final values = api.posts.single['values'] as Map;
      expect(values['master'], 'MASTER-B');
      expect(values['settings'], isEmpty);
      expect(values.containsKey('unit'), false);
      expect(values.containsKey('order'), false);
    },
  );

  testWidgets(
    'cleared master settings stay cleared after editing and reviewing again',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      await showEdit(t, api);
      await t.enterText(find.widgetWithText(TextFormField, 'Description'), '');
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      await t.tap(find.text('Edit entry'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Updated again',
      );
      await post(t);
      expect(
        ((api.posts.single['values'] as Map)['settings'] as Map).containsKey(
          'description',
        ),
        false,
      );
    },
  );

  testWidgets(
    'a master with no saved settings still opens for a name-only edit',
    (t) async {
      desktop(t);
      final api = FactoryApi()..blankSettings = true;
      addTearDown(api.close);
      await showFactory(t, api);
      await t.tap(find.text('Saved definition'));
      await t.pumpAndSettle();
      await t.tap(find.text('Edit definition'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Empty setting definition',
      );
      await post(t);
      expect((api.posts.single['values'] as Map)['settings'], isEmpty);
    },
  );

  testWidgets('read-only Factory users see master detail without edit', (
    t,
  ) async {
    desktop(t);
    final api = FactoryApi();
    addTearDown(api.close);
    await showFactory(t, api, configure: false);
    await t.tap(find.text('Saved definition'));
    await t.pumpAndSettle();
    expect(find.text('Saved description'), findsOneWidget);
    expect(find.text('Edit definition'), findsNothing);
    expect(api.posts, isEmpty);
  });

  testWidgets('master detail never edits a different lookup result', (t) async {
    desktop(t);
    final api = FactoryApi()..wrongLookup = true;
    addTearDown(api.close);
    await showFactory(t, api);
    await t.tap(find.text('Saved definition'));
    await t.pumpAndSettle();
    expect(find.text('Edit definition'), findsNothing);
    expect(find.textContaining('no longer available'), findsOneWidget);
  });

  testWidgets(
    'old category responses and mismatched category echoes stay hidden',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      await showFactory(t, api);
      api.delayed = Completer();
      await t.tap(find.byKey(const ValueKey('factory-master-category')));
      await t.pumpAndSettle();
      await t.tap(find.text('Dia').last);
      await t.pump();
      await selectCategory(t, 'Fabric');
      api.delayed!.complete({
        ...api.page('Mill', 'masters', 0, 'Dia'),
        'rows': [
          masterRow(name: 'STALE-MASTER')..['title'] = 'Stale definition',
        ],
      });
      await t.pumpAndSettle();
      expect(find.text('Stale definition'), findsNothing);
      api.wrongCategory = true;
      await selectCategory(t, 'Gauge');
      expect(find.text('Saved definition'), findsNothing);
      expect(find.textContaining('unexpected page'), findsOneWidget);
    },
  );

  testWidgets(
    'access change hides cached master detail and requires a fresh form source',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      api.publishContext(factoryAccess());
      await showFactory(t, api);
      await t.tap(find.text('Saved definition'));
      await t.pumpAndSettle();
      expect(find.text('Saved description'), findsOneWidget);
      api.current = factoryAccess(configure: false, fingerprint: 'after');
      api.publishContext(api.current);
      await t.pumpAndSettle();
      expect(find.text('Saved description'), findsNothing);
      expect(find.text('Edit definition'), findsNothing);
      expect(api.posts, isEmpty);
    },
  );

  testWidgets(
    'master review requires a fresh definition after access refresh',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      api.publishContext(factoryAccess());
      await showEdit(t, api);
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.text('Confirm & post'), findsOneWidget);
      api.publishContext(factoryAccess(fingerprint: 'after'));
      await t.pumpAndSettle();
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.text('Confirm & post'), findsNothing);
      expect(
        find.textContaining('Select the current definition again'),
        findsOneWidget,
      );
      expect(api.posts, isEmpty);
    },
  );

  testWidgets(
    'company change resets the Factory category before loading masters',
    (t) async {
      desktop(t);
      final api = FactoryApi();
      addTearDown(api.close);
      await showFactory(t, api);
      await selectCategory(t, 'Dia');
      await showFactory(t, api, company: 'Other');
      expect(api.requests.where((r) => r['collection'] == 'masters').last, {
        'company': 'Other',
        'collection': 'masters',
        'start': 0,
        'category': null,
      });
      expect(find.text('All categories'), findsOneWidget);
    },
  );

  testWidgets(
    'Factory categories and saved settings fit a short phone with larger text',
    (t) async {
      t.view.physicalSize = const Size(360, 510);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = FactoryApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: KnittingScreen(
            api: api,
            workspace: factoryAccess(),
            onContextChanged: (_) {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Open navigation menu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Factory').last);
      await t.pumpAndSettle();
      Future<void> reveal(Finder target) async {
        for (
          var i = 0;
          i < 30 && target.hitTestable().evaluate().isEmpty;
          i++
        ) {
          await t.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -180),
          );
          await t.pumpAndSettle();
        }
        expect(target.hitTestable(), findsOneWidget);
      }

      await reveal(find.byKey(const ValueKey('factory-master-category')));
      expect(t.takeException(), isNull);
      await reveal(find.text('Saved definition'));
      await t.tap(find.text('Saved definition'));
      await t.pumpAndSettle();
      expect(find.text('Saved description'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'stale master reload cannot turn an update into new-master creation',
    (t) async {
      desktop(t);
      final api = FactoryApi()..stale = true;
      addTearDown(api.close);
      await showEdit(t, api);
      await post(t);
      await t.tap(find.text('Reload current sources'));
      await t.pumpAndSettle();
      await t.tap(find.text('Review entry'));
      await t.pumpAndSettle();
      expect(find.text('Confirm & post'), findsNothing);
      expect(
        find.textContaining('Select the current definition again'),
        findsOneWidget,
      );
      expect(api.posts.length, 1);
    },
  );
}
