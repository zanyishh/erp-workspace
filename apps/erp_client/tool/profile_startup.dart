// Run scripts/profile-startup.py with a profile build of this entry point.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming, ImageFilter, PointerDeviceKind;

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/mill_overview.dart';
import 'package:erp_client/main.dart' show WorkspaceShell;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' show LiveWidgetController, find;

import 'profile_workspace.dart' show ProfileFixtureApi;

Future<void> main() async {
  try {
    if (kDebugMode) throw StateError('Use a native profile or release build.');
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      exit(1);
    };
    await _run().timeout(const Duration(seconds: 60));
    await stdout.flush();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('STARTUP_FAILED $error\n$stack');
    exit(1);
  }
}

Future<void> _run() async {
  final launchUs = int.parse(Platform.environment['ERP_PROFILE_LAUNCH_US']!);
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  final timings = <FrameTiming>[];
  final reports = StreamController<void>.broadcast();
  void capture(List<FrameTiming> batch) {
    timings.addAll(batch);
    reports.add(null);
  }

  binding.addTimingsCallback(capture);
  int frame() => binding.platformDispatcher.frameData.frameNumber;
  Future<int> drawn(bool Function() ready) async {
    final result = Completer<int>();
    void check(Duration _) {
      if (ready()) {
        result.complete(frame());
      } else {
        binding.addPostFrameCallback(check);
      }
    }

    binding.addPostFrameCallback(check);
    binding.scheduleFrame();
    return result.future;
  }

  Future<void> report(String scenario, int startUs, int first, int last) async {
    while (!timings.any((f) => f.frameNumber >= last)) {
      await reports.stream.first;
    }
    final frames = timings
        .where((f) => f.frameNumber >= first && f.frameNumber <= last)
        .toList();
    final finish = frames.last.timestampInMicroseconds(
      FramePhase.rasterFinishWallTime,
    );
    if (frames.last.frameNumber != last || finish < startUs) {
      throw StateError(
        'No matching raster timestamp for $scenario frame $last.',
      );
    }
    final view = binding.platformDispatcher.views.single;
    final size = view.physicalSize / view.devicePixelRatio;
    stdout.writeln(
      'STARTUP_PROFILE ${jsonEncode({
        'scenario': scenario,
        'elapsed_ms': (finish - startUs) / 1000,
        'width': size.width,
        'height': size.height,
        'dpr': view.devicePixelRatio,
        'display_hz': view.display.refreshRate,
        'impeller': ImageFilter.isShaderFilterSupported,
        'mode': kReleaseMode ? 'release' : 'profile',
        'frames': [
          for (final f in frames) {'id': f.frameNumber, 'build_ms': f.buildDuration.inMicroseconds / 1000, 'raster_ms': f.rasterDuration.inMicroseconds / 1000, 'span_ms': f.totalSpan.inMicroseconds / 1000},
        ],
      })}',
    );
  }

  final connected = Platform.environment['ERP_PROFILE_CONNECTED'] == '1';
  final address = Uri.parse('http://127.0.0.1:8081');
  final secrets = connected
      ? jsonDecode(stdin.readLineSync()!) as Map<String, dynamic>
      : {'user': 'synthetic@example.invalid', 'password': 'synthetic'};
  if (!(secrets['user'] as String).endsWith('@example.invalid')) {
    throw StateError('Use a synthetic native-test account.');
  }
  late ErpApi api;
  ErpApi connect(Uri requested) {
    if (!connected) return api = ProfileFixtureApi();
    if (requested != address) {
      throw StateError('Expected the isolated service.');
    }
    return api = ErpApi(address);
  }

  runApp(
    MaterialApp(
      theme: WorkspaceTheme.theme,
      home: WorkspaceShell(connect: connect),
    ),
  );
  final signIn = find.text('Enter workspace').hitTestable();
  final fields = find.byType(EditableText);
  final signInFrame = await drawn(
    () =>
        signIn.evaluate().isNotEmpty &&
        fields.evaluate().length >= 2 &&
        binding.lifecycleState == AppLifecycleState.resumed,
  );
  await report('launch_to_sign_in', launchUs, 0, signInFrame);

  Future<void> enterAt(int index, String value) async {
    final field = fields.at(index);
    await controller.tap(field, kind: PointerDeviceKind.mouse);
    final state = controller.state<EditableTextState>(field);
    if (!state.widget.focusNode.hasFocus) {
      throw StateError('Field did not take focus.');
    }
    state.updateEditingValue(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
  }

  final credentialIndex = fields.evaluate().length - 2;
  if (credentialIndex == 1) await enterAt(0, address.toString());
  await enterAt(credentialIndex, secrets['user'] as String);
  await enterAt(credentialIndex + 1, secrets['password'] as String);
  final clickFrame = frame();
  final clickUs = DateTime.now().microsecondsSinceEpoch;
  await controller.tap(signIn, kind: PointerDeviceKind.mouse);
  final jobs = find.text('Jobs').hitTestable();
  final usable = await drawn(
    () =>
        jobs.evaluate().isNotEmpty &&
        find.text('Running jobs').hitTestable().evaluate().isNotEmpty &&
        find.byType(MillOverview).evaluate().isNotEmpty,
  );
  // Also track late image uploads. Preserve the separate actionable milestone.
  final illustrated = await drawn(() {
    final images = find.byType(RawImage).evaluate();
    return images.isNotEmpty &&
        images.every((e) => (e.widget as RawImage).image != null);
  });
  await report('sign_in_to_mill', clickUs, clickFrame + 1, usable);
  await report(
    'sign_in_to_illustrated_mill',
    clickUs,
    clickFrame + 1,
    illustrated,
  );

  final snapshot = controller
      .widget<MillOverview>(find.byType(MillOverview))
      .snapshot;
  final records = snapshot.rows('jobs');
  final firstJob = records.first['name'] as String;
  final lastJob = records.last['name'] as String;
  final running = records.where((r) => r['status'] == 'Running').length;
  if (records.length < 2 || find.text('$running').evaluate().isEmpty) {
    throw StateError('Missing the expected running-job count.');
  }
  if (connected) {
    final catalog = await api.nativeCatalog(company: snapshot.company);
    if (catalog.site != 'native-test.localhost' ||
        snapshot.company != 'ERP Native Verification') {
      throw StateError('Unexpected site or fixture company.');
    }
  }
  stdout.writeln(
    'STARTUP_WORKLOAD ${jsonEncode({'source': connected ? 'native-test.localhost' : 'in-memory', 'jobs': records.length, 'events': snapshot.rows('events').length})}',
  );

  final jobsStart = frame();
  final jobsUs = DateTime.now().microsecondsSinceEpoch;
  await controller.tap(jobs, kind: PointerDeviceKind.mouse);
  final register = await drawn(
    () =>
        fields.evaluate().length == 1 &&
        find.text(firstJob).evaluate().isNotEmpty,
  );
  await report('jobs_click_to_register', jobsUs, jobsStart + 1, register);
  // Timings stop at the drawn register. Follow the same field-change path as
  // keyboard navigation without aiming at a row while it is still moving.
  final search = controller.state<EditableTextState>(fields.first);
  await controller.ensureVisible(fields.first);
  search.widget.focusNode.requestFocus();
  await drawn(() => search.widget.focusNode.hasFocus);
  search.updateEditingValue(
    TextEditingValue(
      text: lastJob,
      selection: TextSelection.collapsed(offset: lastJob.length),
    ),
  );
  final filtered = await drawn(
    () =>
        find.text(lastJob).evaluate().isNotEmpty &&
        find.text(firstJob).evaluate().isEmpty,
  );
  if (connected) await api.signOut();
  binding.removeTimingsCallback(capture);
  stdout.writeln('STARTUP_OK filtered job in frame $filtered');
  await reports.close();
}
