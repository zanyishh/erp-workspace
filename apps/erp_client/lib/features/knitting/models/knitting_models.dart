import 'dart:math';

import '../../../core/models/erp_exception.dart' show ErpException;

String knittingJobTitle(Map<String, dynamic> job) {
  for (final key in ['source_reference_display', 'source_reference', 'name']) {
    final value = job[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return 'Order';
}

String knittingCustomerTitle(
  Map<String, dynamic> record, {
  String fallback = '—',
}) {
  for (final key in ['customer_name', 'customer']) {
    final value = record[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

String knittingDiameterTitle(Map record) {
  final value = record.containsKey('dia_display')
      ? record['dia_display']
      : record['dia'];
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '—' : text;
}

/// Fixed-point kilograms. Never round a business input on the client.
class Kg implements Comparable<Kg> {
  Kg._(this.milli);
  final BigInt milli;
  factory Kg.parse(String value) {
    if (!RegExp(r'^\d{1,10}(\.\d{1,3})?$').hasMatch(value)) {
      throw const FormatException(
        'Use kilograms with up to three decimal places.',
      );
    }
    final parts = value.split('.');
    final result = Kg._(
      BigInt.parse(parts[0]) * BigInt.from(1000) +
          BigInt.parse((parts.length == 2 ? parts[1] : '').padRight(3, '0')),
    );
    if (result.milli > BigInt.parse('1000000000000')) {
      throw const FormatException('The quantity exceeds the ERP limit.');
    }
    return result;
  }
  Kg operator +(Kg other) => Kg._(milli + other.milli);
  @override
  int compareTo(Kg other) => milli.compareTo(other.milli);
  @override
  String toString() =>
      '${milli ~/ BigInt.from(1000)}.${(milli.abs() % BigInt.from(1000)).toString().padLeft(3, '0')}';
}

class KnittingSnapshot {
  KnittingSnapshot(this.company, this.data);
  factory KnittingSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['company'] is! String) {
      throw const FormatException('Unsupported knitting workspace.');
    }
    return KnittingSnapshot(json['company'] as String, Map.unmodifiable(json));
  }
  final String company;
  final Map<String, dynamic> data;
  List<Map<String, dynamic>> rows(String key) => List.unmodifiable(
    (data[key] as List? ?? []).map(
      (e) => Map<String, dynamic>.unmodifiable(e as Map),
    ),
  );
  bool get financialRead => data['financial_read'] == true;
  bool get paginated => data['pagination'] is Map;
  Map<String, dynamic>? page(String key) {
    final value = (data['pagination'] as Map?)?[key];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }
}

enum CommandState {
  editing,
  posting,
  rejected,
  uncertain,
  checking,
  confirmed,
  stale,
}

class KnittingDraft {
  KnittingDraft(this.action, Map<String, dynamic> values, {String? requestId})
    : values = Map.unmodifiable(values),
      requestId =
          requestId ??
          'native-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
  final String action, requestId;
  final Map<String, dynamic> values;
  CommandState state = CommandState.editing;
  Map<String, dynamic>? result;
  String? error;
  Future<void> submit(Future<Map<String, dynamic>> Function() post) async {
    if (state != CommandState.editing) return;
    state = CommandState.posting;
    error = null;
    try {
      result = await post();
      state = CommandState.confirmed;
    } catch (e) {
      error = e.toString();
      state = switch (e) {
        ErpException(staleDocument: true) => CommandState.stale,
        ErpException(validationRejected: true) => CommandState.rejected,
        _ => CommandState.uncertain,
      };
    }
  }

  Future<void> check(Future<Map<String, dynamic>> Function() read) async {
    if (state != CommandState.uncertain) return;
    state = CommandState.checking;
    try {
      final value = await read();
      if (value['event'] is String &&
          (value['event'] as String).isNotEmpty &&
          value['data'] is Map) {
        result = value;
        state = CommandState.confirmed;
        error = null;
      } else {
        state = CommandState.uncertain;
        error = 'The save is not confirmed. Check again before starting another entry.';
      }
    } catch (e) {
      error = e.toString();
      state = CommandState.uncertain;
    }
  }
}
