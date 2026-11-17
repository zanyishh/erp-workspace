import 'package:flutter/material.dart';

/// DateTime.parse normalizes invalid dates (31 February). Entry validation must
/// preserve the exact calendar date the operator typed.
bool validEntryDate(String value, {required bool withTime}) {
  final match = RegExp(
    withTime
        ? r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$'
        : r'^(\d{4})-(\d{2})-(\d{2})$',
  ).firstMatch(value);
  if (match == null) return false;
  final y = int.parse(match[1]!),
      m = int.parse(match[2]!),
      d = int.parse(match[3]!);
  final parsed = DateTime(y, m, d);
  return y >= 1 &&
      parsed.year == y &&
      parsed.month == m &&
      parsed.day == d &&
      (!withTime ||
          int.parse(match[4]!) < 24 &&
              int.parse(match[5]!) < 60 &&
              int.parse(match[6] ?? '0') < 60);
}

class DateEntry extends StatefulWidget {
  const DateEntry({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.withTime = false,
    this.optional = false,
    this.enabled = true,
  });
  final String label, initialValue;
  final ValueChanged<String> onChanged;
  final bool withTime, optional, enabled;
  @override
  State<DateEntry> createState() => _DateEntryState();
}

class _DateEntryState extends State<DateEntry> {
  late final controller = TextEditingController(text: widget.initialValue);
  @override
  void didUpdateWidget(covariant DateEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        controller.text != widget.initialValue) {
      controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final apply = widget.onChanged;
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.year < 1900 || initial.year > 2200
          ? DateTime.now()
          : initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (date == null || !mounted || !widget.enabled) return;
    String value = date.toIso8601String().split('T').first;
    if (widget.withTime) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (time == null || !mounted || !widget.enabled) return;
      value +=
          ' ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    controller.text = value;
    apply(value);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    enabled: widget.enabled,
    keyboardType: TextInputType.datetime,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.withTime ? 'YYYY-MM-DD HH:MM' : 'YYYY-MM-DD',
      suffixIcon: IconButton(
        tooltip: 'Choose ${widget.label}',
        onPressed: widget.enabled ? pick : null,
        icon: const Icon(Icons.calendar_today_outlined),
      ),
    ),
    onChanged: widget.onChanged,
    validator: (value) => value == null || value.trim().isEmpty
        ? widget.optional
              ? null
              : 'Enter ${widget.label.toLowerCase()}.'
        : validEntryDate(value.trim(), withTime: widget.withTime)
        ? null
        : widget.withTime
        ? 'Enter a valid date and time (YYYY-MM-DD HH:MM).'
        : 'Enter a valid date (YYYY-MM-DD).',
  );
}
