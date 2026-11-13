// From apps/erp_client: flutter run -d macos --profile --no-pub -t tool/profile_workspace.dart
// The app exits after writing each measured scenario to stdout as JSON.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/main.dart' show WorkspaceShell;
import 'package:erp_client/sign_in.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' show LiveWidgetController, find;

const company = 'Sample mill';

class _FixtureApi extends ErpApi {
  _FixtureApi() : super(Uri.parse('https://native-test.localhost'));

  final workspace = WorkspaceContext.fromJson({
    'company': company,
    'knitting_enabled': true,
    'setup_state': 'Active',
    'capabilities': [
      'overview',
      'jobs',
      'materials',
      'planning',
      'production',
      'quality',
      'delivery',
      'billing',
      'factory',
      'reports',
    ],
  });
  final mill = KnittingSnapshot(company, {
    'jobs': [
      for (var i = 0; i < 200; i++)
        {
          'name': 'JOB-${i.toString().padLeft(3, '0')}',
          'customer': 'Sample customer ${i % 12}',
          'due_date': '2026-11-22',
          'material_mode': i.isEven ? 'Customer' : 'Owned',
          'status': i % 3 == 0 ? 'Completed' : 'Running',
          'target_kg': '${150 + i}.000',
          'balances': {
            'produced_kg': '${100 + i}.125',
            'yarn_kg': '20.000',
            'unbilled_kg': '30.000',
          },
        },
    ],
    'events': [
      for (var i = 0; i < 500; i++)
        {
          'name': 'POST-$i',
          'job': 'JOB-${(i % 200).toString().padLeft(3, '0')}',
          'occurred_at':
              '2026-11-${(i % 7 + 7).toString().padLeft(2, '0')} 12:00:00',
          'kind': 'produce',
          'result': {'quantity_kg': '${10 + i % 20}.125'},
        },
    ],
    'rolls': [
      for (var i = 0; i < 500; i++)
        {
          'state': ['Awaiting QC', 'Released', 'On Hold'][i % 3],
        },
    ],
    'plans': [
      for (var i = 0; i < 200; i++) {'state': 'Planned'},
    ],
  });
  @override
  Future<void> login(String username, String password) async {}
  @override
  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      workspace;
  @override
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => mill;
  @override
  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async {
    final range = period.range(DateTime.now());
    final sales = [
      for (
        var date = range.start;
        date.isBefore(range.end);
        date = DateTime(date.year, date.month, date.day + 1)
      )
        SalesDay(date, (date.day * 17 % 23 + 3) * 930.25),
    ];
    return ErpSnapshot(
      company: company,
      currency: 'INR',
      sales: sales,
      counts: {
        for (final module in ErpModule.values) module: module.index * 11 + 9,
      },
      warehouses: 14,
      billed: sales.fold<double>(0, (sum, day) => sum + day.amount),
      unpaidInvoices: 3,
      activity: [
        for (var i = 0; i < 4; i++)
          ErpRecord({
            'name': 'INV-$i',
            'customer_name': 'Sample customer $i',
            'grand_total': i * 400.25,
            'currency': 'INR',
            'status': 'Paid',
          }, ErpModule.accounts),
      ],
    );
  }
}

void _emit(Map<String, dynamic> row) =>
    debugPrintSynchronously('WORKSPACE_PROFILE ${jsonEncode(row)}');

Future<void> main() async {
  try {
    if (kDebugMode) throw StateError('Use a profile or release build.');
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      exit(1);
    };
    await _profile().timeout(const Duration(seconds: 100));
    _emit({'complete': true});
    await stdout.flush();
    exit(0);
  } catch (error, trace) {
    debugPrintSynchronously('WORKSPACE_PROFILE_FAILED $error\n$trace');
    exit(1);
  }
}

