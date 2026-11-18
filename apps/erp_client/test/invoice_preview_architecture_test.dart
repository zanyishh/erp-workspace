import 'dart:async';
import 'dart:typed_data';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/invoices/data/invoice_repository.dart';
import 'package:erp_client/features/invoices/models/invoice_print_data.dart';
import 'package:erp_client/features/invoices/models/invoice_paper.dart';
import 'package:erp_client/features/invoices/models/invoice_templates.dart';
import 'package:erp_client/features/invoices/presentation/invoice_preview_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> invoicePrintValues(
  InvoicePreviewSource source, {
  String template = 'ledger',
  String override = 'ledger',
}) => {
  'company': 'A',
  'name': source.kind == InvoiceSourceKind.native
      ? source.name
      : 'Original display name',
  'template_id': template,
  'template_override': override,
  'can_set_template': true,
  'grand_total': '-0.1250',
  'items': [
    {'qty': '-0.2500'},
  ],
  if (source.kind == InvoiceSourceKind.original) 'source_record': source.name,
  if (source.kind == InvoiceSourceKind.original) 'source_copy': true,
  if (source.kind == InvoiceSourceKind.original)
    'source_reference': 'Original / 42',
};

class MemoryInvoicePreviewRepository implements InvoicePreviewRepository {
  Object owner = Object();
  Object? current = 1;
  @override
  Object get identity => owner;
  @override
  Object? get scope => current;
  bool denied = false;
  int reads = 0;
  String template = 'ledger', savedOverride = 'ledger';
  Completer<InvoicePrintData>? pending;
  Completer<void>? saving;
  final writes = <(String, String)>[];
  InvoicePrintData value(InvoicePreviewSource source) =>
      InvoicePrintData.fromJson(
        invoicePrintValues(source, template: template, override: savedOverride),
        company: 'A',
        source: source,
      );
  @override
  Future<InvoicePrintData> source(InvoicePreviewSource source) async {
    reads++;
    if (denied) throw const ErpException('Denied', permissionDenied: true);
    return pending?.future ?? value(source);
  }

  @override
  Future<void> saveTemplate(String invoice, String id) async {
    writes.add((invoice, id));
    if (saving != null) await saving!.future;
    template = id.isEmpty ? 'ledger' : id;
    savedOverride = id;
  }
}

