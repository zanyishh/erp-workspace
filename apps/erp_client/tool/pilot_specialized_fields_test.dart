// Connected editor verification on the isolated native site. The platform file
// picker returns the path of a synthetic PNG; all record saves and reads use HTTP.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _Binding();
  testWidgets('draw, attach, scan, save, reopen and preview on native-test', (
    t,
  ) async {
    const type = 'Native Workspace Test Record';
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP42OoARAwQCgAyugbZ73Um7wAAAABJRU5ErkJggg==';
    final api = ErpApi(Uri.parse('http://localhost:8081'));
    final verified = await t.runAsync(() async {
      await api.login(
        'Administrator',
        Platform.environment['ERP_LOCAL_PILOT_PASSWORD'] ??
            (throw StateError(
              'Set ERP_LOCAL_PILOT_PASSWORD for the isolated native site.',
            )),
      );
      return (await api.nativeCatalog()).site;
    });
    expect(verified, 'native-test.localhost');
    final dir = Directory.systemTemp.createTempSync('native-field-proof-');
    final image = File('${dir.path}/field-receipt.png')
      ..writeAsBytesSync(base64Decode(png));
    addTearDown(() => dir.deleteSync(recursive: true));
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      picker,
      (call) async => call.method == 'openFile' ? [image.path] : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        null,
      ),
    );
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    Future<void> wait(Finder f) async {
      for (var i = 0; i < 250; i++) {
        await t.pump(const Duration(milliseconds: 70));
        if (f.evaluate().isNotEmpty) return;
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      fail(
        'Waiting for $f: ${t.widgetList<Text>(find.byType(Text)).map((e) => e.data).whereType<String>().where((s) => s.length < 200).join(" | ")}',
      );
    }

    Future<void> tap(Finder f) async {
      await wait(f);
      await t.ensureVisible(f.first);
      await t.tap(f.first);
      await t.pump(const Duration(milliseconds: 350));
    }

    Future<void> put(String key, String value) async {
      final f = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      );
      await wait(f);
      await t.ensureVisible(f.first);
      await t.enterText(f.first, value);
      await t.pump();
    }

    Future<void> editor({String? name}) async {
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: DocumentEditor(
            key: ValueKey(name),
            api: api,
            doctype: type,
            name: name,
          ),
        ),
      );
      await wait(find.byType(DocumentFields));
    }

    await editor();
    await put('title', 'Synthetic specialized field rehearsal');
    await tap(find.text('Choose image'));
    await wait(find.text('Ready to save privately'));
    await tap(find.text('Add signature'));
    final pad = find.byKey(const ValueKey('signature-pad'));
    await wait(pad);
    final pen = await t.startGesture(t.getCenter(pad));
    await pen.moveBy(const Offset(25, 20));
    await pen.moveBy(const Offset(36, -15));
    await pen.up();
    await t.pump();
    await tap(find.text('Use signature'));
    await wait(find.byTooltip('Clear signature'));
    await put('scan', '000127');
    await tap(find.widgetWithText(FilledButton, 'Save'));
    await wait(find.text('Saved successfully'));
    final saved = t
        .widget<DocumentFields>(find.byType(DocumentFields).first)
        .data;
    expect(saved['signed_by'], startsWith('data:image/png;base64,'));
    expect(barcodeText(saved['scan']), '000127');
    expect(saved['proof_image'], startsWith('/private/files/'));
    final id = saved['name'] as String;
    await editor(name: id);
    await wait(find.byTooltip('Clear signature'));
    final text = t.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('scan')),
        matching: find.byType(TextField),
      ),
    );
    expect(text.controller!.text, '000127');
    await tap(
      find.descendant(
        of: find.byKey(const ValueKey('proof_image')),
        matching: find.text('Open file'),
      ),
    );
    await wait(find.byType(InteractiveViewer));
    final fetched = await t.runAsync(
      () => api.fieldAttachment(type, id, 'proof_image'),
    );
    expect(base64Encode(fetched!.bytes), png);
    await t.pageBack();
    await t.pumpAndSettle();
    await tap(find.byTooltip('Clear file'));
    await tap(find.widgetWithText(FilledButton, 'Save'));
    await wait(find.text('Saved successfully'));
    final reopened = await t.runAsync(() => api.nativeDocument(type, name: id));
    expect(reopened!.data['proof_image'] ?? '', isEmpty);
    expect(reopened.data['signed_by'], saved['signed_by']);
    await t.runAsync(api.signOut);
    api.close();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 30));
    debugPrint(
      'Verified native-test.localhost: private PNG, drawn signature and barcode reopened on $id.',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
