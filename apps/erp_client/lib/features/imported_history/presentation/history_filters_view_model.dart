import 'package:flutter/foundation.dart';

import '../../../core/models/json_values.dart';
import '../data/history_repository.dart';
import '../models/history_filter_values.dart';

class HistoryChoiceIntent {
  HistoryChoiceIntent._(
    this._owner,
    this._scope,
    this._version,
    this.family,
    this.field,
    Map<String, dynamic> values,
  ) : filters = immutableJsonMap(values);
  final Object _owner, _scope;
  final int _version;
  final String family, field;
  final Map<String, dynamic> filters;
}

class HistoryFiltersViewModel extends ChangeNotifier {
  HistoryFiltersViewModel(
    this._repository, {
    required this.family,
    required List<String> fields,
    Map<String, dynamic> initial = const {},
    Map<String, String> labels = const {},
  }) : _owner = _repository.identity,
       _openedScope = _repository.scope,
       fields = List.unmodifiable(fields),
       _selected = copyJsonMap(initial)
         ..removeWhere((key, _) => !historyFilterLabels.containsKey(key)),
       _labels = Map.from(labels),
       _from = initial['from_date'] as String? ?? '',
       _to = initial['to_date'] as String? ?? '',
       _basis = initial['date_basis'] as String? ?? '';
  final ImportedHistoryRepository _repository;
  final Object _owner;
  final Object? _openedScope;
  final String family;
  final List<String> fields;
  final Map<String, dynamic> _selected;
  final Map<String, String> _labels;
  String _from, _to, _basis;
  String? _error;
  bool _disposed = false;
  int _version = 0;
  bool get valid =>
      !_disposed &&
      _owner == _repository.identity &&
      _openedScope != null &&
      _openedScope == _repository.scope;
  String get from => _from;
  String get to => _to;
  String get basis => _basis;
  String? get error => _error;
  Map<String, dynamic> get selected =>
      valid ? Map.unmodifiable(_selected) : const {};
  Map<String, String> get labels =>
      valid ? Map.unmodifiable(_labels) : const {};
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void invalidate() {
    _version++;
    _notify();
  }

  void selectBasis(String value) {
    if (!valid || !historyDateLabels.containsKey(value)) return;
    _basis = value;
    _error = null;
    _version++;
    if (value == 'no_original') {
      _from = '';
      _to = '';
    }
    _notify();
  }

  void clear(String field) {
    if (!valid) return;
    _selected.remove(field);
    _labels.remove(field);
    _version++;
    _notify();
  }

  bool validate(String from, String to) {
    if (!valid) return false;
    if (_from != from || _to != to) _version++;
    _from = from;
    _to = to;
    for (final text in [from.trim(), to.trim()]) {
      if (text.isEmpty || _basis == 'no_original') continue;
      final parsed = DateTime.tryParse(text);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != text) {
        _error = 'Use a valid YYYY-MM-DD date.';
        _notify();
        return false;
      }
    }
    if (_basis != 'no_original' &&
        from.isNotEmpty &&
        to.isNotEmpty &&
        from.compareTo(to) > 0) {
      _error = 'From cannot follow Through.';
      _notify();
      return false;
    }
    _error = null;
    _notify();
    return true;
  }

  Map<String, dynamic> _values() => {
    ..._selected,
    if (_basis.isNotEmpty || _from.trim().isNotEmpty || _to.trim().isNotEmpty)
      'date_basis': _basis.isEmpty ? 'original' : _basis,
    if (_basis != 'no_original' && _from.trim().isNotEmpty)
      'from_date': _from.trim(),
    if (_basis != 'no_original' && _to.trim().isNotEmpty) 'to_date': _to.trim(),
  };
  Map<String, dynamic>? apply(String from, String to) =>
      validate(from, to) ? _values() : null;
  HistoryChoiceIntent? prepareChoice(String field, String from, String to) {
    if (!fields.contains(field) || !validate(from, to)) return null;
    return HistoryChoiceIntent._(
      this,
      _openedScope!,
      _version,
      family,
      field,
      _values(),
    );
  }

  bool acceptChoice(HistoryChoiceIntent intent, Map<String, dynamic> row) {
    if (!valid ||
        !identical(intent._owner, this) ||
        intent._scope != _repository.scope ||
        intent._version != _version ||
        !fields.contains(intent.field) ||
        row['label'] is! String ||
        !(row['value'] is String ||
            row['value'] == null && intent.field == 'source_book')) {
      return false;
    }
    _selected[intent.field] = row['value'];
    _labels[intent.field] = row['label'] as String;
    _version++;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _version++;
    _selected.clear();
    _labels.clear();
    super.dispose();
  }
}