void main() {
  const native = InvoicePreviewSource.native('INV-1');
  InvoicePreviewViewModel model(
    MemoryInvoicePreviewRepository repository, {
    InvoicePreviewSource source = native,
    Future<Uint8List> Function(InvoiceTemplate, InvoicePrintData)? render,
  }) => InvoicePreviewViewModel(
    repository,
    source: source,
    render: (style, data, paper) async => render == null
        ? Uint8List.fromList([1, 2, 3])
        : await render(style, data),
  );
  test('print values freeze exact server amounts and reject mismatched native/original sources', () {
    final raw = invoicePrintValues(native);
    final data = InvoicePrintData.fromJson(raw, company: 'A', source: native);
    (raw['items'] as List).single['qty'] = 'changed';
    expect(data.data['items'].single['qty'], '-0.2500');
    expect(data.data['grand_total'], '-0.1250');
    expect(() => data.data['items'].add({}), throwsUnsupportedError);
    expect(
      () => InvoicePrintData.fromJson(
        {...raw, 'company': 'B'},
        company: 'A',
        source: native,
      ),
      throwsA(isA<ErpException>()),
    );
    expect(
      () => InvoicePrintData.fromJson(
        {...raw, 'name': 'INV-2'},
        company: 'A',
        source: native,
      ),
      throwsA(isA<ErpException>()),
    );
    const original = InvoicePreviewSource.original('history-1');
    expect(
      () => InvoicePrintData.fromJson(
        invoicePrintValues(original)..['source_record'] = 'other',
        company: 'A',
        source: original,
      ),
      throwsA(isA<ErpException>()),
    );
    expect(
      () => InvoicePrintData.fromJson(
        invoicePrintValues(original)..['source_copy'] = false,
        company: 'A',
        source: original,
      ),
      throwsA(isA<ErpException>()),
    );
  });
  test('preview publishes immutable rendered bytes and the exact sanitized filename', () async {
    final repository = MemoryInvoicePreviewRepository(),
        bytes = Uint8List.fromList([1, 2, 3]);
    final vm = model(
      repository,
      source: const InvoicePreviewSource.original('history-1'),
      render: (style, data) async => bytes,
    );
    addTearDown(vm.dispose);
    await vm.data;
    final file = await vm.pdf!;
    bytes[0] = 9;
    expect(file.bytes, [1, 2, 3]);
    expect(() => file.bytes[0] = 8, throwsUnsupportedError);
    expect(file.filename, 'Original _ 42 - Trade Ledger.pdf');
    expect(vm.canUse(file), isTrue);
    expect(vm.canSaveStyle, isFalse);
    expect(vm.canInherit, isFalse);
  });
  test(
    'paper change invalidates the old preview and exports the selected size',
    () async {
      final repository = MemoryInvoicePreviewRepository();
      final preview = model(repository);
      addTearDown(preview.dispose);
      await preview.data;
      final initial = await preview.pdf!;
      final choice = preview.prepareSelection()!;
      expect(preview.selectPaper(choice, InvoicePaper.receipt58), isTrue);
      expect(preview.canUse(initial), isFalse);
      expect(preview.selectPaper(choice, InvoicePaper.a5), isFalse);
      final file = await preview.pdf!;
      expect(file.paper, InvoicePaper.receipt58);
      expect(file.filename, endsWith(' - 58 mm receipt.pdf'));
      await preview.exportTo((value, reauthorize) async {
        expect(value.paper, file.paper);
        expect((await reauthorize()).paper, file.paper);
      });
      expect(repository.writes, isEmpty);
    },
  );

  test('selection is scoped and original/sample sources never write invoice metadata', () async {
    for (final source in [
      const InvoicePreviewSource.original('history-1'),
      const InvoicePreviewSource.sample(),
    ]) {
      final repository = MemoryInvoicePreviewRepository();
      final preview = model(repository, source: source);
      await preview.data;
      final choice = preview.prepareSelection()!;
      expect(
        preview.selectTemplate(choice, invoiceTemplateById('canopy')),
        isTrue,
      );
      expect(preview.selected.id, 'canopy');
      expect(preview.canSaveStyle, isFalse);
      expect(await preview.saveStyle(), isFalse);
      expect(repository.writes, isEmpty);
      repository.current = 2;
      expect(
        preview.selectTemplate(choice, invoiceTemplateById('folio')),
        isFalse,
      );
      preview.dispose();
    }
  });
  test('native template save refreshes authoritative override and supports inheritance', () async {
    final repository = MemoryInvoicePreviewRepository();
    final preview = model(repository);
    addTearDown(preview.dispose);
    await preview.data;
    expect(
      preview.selectTemplate(
        preview.prepareSelection()!,
        invoiceTemplateById('canopy'),
      ),
      isTrue,
    );
    expect(preview.canSaveStyle, isTrue);
    expect(await preview.saveStyle(), isTrue);
    expect(repository.writes, [('INV-1', 'canopy')]);
    expect(preview.savedOverride, 'canopy');
    expect(preview.canInherit, isTrue);
    expect(await preview.saveStyle(inherit: true), isTrue);
    expect(repository.writes.last, ('INV-1', ''));
  });
  test('read refresh cannot release an in-flight template write', () async {
    final repository = MemoryInvoicePreviewRepository();
    final vm = model(repository);
    addTearDown(vm.dispose);
    await vm.data;
    vm.selectTemplate(vm.prepareSelection()!, invoiceTemplateById('canopy'));
    repository.saving = Completer<void>();
    final saving = vm.saveStyle();
    expect(vm.working, isTrue);
    await vm.reload();
    expect(vm.working, isTrue);
    expect(await vm.saveStyle(), isFalse);
    expect(repository.writes, hasLength(1));
    repository.saving!.complete();
    expect(await saving, isTrue);
    expect(vm.savedOverride, 'canopy');
    expect(vm.working, isFalse);
  });
  for (final change in ['owner', 'access', 'dispose']) {
    test('late preview source cannot publish after $change', () async {
      final repository = MemoryInvoicePreviewRepository()
        ..pending = Completer<InvoicePrintData>();
      final vm = model(repository);
      final read = expectLater(vm.data, throwsA(isA<ErpException>()));
      if (change == 'owner') repository.owner = Object();
      if (change == 'access') repository.current = 2;
      if (change == 'dispose') vm.dispose();
      repository.pending!.complete(repository.value(native));
      await read;
      expect(vm.currentFile, isNull);
      if (change != 'dispose') vm.dispose();
    });
  }
  test(
    'a failed old template command cannot replace a newer read with its error',
    () async {
      final repository = MemoryInvoicePreviewRepository();
      final vm = model(repository);
      addTearDown(vm.dispose);
      await vm.data;
      vm.selectTemplate(vm.prepareSelection()!, invoiceTemplateById('canopy'));
      repository.saving = Completer<void>();
      final writing = vm.saveStyle();
      await vm.reload();
      repository.saving!.completeError(const ErpException('Old failure'));
      expect(await writing, isFalse);
      expect(vm.problem, isNull);
    },
  );
  test('late rendering cannot publish bytes from obsolete access', () async {
    final repository = MemoryInvoicePreviewRepository(),
        render = Completer<Uint8List>();
    final vm = model(repository, render: (style, data) => render.future);
    addTearDown(vm.dispose);
    await vm.data;
    final pending = expectLater(vm.pdf!, throwsA(isA<ErpException>()));
    repository.current = 2;
    render.complete(Uint8List.fromList([1]));
    await pending;
    expect(vm.currentFile, isNull);
  });
  test('export reauthorizes before platform work and after a picker; permission rejection clears cached bytes', () async {
    final repository = MemoryInvoicePreviewRepository();
    final preview = model(repository);
    addTearDown(preview.dispose);
    await preview.data;
    final old = await preview.pdf!;
    var actions = 0;
    await preview.exportTo((file, reauthorize) async {
      expect(repository.reads, 2);
      expect(preview.canUse(file), isTrue);
      final current = await reauthorize();
      expect(preview.canUse(current), isTrue);
      actions++;
    });
    expect(repository.reads, 3);
    expect(actions, 1);
    repository.denied = true;
    await expectLater(
      preview.exportTo((file, reauthorize) async => actions++),
      throwsA(isA<ErpException>()),
    );
    expect(preview.canUse(old), isFalse);
    expect(preview.currentFile, isNull);
    expect(actions, 1);
  });
  test(
    'revalidation invalidates an export without releasing its active token',
    () async {
      final repository = MemoryInvoicePreviewRepository();
      final preview = model(repository);
      addTearDown(preview.dispose);
      await preview.data;
      await preview.pdf!;
      final picker = Completer<void>(), started = Completer<void>();
      final exporting = preview.exportTo((file, reauthorize) async {
        started.complete();
        await picker.future;
        await reauthorize();
      });
      final rejected = expectLater(exporting, throwsA(isA<ErpException>()));
      await started.future;
      await preview.reload();
      expect(preview.working, isTrue);
      var overlap = false;
      await preview.exportTo((file, reauthorize) async => overlap = true);
      expect(overlap, isFalse);
      picker.complete();
      await rejected;
      expect(preview.working, isFalse);
    },
  );
  test('unready preview reads and renders nothing', () async {
    final repository = MemoryInvoicePreviewRepository()..current = null;
    var renders = 0;
    final vm = model(
      repository,
      render: (style, data) async {
        renders++;
        return Uint8List(0);
      },
    );
    addTearDown(vm.dispose);
    await expectLater(vm.data, throwsA(isA<ErpException>()));
    expect(repository.reads, 0);
    expect(renders, 0);
  });
}
