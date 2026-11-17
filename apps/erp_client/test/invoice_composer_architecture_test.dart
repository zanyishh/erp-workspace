import 'dart:async';

import 'package:erp_client/core/models/erp_exception.dart';
import 'package:erp_client/features/invoices/data/invoice_composer_repository.dart';
import 'package:erp_client/features/invoices/models/invoice_compose.dart';
import 'package:erp_client/features/invoices/presentation/invoice_composer_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _quote({String company = 'A'}) => {
  'company': company,
  'review': 'server-review',
  'currency': 'INR',
  'precision': 2,
  'net_total': '108.50',
  'grand_total': '108.50',
  'rounded_total': '109',
  'rounding_adjustment': '0.50',
  'taxes': [],
  'items': [
    {'qty': '2', 'uom': 'Nos', 'rate': '54.25', 'amount': '108.50'},
  ],
};

class _Repo implements InvoiceComposerRepository {
  @override
  Object identity = Object();
  @override
  Object? scope = 1;
  @override
  String get company => 'A';
  @override
  bool supportsRecovery = false;
  bool loseResponse = false, failPreparation = false, reject = false;
  String operationState = 'prepared';
  final writes = <(Map<String, Object?>, String, String)>[];
  final acknowledgements = <String>[];
  int prepares = 0, defaultReads = 0;
  Completer<String>? pendingWrite;
  Completer<InvoiceSaveStatus>? pendingPrepare;
  Completer<InvoiceReview>? pendingReview;
  Completer<InvoiceComposeDefaults>? pendingDefaults;
  @override
  Future<InvoiceComposeDefaults> defaults() async {
    defaultReads++;
    return pendingDefaults?.future ??
        InvoiceComposeDefaults.fromJson({
          'posting_date': '2026-11-17',
          'template_id': 'cobalt',
        });
  }

  @override
  Future<InvoiceReview> review(Map<String, Object?> draft) async =>
      pendingReview?.future ??
      InvoiceReview.fromJson(_quote(), company: 'A', itemCount: 1);
  @override
  Future<String> save(
    Map<String, Object?> draft,
    String requestId,
    String review,
  ) async {
    writes.add((draft, requestId, review));
    if (reject) throw const ErpException('Rejected', validationRejected: true);
    if (pendingWrite != null) return pendingWrite!.future;
    if (loseResponse) throw const ErpException('Response lost');
    return 'SINV-A';
  }

  InvoiceSaveStatus statusValue(String id) => InvoiceSaveStatus.fromJson(
    {
      'state': operationState,
      'request_id': id,
      'company': 'A',
      if (operationState == 'completed') 'result': {'name': 'SINV-RECOVERED'},
    },
    company: 'A',
    requestId: id,
  );
  @override
  Future<InvoiceSaveStatus> prepare(String requestId) async {
    prepares++;
    if (failPreparation) throw const ErpException('Offline');
    return pendingPrepare?.future ?? statusValue(requestId);
  }

  @override
  Future<InvoiceSaveStatus> status(
    String requestId, {
    bool close = false,
  }) async {
    if (close && operationState == 'prepared') operationState = 'closed';
    return statusValue(requestId);
  }

  @override
  Future<void> acknowledge(String requestId) async {
    acknowledgements.add(requestId);
  }

  @override
  Future<List<Map<String, dynamic>>> searchLinks(
    String doctype,
    String query,
  ) async => [];
  @override
  Future<void> setTemplate(String name, String templateId) async {}
}

Future<InvoiceComposerViewModel> _model(_Repo repository) async {
  final model = InvoiceComposerViewModel(
    repository,
    newRequestId: () => 'request-1',
  );
  addTearDown(model.dispose);
  await model.loaded;
  return model;
}

Future<void> _review(InvoiceComposerViewModel model) async {
  model.changeCustomer(' Customer A ');
  model.changeLine(
    model.lines.single.id,
    item: ' SERVICE ',
    qty: '2',
    rate: '54.25',
  );
  expect(await model.review(), isTrue);
}

