import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/native_models.dart';

NativeSchema rowSchema() => NativeSchema.fromJson({
  'doctype': 'Example',
  'fields': [
    {
      'fieldname': 'rows',
      'label': 'Items',
      'fieldtype': 'Table',
      'options': 'Item Row',
    },
  ],
  'children': {
    'Item Row': {
      'doctype': 'Item Row',
      'fields': [
        {'fieldname': 'item_code', 'label': 'Item', 'fieldtype': 'Data'},
      ],
    },
  },
});

Future<void> showRows(
  WidgetTester tester,
  Map<String, dynamic> data, {
  RowDefaults? onNewRow,
  ItemDefaults? onItemDefaults,
  bool editable = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => DocumentFields(
            schema: rowSchema(),
            data: data,
            editable: editable,
            onChanged: () => update(() {}),
            onNewRow: onNewRow,
            onItemDefaults: onItemDefaults,
          ),
        ),
      ),
    ),
  );
}

Future<void> showScalar(
  WidgetTester tester,
  String type,
  String initial,
  ValueChanged<Object?> changed,
) async {
  Object? value = initial;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => NativeScalarField(
            field: NativeField.fromJson({
              'fieldname': 'scheduled',
              'label': 'Scheduled',
              'fieldtype': type,
            }),
            value: value,
            editable: true,
            onChanged: (next) {
              update(() => value = next);
              changed(next);
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a failed row defaults request can be retried in place', (
    tester,
  ) async {
    var attempts = 0;
    final data = <String, dynamic>{'rows': []};
    await showRows(
      tester,
      data,
      onNewRow: (_, _) async {
        if (++attempts == 1) throw StateError('Connection interrupted');
        return {'item_code': 'RECOVERED'};
      },
    );
    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry loading row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((data['rows'] as List).single['item_code'], 'RECOVERED');
    expect(attempts, 2);
  });

  testWidgets(
    'the date picker opens for manually typed years outside its range',
    (tester) async {
      await showScalar(tester, 'Date', '2600-01-01', (_) {});
      await tester.tap(find.byTooltip('Choose Scheduled'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('2600-01-01'), findsOneWidget);
    },
  );

  testWidgets('rapid Add clicks open only one row draft', (tester) async {
    final pending = <Completer<Map<String, dynamic>>>[];
    final data = <String, dynamic>{'rows': <Map<String, dynamic>>[]};
    await showRows(
      tester,
      data,
      onNewRow: (_, _) {
        final load = Completer<Map<String, dynamic>>();
        pending.add(load);
        return load.future;
      },
    );
    final add = tester
        .widget<TextButton>(
          find.ancestor(
            of: find.text('Add row'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          ),
        )
        .onPressed!;
    add();
    add();
    await tester.pump();
    final calls = pending.length;
    for (final load in pending) {
      load.complete({'doctype': 'Item Row', 'item_code': 'First'});
    }
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((data['rows'] as List).map((row) => row['item_code']), ['First']);
  });

  testWidgets('new row accepts against the latest parent rows', (tester) async {
    final load = Completer<Map<String, dynamic>>();
    final data = <String, dynamic>{
      'rows': [
        {'item_code': 'Original'},
      ],
    };
    await showRows(tester, data, onNewRow: (_, _) => load.future);
    await tester.tap(find.text('Add row'));
    data['rows'] = [
      ...(data['rows'] as List),
      {'item_code': 'Concurrent'},
    ];
    load.complete({'doctype': 'Item Row', 'item_code': 'Added'});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((data['rows'] as List).map((row) => row['item_code']), [
      'Original',
      'Concurrent',
      'Added',
    ]);
  });

  testWidgets('editing finds the same row after its position changes', (
    tester,
  ) async {
    final original = {'name': 'ROW-1', 'item_code': 'Original'};
    final data = <String, dynamic>{
      'rows': [original],
    };
    await showRows(tester, data);
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    data['rows'] = [
      {'name': 'ROW-2', 'item_code': 'Inserted'},
      original,
    ];
    await tester.enterText(find.byType(TextFormField), 'Edited');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((data['rows'] as List).map((row) => row['item_code']), [
      'Inserted',
      'Edited',
    ]);
  });

  testWidgets('Close asks before discarding a changed row', (tester) async {
    final data = <String, dynamic>{
      'rows': [
        {'item_code': 'Original'},
      ],
    };
    await showRows(tester, data);
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Changed');
    await tester.tap(find.byTooltip('Close row'));
    await tester.pumpAndSettle();
    expect(find.text('Keep editing'), findsOneWidget);
    expect((data['rows'] as List).single['item_code'], 'Original');
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Changed'), findsOneWidget);
    await tester.tap(find.byTooltip('Close row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close row'), findsNothing);
    expect((data['rows'] as List).single['item_code'], 'Original');
  });

  testWidgets('system back asks before discarding a changed row', (
    tester,
  ) async {
    final data = <String, dynamic>{
      'rows': [
        {'item_code': 'Original'},
      ],
    };
    await showRows(tester, data);
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Changed');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Changed'), findsOneWidget);
  });

  testWidgets('untouched editable and read only rows close without a warning', (
    tester,
  ) async {
    for (final editable in [true, false]) {
      await showRows(tester, {
        'rows': [
          {'item_code': 'Original'},
        ],
      }, editable: editable);
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close row'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close row'), findsNothing);
      expect(find.text('Discard changes'), findsNothing);
    }
  });

  testWidgets('row defaults remain guarded until the request finishes', (
    tester,
  ) async {
    final load = Completer<Map<String, dynamic>>();
    await showRows(tester, {'rows': []}, onNewRow: (_, _) => load.future);
    await tester.tap(find.text('Add row'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Close row'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    load.complete({'doctype': 'Item Row', 'item_code': 'Loaded'});
    await tester.pumpAndSettle();
    expect(find.text('Loaded'), findsOneWidget);
    expect(find.byTooltip('Close row'), findsOneWidget);
    await tester.tap(find.byTooltip('Close row'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes'), findsNothing);
  });

  testWidgets('loaded item changes are guarded after a pending request', (
    tester,
  ) async {
    final load = Completer<Map<String, dynamic>>();
    final data = <String, dynamic>{
      'rows': [
        {'item_code': 'Original'},
      ],
    };
    await showRows(tester, data, onItemDefaults: (_, _, _) => load.future);
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load item details'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    load.complete({'item_code': 'Loaded'});
    await tester.pumpAndSettle();
    expect(find.text('Loaded'), findsOneWidget);
    await tester.tap(find.byTooltip('Close row'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes'), findsOneWidget);
    expect((data['rows'] as List).single['item_code'], 'Original');
  });

  testWidgets('changing a datetime date preserves its existing time', (
    tester,
  ) async {
    Object? result;
    await showScalar(tester, 'Datetime', '2026-11-12 15:42:17', (value) {
      result = value;
    });
    await tester.tap(find.byTooltip('Choose Scheduled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, '2026-11-13 15:42:17');
  });

  for (final type in ['Time', 'Datetime']) {
    testWidgets('$type picker selects time without changing the date', (
      tester,
    ) async {
      Object? result;
      await showScalar(
        tester,
        type,
        type == 'Time' ? '09:15:00' : '2026-11-12 09:15:00',
        (value) => result = value,
      );
      await tester.tap(
        find.byTooltip(
          type == 'Time' ? 'Choose Scheduled' : 'Choose Scheduled time',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(inputs.at(0), '18');
      await tester.enterText(inputs.at(1), '25');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, type == 'Time' ? '18:25:00' : '2026-11-12 18:25:00');
    });
  }
}
