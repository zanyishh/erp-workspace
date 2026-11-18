import 'dart:async';
import 'dart:convert';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/catalog/data/master_import_repository.dart';
import 'package:erp_client/features/catalog/models/catalog_models.dart';
import 'package:erp_client/features/catalog/presentation/master_import_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _content = 'customer_name\r\nSynthetic shop\r\n';
MasterImportPreview _preview({bool imported = false}) =>
    MasterImportPreview.fromJson({
      'count': 1,
      'columns': ['customer_name'],
      'sample': [
        ['Synthetic shop'],
      ],
      'already_imported': imported,
    });

class _Repository implements MasterImportRepository {
  Object owner = Object();
  Object? access = Object();
  @override
  Object get identity => owner;
  @override
  Object? get scope => access;
  final stages = <(String, String, String?)>[];
  bool imported = false;
  Object? confirmError;
  Completer<MasterImportPreview>? pending;
  @override
  Future<MasterImportPreview> importMasters(
    String doctype,
    String stage, {
    String? content,
  }) async {
    stages.add((doctype, stage, content));
    if (stage == 'confirm') {
      imported = true;
      if (pending != null) return pending!.future;
      if (confirmError != null) throw confirmError!;
    }
    return _preview(imported: stage == 'preview' && imported);
  }
}

void main() {
  MasterImportViewModel model(
    _Repository repository, {
    Future<ImportFile?> Function()? choose,
    Future<void> Function(String, List<int>)? saved,
  }) => MasterImportViewModel(
    repository,
    doctype: 'Customer',
    company: 'A',
    chooseFile:
        choose ??
        () async => ImportFile('customers.csv', utf8.encode(_content)),
    saveFile: (name, bytes) async {
      await saved?.call(name, bytes);
    },
  );
  test(
    'CSV content is previewed unchanged before one explicit confirmation',
    () async {
      final repository = _Repository();
      final vm = model(repository);
      expect(repository.stages, isEmpty);
      await vm.choose();
      expect(vm.filename, 'customers.csv');
      expect(vm.preview!.count, 1);
      expect(repository.stages, [('Customer', 'preview', _content)]);
      await vm.confirm();
      expect(vm.finished, isTrue);
      expect(vm.uncertain, isFalse);
      await vm.confirm();
      expect(repository.stages, [
        ('Customer', 'preview', _content),
        ('Customer', 'confirm', _content),
      ]);
      vm.dispose();
    },
  );
  test(
    'lost confirmation checks the existing receipt without replaying the write',
    () async {
      final repository = _Repository()
        ..confirmError = const ErpException('Response lost');
      final vm = model(repository);
      await vm.choose();
      await vm.confirm();
      expect(vm.uncertain, isTrue);
      expect(vm.finished, isFalse);
      await vm.choose();
      expect(repository.stages, hasLength(2));
      await vm.check();
      expect(vm.finished, isTrue);
      expect(vm.uncertain, isFalse);
      expect(repository.stages.map((s) => s.$2), [
        'preview',
        'confirm',
        'preview',
      ]);
      await vm.confirm();
      expect(repository.stages, hasLength(3));
      vm.dispose();
    },
  );
  for (final error in [
    const ErpException('Invalid row', validationRejected: true),
    const ErpException('No permission', permissionDenied: true),
    const ErpException('Sign in', sessionExpired: true),
  ]) {
    test(
      'known rejected import remains a failure without an uncertain outcome: $error',
      () async {
        final repository = _Repository()..confirmError = error;
        final vm = model(repository);
        await vm.choose();
        await vm.confirm();
        expect(vm.uncertain, isFalse);
        expect(vm.finished, isFalse);
        expect(vm.problem, contains(error.toString()));
        vm.dispose();
      },
    );
  }
  test(
    'a pending file selection cannot preview under a replacement owner',
    () async {
      final repository = _Repository();
      final file = Completer<ImportFile?>();
      final vm = model(repository, choose: () => file.future);
      final choosing = vm.choose();
      expect(vm.busy, isTrue);
      repository.owner = Object();
      file.complete(ImportFile('old.csv', utf8.encode(_content)));
      await choosing;
      expect(repository.stages, isEmpty);
      expect(vm.preview, isNull);
      vm.dispose();
    },
  );
  test('a disposed import ignores a file chooser that returns later', () async {
    final repository = _Repository();
    final file = Completer<ImportFile?>();
    final vm = model(repository, choose: () => file.future);
    final choosing = vm.choose();
    vm.dispose();
    file.complete(ImportFile('old.csv', utf8.encode(_content)));
    await choosing;
    expect(repository.stages, isEmpty);
    expect(vm.preview, isNull);
  });
  for (final changedScope in [false, true]) {
    test(
      'access revalidation never releases a pending import with scope change $changedScope',
      () async {
        final repository = _Repository()
          ..pending = Completer<MasterImportPreview>();
        final vm = model(repository);
        await vm.choose();
        final writing = vm.confirm();
        if (changedScope) {
          repository.access = Object();
        }
        vm.invalidate();
        await vm.revalidate();
        expect(vm.busy, isTrue);
        await vm.confirm();
        await vm.choose();
        expect(repository.stages.where((s) => s.$2 == 'confirm'), hasLength(1));
        repository.pending!.complete(_preview(imported: true));
        await writing;
        expect(vm.busy, isFalse);
        vm.dispose();
      },
    );
  }
  test(
    'oversized and invalid UTF-8 inputs never reach the import API',
    () async {
      for (final bytes in [
        List<int>.filled(262145, 65),
        [255],
      ]) {
        final repository = _Repository();
        final vm = model(
          repository,
          choose: () async => ImportFile('bad.csv', bytes),
        );
        await vm.choose();
        expect(repository.stages, isEmpty);
        expect(vm.problem, isNotNull);
        expect(vm.preview, isNull);
        vm.dispose();
      }
    },
  );
  test('templates retain their original CSV headers and CRLF bytes', () async {
    final repository = _Repository();
    final saved = <(String, String)>[];
    final vm = model(
      repository,
      saved: (name, bytes) async {
        saved.add((name, utf8.decode(bytes)));
      },
    );
    await vm.template();
    expect(repository.stages, [('Customer', 'template', null)]);
    expect(saved, [('Customer template.csv', 'customer_name\r\n')]);
    vm.dispose();
  });
  test('preview rows cannot be changed through a read result', () {
    final value = _preview();
    expect(
      () => (value.data['sample'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (value.data['sample'] as List).first.clear(),
      throwsUnsupportedError,
    );
  });
}
