import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/invoices/data/invoice_repository.dart';
import 'package:erp_client/features/invoices/models/invoice_profile.dart';
import 'package:erp_client/features/invoices/presentation/invoice_settings_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> invoiceSettingsValues() => {
  'template_id': 'ledger',
  'logo_base64': '',
  'bank_name': '',
  'account_holder': '',
  'account_number': '',
  'ifsc': '',
  'upi_id': '',
  'upi_name': '',
};
Map<String, dynamic> invoiceProfileData({
  Map<String, String>? values,
  String revision = '0',
  bool manage = true,
}) => {
  'company': 'A',
  'can_manage': manage,
  'revision': revision,
  'settings': values ?? invoiceSettingsValues(),
};

class MemoryInvoiceSettingsRepository implements InvoiceSettingsRepository {
  Object owner = Object();
  Object? current = 1;
  @override
  Object get identity => owner;
  @override
  Object? get scope => current;
  int reads = 0;
  var saved = invoiceSettingsValues();
  String revision = '0';
  bool manage = true, lose = false, deny = false;
  Completer<InvoiceProfile>? pendingRead, pendingSave;
  final writes = <(Map<String, String>, String)>[];
  InvoiceProfile profile() => InvoiceProfile.fromJson(
    invoiceProfileData(values: saved, revision: revision, manage: manage),
    company: 'A',
  );
  @override
  Future<InvoiceProfile> settings() async {
    reads++;
    return pendingRead?.future ?? profile();
  }

  @override
  Future<InvoiceProfile> saveSettings(
    Map<String, String> values,
    String version,
  ) async {
    writes.add((Map.of(values), version));
    if (pendingSave != null) return pendingSave!.future;
    if (deny) throw const ErpException('Rejected', validationRejected: true);
    saved = Map.of(values);
    revision = '1';
    if (lose) throw const ErpException('Response lost');
    return profile();
  }
}

