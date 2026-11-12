// Evaluate data-only condition trees. No JavaScript or arbitrary methods run here.
bool conditionTruth(Object? value) =>
    value != null &&
    value != false &&
    value != '' &&
    value != 0 &&
    !(value is num && value.isNaN);
num _number(Object? value) {
  if (value == null || value == '') return 0;
  if (value is bool) return value ? 1 : 0;
  return num.tryParse(value.toString()) ?? double.nan;
}

bool _equal(Object? a, Object? b, bool strict) {
  if (a == b) return true;
  if (strict || a == null || b == null || a is String && b is String) {
    return false;
  }
  return _number(a) == _number(b);
}

Object? _value(
  Map<String, dynamic> node,
  Map<String, dynamic> doc,
  Map<String, dynamic> parent,
) {
  final op = node['op'];
  final args = (node['args'] as List? ?? []).cast<Map<String, dynamic>>();
  Object? arg(int i) => i < args.length ? _value(args[i], doc, parent) : null;
  switch (op) {
    case 'literal':
      return node['value'];
    case 'context':
      return node['name'] == 'parent' ? parent : doc;
    case 'field':
      final v = doc[node['name']];
      return v is List ? v.isNotEmpty : conditionTruth(v);
    case 'array':
      return [
        for (final n in node['values'] as List)
          _value(n as Map<String, dynamic>, doc, parent),
      ];
    case 'get':
      final target = _value(
        node['object'] as Map<String, dynamic>,
        doc,
        parent,
      );
      final key = _value(node['key'] as Map<String, dynamic>, doc, parent);
      if (key == 'length' && (target is List || target is String)) {
        return target is List ? target.length : (target as String).length;
      }
      if (target is Map) return target[key];
      if (target is List &&
          key is num &&
          key == key.truncate() &&
          key >= 0 &&
          key < target.length) {
        return target[key.toInt()];
      }
      return null;
    case '!':
      return !conditionTruth(arg(0));
    case '&&':
      final left = arg(0);
      return conditionTruth(left) ? arg(1) : left;
    case '||':
      final left = arg(0);
      return conditionTruth(left) ? left : arg(1);
    case '??':
      return arg(0) ?? arg(1);
    case '?':
      return conditionTruth(arg(0)) ? arg(1) : arg(2);
    case '===':
      return _equal(arg(0), arg(1), true);
    case '!==':
      return !_equal(arg(0), arg(1), true);
    case '==':
      return _equal(arg(0), arg(1), false);
    case '!=':
      return !_equal(arg(0), arg(1), false);
    case '+':
      if (args.length == 1) return _number(arg(0));
      final a = arg(0), b = arg(1);
      return a is String || b is String
          ? '${a ?? 'null'}${b ?? 'null'}'
          : _number(a) + _number(b);
    case '-':
      return args.length == 1
          ? -_number(arg(0))
          : _number(arg(0)) - _number(arg(1));
    case '*':
      return _number(arg(0)) * _number(arg(1));
    case '/':
      return _number(arg(0)) / _number(arg(1));
    case '>':
      return _compare(arg(0), arg(1), (a, b) => a > b);
    case '>=':
      return _compare(arg(0), arg(1), (a, b) => a >= b);
    case '<':
      return _compare(arg(0), arg(1), (a, b) => a < b);
    case '<=':
      return _compare(arg(0), arg(1), (a, b) => a <= b);
    case 'call':
      if (node['method'] == 'in_list') {
        final list = arg(0);
        return list is List && list.any((v) => _equal(v, arg(1), true));
      }
      if (!const {'cint', 'flt'}.contains(node['method'])) {
        throw const FormatException('Unsupported native condition call.');
      }
      final n = _number(arg(0));
      return node['method'] == 'cint'
          ? (n.isFinite ? n.toInt() : 0)
          : (n.isFinite ? n : 0);
    case 'method':
      final target = _value(
        node['object'] as Map<String, dynamic>,
        doc,
        parent,
      );
      final first = arg(0);
      switch (node['method']) {
        case 'includes':
          return target is List
              ? target.any((v) => _equal(v, first, true))
              : target is String &&
                    target.contains(first?.toString() ?? 'null');
        case 'indexOf':
          return target is List
              ? target.indexWhere((v) => _equal(v, first, true))
              : target is String
              ? target.indexOf(first?.toString() ?? 'null')
              : -1;
        case 'startsWith':
          return target is String &&
              target.startsWith(first?.toString() ?? 'null');
        case 'endsWith':
          return target is String &&
              target.endsWith(first?.toString() ?? 'null');
        case 'toLowerCase':
          return target is String ? target.toLowerCase() : null;
        case 'toUpperCase':
          return target is String ? target.toUpperCase() : null;
      }
  }
  throw const FormatException('Unsupported native condition.');
}

bool _compare(Object? a, Object? b, bool Function(num, num) compare) {
  if (a is String && b is String) return compare(a.compareTo(b), 0);
  return compare(_number(a), _number(b));
}

bool? evaluateCondition(
  Map<String, dynamic>? node,
  Map<String, dynamic> doc, {
  Map<String, dynamic> parent = const {},
}) {
  if (node == null || node['op'] == 'unsupported') return null;
  try {
    return conditionTruth(_value(node, doc, parent));
  } on FormatException {
    return null;
  }
}
