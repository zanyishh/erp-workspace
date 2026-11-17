// Rehearse the direct local start and the real invoice register on the isolated Mac service.
// Optional INVOICE_PILOT_DIR captures the visible UI and a real synthetic invoice PDF.
import 'dart:io';
import 'dart:convert';

import 'package:printing/printing.dart';
// The plugin exposes its test platform interface from src in the pinned version.
// ignore: implementation_imports
import 'package:printing/src/interface.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/main.dart' as app;
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/invoice_gallery.dart';
import 'package:erp_client/invoice_preview.dart';
import 'package:erp_client/invoice_templates.dart';
import 'package:erp_client/invoice_pdf.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

// Widget tests do not host the macOS printing plugin. Rasterise its actual PDF bytes
// with Poppler so the integration check can inspect and capture the rendered page.
class _PilotPrinting extends PrintingPlatform {
  @override
  Future<PrintingInfo> info() async => const PrintingInfo(canRaster: true);
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    {
      final dir = Directory.systemTemp.createTempSync('erp-invoice-render-');
      try {
        final input = File('${dir.path}/invoice.pdf');
        input.writeAsBytesSync(document);
        final converted = Process.runSync('pdftoppm', [
          '-f',
          '1',
          '-l',
          '1',
          '-singlefile',
          '-scale-to',
          '1000',
          input.path,
          '${dir.path}/page',
        ]);
        if (converted.exitCode != 0) {
          throw StateError('Could not rasterise the pilot PDF.');
        }
        final data = File('${dir.path}/page.ppm').readAsBytesSync();
        final head = RegExp(r'^P6\s+(\d+)\s+(\d+)\s+255\s')
            .firstMatch(latin1.decode(data.sublist(0, 64)))!;
        final width = int.parse(head[1]!), height = int.parse(head[2]!);
        final rgba = Uint8List(width * height * 4);
        for (var pixel = 0; pixel < width * height; pixel++) {
          final src = head.end + pixel * 3, dest = pixel * 4;
          rgba[dest] = data[src];
          rgba[dest + 1] = data[src + 1];
          rgba[dest + 2] = data[src + 2];
          rgba[dest + 3] = 255;
        }
        yield PdfRaster(width, height, rgba);
      } finally {
        dir.deleteSync(recursive: true);
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _Binding();
  testWidgets(
    'direct workspace opens invoices, previews all formats, and preserves the chosen style',
    (t) async {
      expect(const bool.fromEnvironment('ERP_LOCAL_WORKSPACE'), isTrue);
      expect(
        const String.fromEnvironment('ERP_SERVER'),
        'http://127.0.0.1:8081',
      );
      const channel = MethodChannel('org.localerp.workspace/local');
      final previousPrinting = PrintingPlatform.instance;
      PrintingPlatform.instance = _PilotPrinting();
      addTearDown(() => PrintingPlatform.instance = previousPrinting);
      final home = Platform.environment['HOME']!;
      final support =
          '$home/Library/Containers/org.localerp.erpClient/Data/Library/Application Support';
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'applicationSupport' ? support : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1320, 900);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final boundary = GlobalKey();
      final output = Platform.environment['INVOICE_PILOT_DIR'];
      Future<void> wait(Finder target) async {
        for (var n = 0; n < 350; n++) {
          await t.pump(const Duration(milliseconds: 55));
          if (target.evaluate().isNotEmpty) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 45)),
          );
        }
        fail(
          'Could not reach $target. Visible text: ${t.widgetList<Text>(find.byType(Text)).map((e) => e.data).whereType<String>().take(28).join(' | ')}',
        );
      }

      Future<void> tap(Finder target) async {
        await wait(target);
        await t.ensureVisible(target.first);
        await t.tap(target.first);
        await t.pump(const Duration(milliseconds: 350));
      }

      Future<void> shot(String file) async {
        if (output == null) return;
        await t.pump(const Duration(milliseconds: 600));
        await t.pump();
        final pictures = find.byType(RawImage);
        for (var n = 0; n < 70; n++) {
          await t.pump(const Duration(milliseconds: 30));
          if (t.widgetList<RawImage>(pictures).isNotEmpty &&
              t
                  .widgetList<RawImage>(pictures)
                  .every((im) => im.image != null)) {
            break;
          }
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await t.runAsync(() async {
          final img =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
          await Directory(output).create(recursive: true);
          await File('$output/$file.png').writeAsBytes(bytes);
          img.dispose();
        });
      }

      for (final font in {
        'Manrope': 'assets/fonts/Manrope-Regular.ttf',
        'BarlowCondensed': 'assets/fonts/BarlowCondensed-SemiBold.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
      await t.pumpWidget(
        RepaintBoundary(key: boundary, child: const app.ErpWorkspaceApp()),
      );
      await tap(find.text('Invoices'));
      await wait(
        find.descendant(
          of: find.byType(InvoiceHub),
          matching: find.text('Atlas Office Supplies'),
        ),
      );
      final hub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
      final api = hub.api, company = hub.company;
      expect(company, 'Meridian Trading');
      expect(api.account, 'local-general-owner@workspace.example.invalid');
      expect(find.text('Kaveri Loomworks'), findsNothing);
      final records = await t.runAsync(() => api.salesInvoices(company));
      final row = (records!['rows'] as List).cast<Map>().firstWhere(
        (r) => r['docstatus'] == 1 && r['can_print'] == true,
      );
      final name = row['name'] as String;
      await shot('invoice-register');
      await tap(find.text('Templates'));
      await wait(find.byType(InvoiceGallery));
      await shot('invoice-gallery');
      t.view.physicalSize = const Size(390, 844);
      await t.pump(const Duration(milliseconds: 400));
      await shot('phone-gallery');
      t.view.physicalSize = const Size(1320, 900);
      await t.pump(const Duration(milliseconds: 400));
      await tap(find.text('Sales invoices'));
      await tap(find.byTooltip('Preview $name'));
      final before = (await t.runAsync(
        () => api.invoicePrintData(company, name),
      ))!;
      expect(before['company'], 'Meridian Trading');
      final initial = invoiceTemplateById(before['template_id'].toString());
      final chosen = invoiceTemplateById(
        initial.id == 'ribbon' ? 'canopy' : 'ribbon',
      );
      await wait(find.byType(InvoicePreviewScreen));
      await tap(
        find.descendant(
          of: find.byType(InvoicePreviewScreen),
          matching: find.text(initial.name),
        ),
      );
      await tap(
        find.descendant(
          of: find.byType(InvoiceGallery).last,
          matching: find.text(chosen.name),
        ),
      );
      await tap(find.text('Save template'));
      await wait(find.text('${chosen.name} saved for $name.'));
      await shot('selected-invoice-preview');
      final after = (await t.runAsync(
        () => api.invoicePrintData(company, name),
      ))!;
      expect(after['template_id'], chosen.id);
      final bytes = (await t.runAsync(() => buildInvoicePdf(chosen, after)))!;
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      if (output != null) {
        await t.runAsync(
          () =>
              File('$output/selected-invoice.pdf')
                  .writeAsBytes(Uint8List.fromList(bytes)),
        );
      }
      stdout.writeln(
        'Verified $name, ${after['currency']} ${after['grand_total']}, template ${chosen.name}, ${bytes.length} PDF bytes.',
      );
      await t.runAsync(
        () => api.setInvoiceTemplate(
          company,
          name,
          before['template_override']?.toString() ?? initial.id,
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