void main() {
  InvoiceSettingsViewModel model(
    MemoryInvoiceSettingsRepository repository, {
    Future<Uint8List?> Function()? pickLogo,
  }) => InvoiceSettingsViewModel(
    repository,
    pickLogo: pickLogo ?? () async => null,
  );
  test('profile freezes settings and validates its exact company', () {
    final raw = invoiceProfileData();
    final value = InvoiceProfile.fromJson(raw, company: 'A');
    (raw['settings'] as Map)['bank_name'] = 'changed';
    expect(value.settings['bank_name'], '');
    expect(() => value.settings['bank_name'] = 'bad', throwsUnsupportedError);
    expect(
      () => InvoiceProfile.fromJson(
        invoiceProfileData()..['company'] = 'B',
        company: 'A',
      ),
      throwsA(isA<ErpException>()),
    );
  });
  test('settings keep raw drafts, validate related fields and snapshot trimmed saves', () async {
    final repository = MemoryInvoiceSettingsRepository();
    final vm = model(repository);
    addTearDown(vm.dispose);
    await vm.loaded;
    expect(vm.dirty, isFalse);
    vm.change('bank_name', ' Synthetic bank ');
    expect(vm.validateField('account_number', ''), contains('account number'));
    vm.change('account_number', ' 0012-34 ');
    expect(
      vm.validateField('account_number', vm.values['account_number']!),
      isNull,
    );
    expect(vm.validateField('ifsc', 'bad'), contains('IFSC'));
    vm.change('upi_name', 'Payee');
    expect(vm.validateField('upi_id', ''), contains('UPI ID'));
    vm.change('upi_name', '');
    expect(await vm.save(), isTrue);
    expect(repository.writes.single.$1['bank_name'], 'Synthetic bank');
    expect(repository.writes.single.$1['account_number'], '0012-34');
    expect(repository.writes.single.$2, '0');
  });
  test(
    'uncertain save confirms matching current values without a duplicate write',
    () async {
      final repository = MemoryInvoiceSettingsRepository()..lose = true;
      final vm = model(repository);
      addTearDown(vm.dispose);
      await vm.loaded;
      vm.change('upi_id', 'synthetic@upi');
      expect(await vm.save(), isTrue);
      expect(repository.writes, hasLength(1));
      expect(repository.reads, 2);
    },
  );
  test('an unresolved save retains exactly the same attempt and revision for explicit retry', () async {
    final repository = MemoryInvoiceSettingsRepository();
    final vm = model(repository);
    addTearDown(vm.dispose);
    await vm.loaded;
    vm.change('upi_id', 'synthetic@upi');
    repository.pendingSave = Completer<InvoiceProfile>();
    final first = vm.save();
    repository.pendingSave!.completeError(const ErpException('Lost'));
    expect(await first, isFalse);
    expect(vm.uncertain, isTrue);
    vm.change('upi_id', 'different@upi');
    expect(vm.values['upi_id'], 'synthetic@upi');
    repository.pendingSave = null;
    expect(await vm.save(), isTrue);
    expect(repository.writes, hasLength(2));
    expect(repository.writes[1].$1, repository.writes[0].$1);
    expect(repository.writes[1].$2, repository.writes[0].$2);
  });
  test('read revalidation does not release a pending settings save', () async {
    final repository = MemoryInvoiceSettingsRepository();
    final vm = model(repository);
    addTearDown(vm.dispose);
    await vm.loaded;
    vm.change('upi_id', 'synthetic@upi');
    repository.pendingSave = Completer<InvoiceProfile>();
    final saving = vm.save();
    expect(vm.busy, isTrue);
    repository.current = 2;
    await vm.revalidate();
    expect(vm.busy, isTrue);
    expect(await vm.save(), isFalse);
    expect(repository.writes, hasLength(1));
    repository.pendingSave!.complete(repository.profile());
    expect(await saving, isFalse);
    expect(vm.busy, isFalse);
  });
  for (final recovering in [false, true]) {
    test(
      'scope-changed save error protects its original attempt, recovering $recovering',
      () async {
        final repository = MemoryInvoiceSettingsRepository();
        final vm = model(repository);
        addTearDown(vm.dispose);
        await vm.loaded;
        vm.change('upi_id', 'original@upi');
        repository.pendingSave = Completer<InvoiceProfile>();
        final writing = vm.save();
        repository.current = recovering ? null : 2;
        if (!recovering) await vm.revalidate();
        repository.pendingSave!.completeError(
          const ErpException('Outcome unknown'),
        );
        expect(await writing, isFalse);
        expect(vm.busy, isFalse);
        if (recovering) {
          repository.current = 2;
          await vm.revalidate();
        }
        expect(vm.uncertain, isTrue);
        vm.change('upi_id', 'new-edit@upi');
        expect(vm.values['upi_id'], 'original@upi');
        repository.pendingSave = null;
        expect(await vm.save(), isTrue);
        expect(repository.writes, hasLength(2));
        expect(repository.writes[1].$1, repository.writes[0].$1);
        expect(repository.writes[1].$2, repository.writes[0].$2);
        expect(repository.saved['upi_id'], 'original@upi');
      },
    );
  }
  test('dirty same-owner drafts survive revalidation and newer revisions become stale', () async {
    final repository = MemoryInvoiceSettingsRepository();
    final vm = model(repository);
    addTearDown(vm.dispose);
    await vm.loaded;
    vm.change('upi_id', 'draft@upi');
    repository.current = 2;
    await vm.revalidate();
    expect(vm.values['upi_id'], 'draft@upi');
    expect(vm.stale, isFalse);
    repository.current = 3;
    repository.revision = 'new';
    await vm.revalidate();
    expect(vm.values['upi_id'], 'draft@upi');
    expect(vm.stale, isTrue);
    expect(await vm.save(), isFalse);
    expect(repository.writes, isEmpty);
  });
  test(
    'a rejected save is editable and permission loss clears all private drafts',
    () async {
      final repository = MemoryInvoiceSettingsRepository()..deny = true;
      final vm = model(repository);
      addTearDown(vm.dispose);
      await vm.loaded;
      vm.change('upi_id', 'draft@upi');
      expect(await vm.save(), isFalse);
      expect(vm.uncertain, isFalse);
      expect(vm.dirty, isTrue);
      repository.manage = false;
      repository.current = 2;
      await vm.revalidate();
      expect(vm.canManage, isFalse);
      expect(vm.values['upi_id'] ?? '', isEmpty);
    },
  );
  test(
    'a late logo selection cannot update another authorization scope',
    () async {
      final repository = MemoryInvoiceSettingsRepository();
      final picked = Completer<Uint8List?>();
      final vm = model(repository, pickLogo: () => picked.future);
      addTearDown(vm.dispose);
      await vm.loaded;
      final picking = vm.chooseLogo();
      repository.current = 2;
      await vm.revalidate();
      expect(vm.busy, isTrue);
      picked.complete(Uint8List.fromList([1, 2, 3]));
      await picking;
      expect(vm.image, isNull);
      expect(vm.values['logo_base64'], '');
      expect(vm.busy, isFalse);
    },
  );
  test('chosen logo bytes are immutable and clearing an added logo restores the original', () async {
    final repository = MemoryInvoiceSettingsRepository();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final vm = model(repository, pickLogo: () async => bytes);
    addTearDown(vm.dispose);
    await vm.loaded;
    await vm.chooseLogo();
    bytes[0] = 9;
    expect(vm.image, [1, 2, 3]);
    expect(() => vm.image![0] = 8, throwsUnsupportedError);
    expect(vm.values['logo_base64'], base64Encode([1, 2, 3]));
    vm.clearLogo();
    expect(vm.image, isNull);
    expect(vm.dirty, isFalse);
  });
  test('unready settings constructor reads nothing', () async {
    final repository = MemoryInvoiceSettingsRepository()..current = null;
    final vm = model(repository);
    addTearDown(vm.dispose);
    await expectLater(vm.loaded, throwsA(isA<ErpException>()));
    expect(repository.reads, 0);
  });
}
