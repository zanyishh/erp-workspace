import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/invoices/data/erp_invoice_repository.dart';
import 'package:erp_client/features/invoices/data/invoice_repository.dart';
import 'package:erp_client/features/invoices/presentation/invoice_register_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> invoiceRegisterData({
  String name = 'INV-1',
  bool more = false,
}) => {
  'rows': [
    {
      'name': name,
      'can_print': true,
      'grand_total': '-0.1250',
      'extra': {
        'values': [1],
      },
    },
  ],
  'statuses': ['All', 'Draft'],
  'has_more': more,
  'can_create': true,
  'can_manage_settings': true,
  'default_template_id': 'ledger',
};

class MemoryInvoiceRepository implements InvoiceRegisterRepository {
  Object owner = Object();
  Object? current = 1;
  @override
  Object get identity => owner;
  @override
  Object? get scope => current;
  final reads = <(String, String, int, int)>[];
  Completer<InvoiceRegisterPage>? pending;
  bool denied = false;
  @override
  Future<InvoiceRegisterPage> register({
    String query = '',
    String status = 'All',
    int start = 0,
    int pageSize = 25,
  }) {
    reads.add((query, status, start, pageSize));
    if (denied) {
      return Future.error(const ErpException('Denied', permissionDenied: true));
    }
    return pending?.future ??
        Future.value(
          InvoiceRegisterPage.fromJson(
            invoiceRegisterData(name: 'INV-${start + 1}', more: start == 0),
            company: 'A',
            pageSize: pageSize,
          ),
        );
  }
}