void main() {
  test(
    'a moved invoice date requires a current due date before review',
    () async {
      final model = await _model(_Repo());
      model.changeCustomer('Customer A');
      model.changeLine(model.lines.single.id, item: 'SERVICE');
      model.changeDate('2026-11-18', due: true);
      model.changeDate('2026-11-19');
      expect(model.dueBeforeInvoice, isTrue);
      expect(await model.review(), isFalse);
      model.changeDate('', due: true);
      expect(model.dueBeforeInvoice, isFalse);
      expect(await model.review(), isTrue);
    },
  );

  test('durable leave confirmation permits unavailable access but rejects replaced scopes and owners', () async {
    final repo = _Repo()
      ..supportsRecovery = true
      ..loseResponse = true;
    final model = await _model(repo);
    await _review(model);
    await model.save();
    repo.scope = null;
    final captured = model.scope;
    expect(model.canConfirmLeave(captured), isTrue);
    repo.scope = 2;
    expect(model.canConfirmLeave(captured), isFalse);
    repo.scope = null;
    repo.identity = Object();
    expect(model.canConfirmLeave(captured), isFalse);
  });
  for (final recoverable in [false, true]) {
    test(
      'confirmed receipt returns to exact recovery after access refresh: $recoverable',
      () async {
        final repo = _Repo()..supportsRecovery = recoverable;
        final model = await _model(repo);
        await _review(model);
        final old = (await model.save())!;
        expect(model.canUse(old), isTrue);
        repo.scope = null;
        await model.revalidate();
        expect(
          model.leaveState,
          recoverable ? InvoiceLeaveState.pending : InvoiceLeaveState.blocked,
        );
        repo.scope = 2;
        await model.revalidate();
        expect(model.canUse(old), isFalse);
        expect(model.uncertain, isTrue);
        expect(model.editable, isFalse);
        expect(
          model.leaveState,
          recoverable ? InvoiceLeaveState.pending : InvoiceLeaveState.blocked,
        );
        expect(model.requestId, 'request-1');
        repo.operationState = 'completed';
        final current = recoverable
            ? await model.checkSave()
            : await model.save();
        expect(current, isNotNull);
        expect(model.canUse(current!), isTrue);
        expect(repo.writes, hasLength(recoverable ? 1 : 2));
        expect(
          repo.writes.every(
            (v) => v.$2 == 'request-1' && v.$3 == 'server-review',
          ),
          isTrue,
        );
      },
    );
  }
  test('an uncertain legacy attempt pins its recovery mode across capability refresh', () async {
    final repo = _Repo()..loseResponse = true;
    final model = await _model(repo);
    await _review(model);
    await model.save();
    expect(model.uncertain, isTrue);
    repo.supportsRecovery = true;
    repo.failPreparation = true;
    await model.revalidate();
    await model.save();
    expect(model.uncertain, isTrue);
    expect(model.editable, isFalse);
    expect(model.requestId, 'request-1');
    expect(repo.prepares, 0);
    expect(repo.writes, hasLength(2));
    expect(repo.writes[1].$1, repo.writes[0].$1);
  });
  test('a retry rejection cannot prove that an earlier unknown legacy write did not commit', () async {
    final repo = _Repo()..loseResponse = true;
    final model = await _model(repo);
    await _review(model);
    await model.save();
    repo.loseResponse = false;
    repo.reject = true;
    await model.save();
    expect(model.uncertain, isTrue);
    expect(model.editable, isFalse);
    expect(model.requestId, 'request-1');
    expect(model.reviewed!.token, 'server-review');
    expect(repo.writes, hasLength(2));
  });
  test('review values freeze nested rows and reject a different company or row count', () {
    final json = _quote();
    final value = InvoiceReview.fromJson(json, company: 'A', itemCount: 1);
    (json['items'] as List).clear();
    expect(value.data['items'], hasLength(1));
    expect(() => (value.data['items'] as List).clear(), throwsUnsupportedError);
    expect(
      () => InvoiceReview.fromJson(
        _quote(company: 'B'),
        company: 'A',
        itemCount: 1,
      ),
      throwsA(isA<ErpException>()),
    );
    expect(
      () => InvoiceReview.fromJson(_quote(), company: 'A', itemCount: 2),
      throwsA(isA<ErpException>()),
    );
  });
  test(
    'completed operation must identify this request and a saved invoice',
    () {
      expect(
        () => InvoiceSaveStatus.fromJson(
          {'state': 'completed', 'result': {}},
          company: 'A',
          requestId: 'x',
        ),
        throwsA(isA<ErpException>()),
      );
      expect(
        () => InvoiceSaveStatus.fromJson(
          {'state': 'prepared', 'company': 'B'},
          company: 'A',
          requestId: 'x',
        ),
        throwsA(isA<ErpException>()),
      );
      expect(
        () => InvoiceSaveStatus.fromJson(
          {'state': 'prepared', 'request_id': 'other'},
          company: 'A',
          requestId: 'x',
        ),
        throwsA(isA<ErpException>()),
      );
    },
  );
  test(
    'draft edits retain decimal text and invalidate the exact server review',
    () async {
      final repo = _Repo();
      final model = await _model(repo);
      await _review(model);
      expect(model.reviewed!.token, 'server-review');
      expect(model.draft['customer'], 'Customer A');
      expect((model.draft['items'] as List).single['rate'], '54.25');
      expect(
        () => (model.draft['items'] as List).clear(),
        throwsUnsupportedError,
      );
      model.changeLine(model.lines.single.id, qty: '2.000');
      expect(model.reviewed, isNull);
      expect(model.hasEdits, isTrue);
      expect(repo.writes, isEmpty);
    },
  );
  test('unknown legacy save freezes payload, review and request ID until exact retry', () async {
    final repo = _Repo()..loseResponse = true;
    final model = await _model(repo);
    await _review(model);
    expect(await model.save(), isNull);
    expect(model.uncertain, isTrue);
    expect(model.editable, isFalse);
    model.changeCustomer('Other');
    model.changeLine(model.lines.single.id, qty: '99');
    expect(model.customer.trim(), 'Customer A');
    expect(model.lines.single.qty, '2');
    repo.loseResponse = false;
    final receipt = await model.save();
    expect(receipt!.name, 'SINV-A');
    expect(repo.writes, hasLength(2));
    expect(repo.writes[1].$1, repo.writes[0].$1);
    expect(repo.writes.map((v) => v.$2), everyElement('request-1'));
    expect(repo.writes.map((v) => v.$3), everyElement('server-review'));
  });
  test('preparation failure cannot issue a business write', () async {
    final repo = _Repo()
      ..supportsRecovery = true
      ..failPreparation = true;
    final model = await _model(repo);
    await _review(model);
    expect(await model.save(), isNull);
    expect(repo.writes, isEmpty);
    expect(model.editable, isTrue);
    expect(model.uncertain, isFalse);
  });
  test(
    'completion during preparation returns its receipt without another write',
    () async {
      final repo = _Repo()
        ..supportsRecovery = true
        ..operationState = 'completed';
      final model = await _model(repo);
      await _review(model);
      final receipt = await model.save();
      expect(receipt!.name, 'SINV-RECOVERED');
      expect(repo.writes, isEmpty);
      expect(repo.acknowledgements, isEmpty);
      await model.acknowledge(receipt);
      expect(repo.acknowledgements, ['request-1']);
    },
  );
  test('lost recoverable write checks the durable reference without repeating the save', () async {
    final repo = _Repo()
      ..supportsRecovery = true
      ..loseResponse = true;
    final model = await _model(repo);
    await _review(model);
    await model.save();
    expect(model.uncertain, isTrue);
    expect(model.prepared, isTrue);
    repo.operationState = 'completed';
    final receipt = await model.checkSave();
    expect(receipt!.name, 'SINV-RECOVERED');
    expect(repo.writes, hasLength(1));
    expect(repo.acknowledgements, isEmpty);
    await model.acknowledge(receipt);
    expect(repo.acknowledgements, hasLength(1));
  });
  test(
    'closing a prepared request unlocks edits only after confirmed closure',
    () async {
      final repo = _Repo()
        ..supportsRecovery = true
        ..loseResponse = true;
      final model = await _model(repo);
      await _review(model);
      await model.save();
      await model.checkSave();
      expect(model.editable, isFalse);
      await model.checkSave(close: true);
      expect(model.editable, isTrue);
      expect(model.reviewed, isNull);
      expect(model.requestId, isEmpty);
      expect(repo.acknowledgements, ['request-1']);
      expect(repo.writes, hasLength(1));
    },
  );
  for (final completed in [false, true]) {
    test(
      'validation closure reconciles a concurrent completion: $completed',
      () async {
        final repo = _Repo()
          ..supportsRecovery = true
          ..reject = true;
        final model = await _model(repo);
        await _review(model);
        // Return prepared first; the write changes the server status before closure.
        repo.pendingPrepare = Completer<InvoiceSaveStatus>();
        final save = model.save();
        await Future<void>.delayed(Duration.zero);
        repo.operationState = completed ? 'completed' : 'prepared';
        repo.pendingPrepare!.complete(
          InvoiceSaveStatus.fromJson(
            {'state': 'prepared'},
            company: 'A',
            requestId: 'request-1',
          ),
        );
        final receipt = await save;
        expect(receipt?.name, completed ? 'SINV-RECOVERED' : null);
        expect(model.editable, !completed);
        expect(repo.writes, hasLength(1));
      },
    );
  }
  test('scope change during preparation never sends the old write', () async {
    final repo = _Repo()
      ..supportsRecovery = true
      ..pendingPrepare = Completer<InvoiceSaveStatus>();
    final model = await _model(repo);
    await _review(model);
    final save = model.save();
    await Future<void>.delayed(Duration.zero);
    repo.scope = 2;
    repo.pendingPrepare!.complete(repo.statusValue('request-1'));
    await save;
    expect(repo.writes, isEmpty);
  });
  for (final ready in [true, false]) {
    test(
      'same-owner late write retains uncertainty through access recovery: $ready',
      () async {
        final repo = _Repo()..pendingWrite = Completer<String>();
        final model = await _model(repo);
        await _review(model);
        final save = model.save();
        await Future<void>.delayed(Duration.zero);
        repo.scope = ready ? 2 : null;
        repo.pendingWrite!.complete('SINV-A');
        expect(await save, isNull);
        repo.scope = 2;
        await model.revalidate();
        expect(model.uncertain, isTrue);
        expect(model.editable, isFalse);
        expect(model.requestId, 'request-1');
        expect(model.customer.trim(), 'Customer A');
      },
    );
  }
  test('owner replacement rejects a late write confirmation', () async {
    final repo = _Repo()..pendingWrite = Completer<String>();
    final model = await _model(repo);
    await _review(model);
    final save = model.save();
    await Future<void>.delayed(Duration.zero);
    repo.identity = Object();
    repo.pendingWrite!.complete('SINV-A');
    expect(await save, isNull);
    expect(model.customer, isEmpty);
    expect(model.reviewed, isNull);
    expect(repo.acknowledgements, isEmpty);
  });
  test('revalidation cannot release a pending write or replace its reviewed snapshot', () async {
    final repo = _Repo()..pendingWrite = Completer<String>();
    final model = await _model(repo);
    await _review(model);
    final save = model.save();
    await Future<void>.delayed(Duration.zero);
    await model.revalidate();
    expect(model.busy, isTrue);
    model.changeLine(model.lines.single.id, qty: '99');
    expect(model.lines.single.qty, '2');
    expect(await model.save(), isNull);
    repo.pendingWrite!.complete('SINV-A');
    expect((await save)!.name, 'SINV-A');
    expect(repo.writes, hasLength(1));
  });
  test(
    'fresh defaults reject an older response without losing entered fields',
    () async {
      final repo = _Repo()
        ..pendingDefaults = Completer<InvoiceComposeDefaults>();
      final model = InvoiceComposerViewModel(repo);
      addTearDown(model.dispose);
      model.changeCustomer('Retained');
      final old = model.loaded;
      final pending = repo.pendingDefaults!;
      repo.pendingDefaults = null;
      repo.scope = 2;
      await model.revalidate();
      pending.complete(
        InvoiceComposeDefaults.fromJson({
          'posting_date': '2026-11-16',
          'template_id': 'ledger',
        }),
      );
      await old;
      expect(model.posting, '2026-11-17');
      expect(model.customer, 'Retained');
      expect(model.companyStyle, 'Cobalt Fold');
    },
  );
  test(
    'row Undo restores exact identity and values only in its original scope',
    () async {
      final repo = _Repo(), model = await _model(_Repo());
      final id = model.lines.single.id;
      model.changeLine(id, item: 'Item', qty: '0.1250', rate: '0');
      final removed = model.removeLine(id)!;
      expect(model.lines, isEmpty);
      expect(model.restoreLine(removed), isTrue);
      expect(model.lines.single.id, same(id));
      expect(model.lines.single.qty, '0.1250');
      final other = await _model(repo);
      expect(other.restoreLine(removed), isFalse);
    },
  );
  test(
    'unready construction makes no defaults request and cannot edit',
    () async {
      final repo = _Repo()..scope = null;
      final model = InvoiceComposerViewModel(repo);
      addTearDown(model.dispose);
      await model.loaded;
      expect(repo.defaultReads, 0);
      expect(model.editable, isFalse);
      expect(model.reviewed, isNull);
    },
  );
}
