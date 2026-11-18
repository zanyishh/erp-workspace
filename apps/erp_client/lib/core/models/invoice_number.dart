import 'dart:math' as math;

// Group the original decimal string directly. Long invoice numbers and large
// financial values must not pass through a floating-point conversion for display.
String formatInvoiceNumber(Object? raw, {int? places, bool indian = false}) {
  final source = raw?.toString().trim() ?? '';
  final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(source);
  if (match == null) return source;
  String whole = match[2]!, fraction = match[3] ?? '';
  final p = places?.clamp(0, 12);
  if (p != null) {
    final scaled = BigInt.parse(
      whole + fraction.padRight(p + 1, '0').substring(0, p),
    );
    final bump = fraction.length > p && fraction.codeUnitAt(p) >= 53;
    final rounded = (scaled + (bump ? BigInt.one : BigInt.zero))
        .toString()
        .padLeft(p + 1, '0');
    whole = rounded.substring(0, rounded.length - p);
    fraction = p == 0 ? '' : rounded.substring(rounded.length - p);
  } else {
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  }
  final groups = <String>[];
  var end = whole.length;
  var width = 3;
  while (end > 0) {
    final begin = math.max(0, end - width);
    groups.add(whole.substring(begin, end));
    end = begin;
    if (indian) width = 2;
  }
  return '${match[1]}${groups.reversed.join(',')}${fraction.isEmpty ? '' : '.$fraction'}';
}