void main() {
  test(
    'invoice read values freeze nested data and preserve exact server amounts',
    () {
      final raw = invoiceRegisterData();
      final page = InvoiceRegisterPage.fromJson(
        raw,
        company: 'A',
        pageSize: 25,
      );
      ((raw['rows'] as List).single as Map)['grand_total'] = 'changed';
      expect(page.rows.single['grand_total'], '-0.1250');
      expect(() => page.rows.add({}), throwsUnsupportedError);
      expect(
        () => (page.rows.single['extra']['values'] as List).add(2),
        throwsUnsupportedError,
      );
      expect(page.canCreate, isTrue);
      expect(page.canManageSettings, isTrue);
    },
  );
  for (final malformed in [
    'rows',
    'identity',
    'duplicates',
    'statuses',
    'scope',
    'bound',
    'more',
  ]) {
    test('invoice register rejects malformed $malformed responses', () {
      final value = invoiceRegisterData();
      switch (malformed) {
        case 'rows':
          value['rows'] = 'bad';
        case 'identity':
          (value['rows'] as List).single['name'] = '';
        case 'duplicates':
          value['rows'] = [
            ...(value['rows'] as List),
            Map<String, dynamic>.from((value['rows'] as List).single),
          ];
        case 'statuses':
          value['statuses'] = [1];
        case 'scope':
          value['company'] = 'B';
        case 'bound':
          value['rows'] = List.generate(26, (i) => {'name': 'INV-$i'});
        case 'more':
          value['has_more'] = 'yes';
      }
      expect(
        () => InvoiceRegisterPage.fromJson(value, company: 'A', pageSize: 25),
        throwsA(isA<ErpException>()),
      );
    });
  }
  test(
    'invoice register keeps optional masked values and old minimal responses',
    () {
      final page = InvoiceRegisterPage.fromJson(
        {
          'rows': [
            {'name': 'INV-1'},
          ],
        },
        company: 'A',
        pageSize: 25,
      );
      expect(page.rows.single, {'name': 'INV-1'});
      expect(page.canCreate, isFalse);
      expect(page.hasMore, isFalse);
    },
  );
  test('register paging, status and trimmed search preserve page size and raw offsets', () async {
    final repository = MemoryInvoiceRepository();
    final model = InvoiceRegisterViewModel(repository);
    addTearDown(model.dispose);
    await model.result;
    await model.nextPage();
    expect(repository.reads.last, ('', 'All', 25, 25));
    await model.chooseStatus('Draft');
    expect(repository.reads.last, ('', 'Draft', 0, 25));
    await model.search('  query  ');
    expect(repository.reads.last, ('query', 'Draft', 0, 25));
    await model.showAll();
    expect(repository.reads.last, ('', 'All', 0, 25));
    final count = repository.reads.length;
    await model.chooseStatus('Unsupported');
    expect(repository.reads, hasLength(count));
  });
  test('transient refresh failure retains authorized row actions; permission failure hides them', () async {
    final repository = MemoryInvoiceRepository();
    final model = InvoiceRegisterViewModel(repository);
    addTearDown(model.dispose);
    final page = await model.result;
    repository.pending = Completer<InvoiceRegisterPage>();
    final refresh = model.reload();
    expect(model.canOpen(page, 'INV-1'), isTrue);
    repository.pending!.completeError(const FormatException('Unavailable'));
    await expectLater(refresh, throwsFormatException);
    expect(model.canOpen(page, 'INV-1'), isTrue);
    repository.pending = null;
    repository.denied = true;
    await expectLater(model.reload(), throwsA(isA<ErpException>()));
    expect(model.canOpen(page, 'INV-1'), isFalse);
    expect(model.canManageSettings(page), isFalse);
  });
  for (final change in ['owner', 'access', 'dispose']) {
    test(
      'pending register rejects obsolete $change and clears row capabilities',
      () async {
        final repository = MemoryInvoiceRepository();
        final model = InvoiceRegisterViewModel(repository);
        addTearDown(() {
          if (change != 'dispose') model.dispose();
        });
        final page = await model.result;
        repository.pending = Completer<InvoiceRegisterPage>();
        final pending = model.reload();
        final expectation = expectLater(pending, throwsA(isA<ErpException>()));
        if (change == 'owner') repository.owner = Object();
        if (change == 'access') repository.current = 2;
        if (change == 'dispose') model.dispose();
        expect(model.canOpen(page, 'INV-1'), isFalse);
        repository.pending!.complete(page);
        await expectation;
      },
    );
  }
  test('a filter change hides prior rows and late failures cannot replace the current read', () async {
    final repository = MemoryInvoiceRepository();
    final model = InvoiceRegisterViewModel(repository);
    addTearDown(model.dispose);
    final oldPage = await model.result;
    final old = Completer<InvoiceRegisterPage>();
    repository.pending = old;
    final stale = model.reload();
    final failure = expectLater(stale, throwsA(isA<ErpException>()));
    repository.pending = null;
    final next = await model.search('new');
    old.completeError(const ErpException('Old denial', permissionDenied: true));
    await failure;
    expect(model.canOpen(oldPage, 'INV-1'), isFalse);
    expect(model.canOpen(next, 'INV-1'), isTrue);
  });
  test('unready constructors issue no invoice read', () async {
    final repository = MemoryInvoiceRepository()..current = null;
    final model = InvoiceRegisterViewModel(repository);
    addTearDown(model.dispose);
    await expectLater(model.result, throwsA(isA<ErpException>()));
    expect(repository.reads, isEmpty);
  });
  test('same-scope retained rows stay renderable and use the latest server capabilities', () async {
    final repository = MemoryInvoiceRepository();
    final model = InvoiceRegisterViewModel(repository);
    addTearDown(model.dispose);
    final old = await model.result;
    final value = invoiceRegisterData();
    value['can_create'] = false;
    value['can_manage_settings'] = false;
    (value['rows'] as List).single['can_print'] = false;
    repository.pending = Completer<InvoiceRegisterPage>();
    final refreshed = model.reload();
    repository.pending!.complete(
      InvoiceRegisterPage.fromJson(value, company: 'A', pageSize: 25),
    );
    await refreshed;
    expect(model.canUse(old), isTrue);
    expect(model.canCreate(old), isFalse);
    expect(model.canManageSettings(old), isFalse);
    expect(model.canOpen(old, 'INV-1', preview: true), isFalse);
    expect(model.canOpen(old, 'INV-1'), isTrue);
    repository.pending = null;
    repository.denied = true;
    await expectLater(model.reload(), throwsA(isA<ErpException>()));
    expect(model.canUse(old), isFalse);
    repository.denied = false;
    await model.reload();
    expect(model.canUse(old), isFalse);
  });
  test('a previously loaded result is unavailable until its access scope is revalidated', () async {
    final repository = MemoryInvoiceRepository();
    final model = InvoiceRegisterViewModel(repository);
    addTearDown(model.dispose);
    await model.result;
    repository.current = null;
    await expectLater(model.result, throwsA(isA<ErpException>()));
    repository.current = 2;
    await expectLater(model.result, throwsA(isA<ErpException>()));
    await model.revalidate();
    expect(model.canCreate(await model.result), isTrue);
  });
  test('concrete invoice repository fences a late transport read', () async {
    final api = _Api();
    addTearDown(api.close);
    final repository = ErpInvoiceRepository(api: api, company: 'A');
    final future = repository.register(
      query: 'saved',
      status: 'Draft',
      start: 25,
    );
    final failure = expectLater(future, throwsA(isA<ErpException>()));
    expect(api.args, ('A', 'saved', 'Draft', 25, 25));
    api.accessRevision++;
    api.pending.complete(invoiceRegisterData());
    await failure;
    api.accessReady = false;
    await expectLater(repository.register(), throwsA(isA<ErpException>()));
    expect(api.reads, 1);
  });
}

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  final pending = Completer<Map<String, dynamic>>();
  Object? args;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) {
    reads++;
    args = (company, query, status, start, limit);
    return pending.future;
  }
}
