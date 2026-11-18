import 'dart:async';

import 'package:erp_client/features/imported_history/models/history_models.dart';
import 'package:erp_client/features/imported_history/presentation/history_filters_view_model.dart';
import 'package:erp_client/features/imported_history/presentation/history_choices_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_architecture_test.dart'
    show MemoryHistoryRepository, historyOptions;

class _ChoicesRepository extends MemoryHistoryRepository {
  Completer<HistoryChoicesPage>? waiting;
  final choices = <(String, String, String, int, Map<String, dynamic>)>[];
  @override
  Future<HistoryChoicesPage> options(
    String family,
    String field, {
    String query = '',
    int start = 0,
    Map<String, dynamic> filters = const {},
  }) {
    choices.add((family, field, query, start, filters));
    return waiting?.future ??
        Future.value(
          HistoryChoicesPage.fromJson(
            historyOptions(family: family, field: field, start: start),
            company: 'A',
            family: family,
            field: field,
            start: start,
          ),
        );
  }
}

void main() {
  test(
    'filter model validates calendar dates, range and no-original basis',
    () {
      final model = HistoryFiltersViewModel(
        MemoryHistoryRepository(),
        family: 'production',
        fields: ['source_book'],
      );
      addTearDown(model.dispose);
      expect(model.apply('2026-02-30', '2026-03-01'), isNull);
      expect(model.error, 'Use a valid YYYY-MM-DD date.');
      expect(model.apply('2026-03-02', '2026-03-01'), isNull);
      expect(model.error, 'From cannot follow Through.');
      expect(model.apply(' 2026-03-01 ', '2026-03-02'), {
        'date_basis': 'original',
        'from_date': '2026-03-01',
        'to_date': '2026-03-02',
      });
      model.selectBasis('no_original');
      expect(model.apply('invalid', 'invalid'), {'date_basis': 'no_original'});
    },
  );
  test(
    'source identity and display label remain separate in filter results',
    () {
      final model = HistoryFiltersViewModel(
        MemoryHistoryRepository(),
        family: 'production',
        fields: ['source_job'],
        initial: {'source_job': 'history-job-old'},
        labels: {'source_job': 'Old order'},
      );
      addTearDown(model.dispose);
      final intent = model.prepareChoice('source_job', '', '');
      expect(intent, isNotNull);
      expect(
        model.acceptChoice(intent!, {
          'value': 'history-job-new',
          'label': 'New original order',
        }),
        isTrue,
      );
      expect(model.selected['source_job'], 'history-job-new');
      expect(model.labels['source_job'], 'New original order');
      expect(model.apply('', ''), {'source_job': 'history-job-new'});
      model.clear('source_job');
      expect(model.selected, isEmpty);
      expect(model.labels, isEmpty);
    },
  );
  test(
    'stale choice results and filter apply are rejected after access changes',
    () {
      final repository = MemoryHistoryRepository();
      final model = HistoryFiltersViewModel(
        repository,
        family: 'job',
        fields: ['source_book'],
      );
      addTearDown(model.dispose);
      final intent = model.prepareChoice('source_book', '', '');
      repository.scope = 2;
      expect(model.valid, isFalse);
      expect(
        model.acceptChoice(intent!, {'value': null, 'label': 'No source book'}),
        isFalse,
      );
      expect(model.apply('', ''), isNull);
    },
  );
  test(
    'choices keep exact field/filter scope while paging and searching',
    () async {
      final repository = _ChoicesRepository();
      final model = HistoryChoicesViewModel(
        repository,
        family: 'production',
        field: 'source_job',
        filters: {'machine': '0'},
      );
      addTearDown(model.dispose);
      await model.settled;
      await model.nextPage();
      expect(model.start, 50);
      await model.search('  order  ');
      expect(model.start, 0);
      expect(model.query, 'order');
      expect(repository.choices.last.$1, 'production');
      expect(repository.choices.last.$2, 'source_job');
      expect(repository.choices.last.$3, 'order');
      expect(repository.choices.last.$5, {'machine': '0'});
      expect(model.canChoose(model.rows.single), isTrue);
    },
  );
  test('late choices cannot survive typing or revoked access', () async {
    final repository = _ChoicesRepository(),
        waiting = Completer<HistoryChoicesPage>();
    repository.waiting = waiting;
    final model = HistoryChoicesViewModel(
      repository,
      family: 'job',
      field: 'source_book',
      filters: {},
    );
    addTearDown(model.dispose);
    final old = model.settled;
    model.beginSearch();
    waiting.complete(
      HistoryChoicesPage.fromJson(
        historyOptions(),
        company: 'A',
        family: 'job',
        field: 'source_book',
        start: 0,
      ),
    );
    await old;
    expect(model.rows, isEmpty);
    repository.waiting = null;
    await model.search('latest');
    repository.scope = 2;
    model.invalidate();
    expect(model.rows, isEmpty);
    expect(model.hasMore, isFalse);
    expect(model.error, contains('access changed'));
  });
}
