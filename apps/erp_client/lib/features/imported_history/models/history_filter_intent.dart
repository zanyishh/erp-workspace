import '../../../core/models/json_values.dart';

class HistoryFilterIntent {
  HistoryFilterIntent({
    required this._owner,
    required this._scope,
    required this._generation,
    required this.family,
    required List<String> fields,
    required Map<String, dynamic> filters,
    required Map<String, String> labels,
  }) : fields = List.unmodifiable(fields),
       filters = immutableJsonMap(filters),
       labels = Map.unmodifiable(labels);
  final Object _owner, _scope;
  final int _generation;
  final String family;
  final List<String> fields;
  final Map<String, dynamic> filters;
  final Map<String, String> labels;
  bool belongsTo(Object owner, Object scope, int generation, String family) =>
      identical(owner, _owner) &&
      scope == _scope &&
      generation == _generation &&
      family == this.family;
}