Future<void> _profile() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  final api = _FixtureApi();
  final timings = <FrameTiming>[];
  binding.addTimingsCallback(timings.addAll);
  runApp(
    MaterialApp(
      theme: WorkspaceTheme.theme,
      home: WorkspaceShell(connect: (_) => api),
    ),
  );
  await binding.waitUntilFirstFrameRasterized;
  await Future<void>.delayed(const Duration(seconds: 1));
  final view = binding.platformDispatcher.views.single;
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    _emit({
      'waiting_for_visible_window': true,
      'lifecycle': binding.lifecycleState?.name,
    });
    while (binding.lifecycleState != AppLifecycleState.resumed) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  // Give macOS time to restore the window geometry after bringing it forward.
  await Future<void>.delayed(const Duration(seconds: 2));
  final logicalSize = view.physicalSize / view.devicePixelRatio;
  _emit({
    'mode': kProfileMode ? 'profile' : 'release',
    'os': Platform.operatingSystemVersion,
    'width': logicalSize.width,
    'height': logicalSize.height,
    'lifecycle': binding.lifecycleState?.name,
    'dpr': view.devicePixelRatio,
    'display_hz': view.display.refreshRate,
    'jobs': 200,
    'postings': 500,
  });

  int frame() => binding.platformDispatcher.frameData.frameNumber;
  Future<void> measure(
    String scenario,
    Future<void> Function() act, {
    int atLeast = 1,
  }) async {
    final start = frame();
    await act();
    final end = frame();
    // Profile/release engines batch reports, so use engine frame IDs for attribution.
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    final frames = timings
        .where((f) => f.frameNumber > start && f.frameNumber <= end)
        .toList();
    if (frames.length < atLeast) {
      throw StateError(
        '$scenario: ${frames.length} measured frames (expected >= $atLeast, IDs $start..$end)',
      );
    }
    Map<String, dynamic> stats(Duration Function(FrameTiming) get) {
      final us = frames.map((f) => get(f).inMicroseconds).toList()..sort();
      double percentile(double p) => us[(p * us.length).ceil() - 1] / 1000;
      return {
        'p50': percentile(.5),
        'p95': percentile(.95),
        'max': us.last / 1000,
      };
    }

    _emit({
      'scenario': scenario,
      'frames': frames.length,
      'build_ms': stats((f) => f.buildDuration),
      'raster_ms': stats((f) => f.rasterDuration),
      'either_stage_over_16_67_ms': frames
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > 16667 ||
                f.rasterDuration.inMicroseconds > 16667,
          )
          .length,
    });
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 700));
  await measure('mill_first_open', () async {
    await controller
        .widget<SignInScreen>(find.byType(SignInScreen))
        .onSignIn('https://native-test.localhost', 'synthetic', 'synthetic');
    await settle();
  });
  final bars = [
    for (var day = 7; day <= 13; day++) find.byTooltip(RegExp('^Nov $day · ')),
  ];
  await Scrollable.ensureVisible(controller.element(bars.first), alignment: .5);
  await settle();
  final selected = find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        w.properties.selected == true &&
        (w.properties.label?.startsWith('Nov ') ?? false),
  );
  Future<void> selectBars(int count) async {
    for (var i = 0; i < count; i++) {
      // Selection rebuilds the bar, so resolve its current action each time.
      final bar = bars[i % bars.length];
      controller
          .widget<InkWell>(
            find.descendant(of: bar, matching: find.byType(InkWell)),
          )
          .onTap!();
      await Future<void>.delayed(const Duration(milliseconds: 230));
      final label = controller.widget<Semantics>(selected).properties.label!;
      if (!label.startsWith('Nov ${7 + i % bars.length} · ')) {
        throw StateError('Production selection ended on $label after step $i.');
      }
    }
  }

  await selectBars(3);
  await measure(
    'production_day_selection_callback',
    () => selectBars(18),
    atLeast: 18,
  );
  await measure('jobs_first_open', () async {
    await controller.tap(find.text('Jobs'));
    await settle();
  });
  _emit({
    'mounted_jobs_on_open': find
        .textContaining(RegExp(r'^JOB-\d{3}$'), skipOffstage: false)
        .evaluate()
        .length,
  });
  final scroll = controller
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(KnittingWorkbench),
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      )
      .position;
  if (scroll.maxScrollExtent < 2000) {
    throw StateError('Expected a long job register.');
  }
  Future<void> scrollTo(double offset, int ms) => scroll.animateTo(
    offset,
    duration: Duration(milliseconds: ms),
    curve: Curves.linear,
  );
  await scrollTo(650, 350);
  await scrollTo(0, 350);
  await measure('job_register_scroll', () async {
    // Recheck the extent after travel since lazy lists refine their estimates.
    await scrollTo(scroll.maxScrollExtent, 2500);
    await scrollTo(scroll.maxScrollExtent, 125);
    if (find.text('JOB-199').evaluate().isEmpty) {
      throw StateError('Final job did not render.');
    }
    await scrollTo(0, 2500);
  }, atLeast: 60);
  await measure('general_first_open', () async {
    await controller.tap(find.text('General ERP'));
    await settle();
  });
  // Use thirty days even when this is run on the first of a calendar month.
  await controller.tap(find.text('This month'));
  await settle();
  await controller.tap(find.text('Last 30 days'));
  await settle();
  final plot = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Daily sales chart',
  );
  await Scrollable.ensureVisible(controller.element(plot), alignment: .5);
  await settle();
  Future<void> selectSales(int count) async {
    const points = [.05, .30, .55, .80, .95];
    for (var i = 0; i < count; i++) {
      final before = controller.widget<Semantics>(plot).properties.value;
      final bounds = controller.getRect(plot);
      await controller.tapAt(
        Offset(
          bounds.left + bounds.width * points[i % points.length],
          bounds.center.dy,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 230));
      if (before == controller.widget<Semantics>(plot).properties.value) {
        throw StateError('Sales selection did not change after step $i.');
      }
    }
  }

  await selectSales(3);
  await measure('sales_day_selection', () => selectSales(16), atLeast: 16);
}
