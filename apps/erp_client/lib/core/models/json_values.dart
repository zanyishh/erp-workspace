import 'dart:convert';

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freeze(entry.value),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

Map<String, dynamic> immutableJsonMap(Map<String, dynamic> value) =>
    _freeze(value) as Map<String, dynamic>;

Map<String, dynamic> copyJsonMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
