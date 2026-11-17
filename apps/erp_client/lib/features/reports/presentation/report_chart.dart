import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/design.dart';
import '../models/native_reports.dart';
import '../../../core/ui/widgets.dart';

const _colors = [
  Color(0xff925334),
  Color(0xff386c68),
  Color(0xff565784),
  Color(0xff826111),
  Color(0xff73556c),
  Color(0xff41688c),
];

class ReportChart extends StatefulWidget {
  const ReportChart({super.key, required this.chart});
  final NativeReportChart chart;

  @override
  State<ReportChart> createState() => _ReportChartState();
}

class _ReportChartState extends State<ReportChart> {
  int _point = 0;

  @override
  void didUpdateWidget(ReportChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart != widget.chart) _point = 0;
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    return Panel(
      border: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            chart.title.isEmpty ? 'Chart' : chart.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: SizedBox(
              height: 148,
              child: CustomPaint(painter: _Plot(chart, _point)),
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous chart value',
                onPressed: _point == 0 ? null : () => setState(() => _point--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    chart.labels[_point],
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next chart value',
                onPressed: _point + 1 >= chart.labels.length
                    ? null
                    : () => setState(() => _point++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final (index, series) in chart.series.indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color:
                          _colors[(chart.distribution ? _point : index) %
                              _colors.length],
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: Text(series.name)),
                    const SizedBox(width: 6),
                    Text(_amount(series.values[_point], chart.currency)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _amount(double? value, String currency) {
    if (value == null) return '—';
    final number = NumberFormat('#,##0.########').format(value);
    return currency.isEmpty ? number : '$currency $number';
  }
}

class _Plot extends CustomPainter {
  _Plot(this.chart, this.point);
  final NativeReportChart chart;
  final int point;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final area = Offset.zero & size;
    if (chart.distribution) {
      final totals = chart.series.first.values;
      final total = totals.fold<double>(0, (a, b) => a + (b ?? 0));
      if (total <= 0) return;
      final rect = Rect.fromCenter(
        center: area.center,
        width: size.shortestSide - 10,
        height: size.shortestSide - 10,
      );
      var start = -math.pi / 2;
      for (final (i, v) in totals.indexed) {
        final fraction = (v ?? 0) / total;
        paint.color = _colors[i % _colors.length];
        if (chart.kind == 'percentage') {
          final left = (start + math.pi / 2) / (2 * math.pi) * size.width;
          canvas.drawRect(
            Rect.fromLTWH(
              left,
              size.height / 2 - 12,
              size.width * fraction,
              24,
            ),
            paint,
          );
        } else {
          canvas.drawArc(rect, start, 2 * math.pi * fraction, true, paint);
        }
        start += 2 * math.pi * fraction;
      }
      if (chart.kind == 'donut') {
        canvas.drawCircle(
          area.center,
          rect.width * .28,
          paint..color = WorkspaceTheme.surface,
        );
      }
      return;
    }
    final all = chart.series.expand((s) => s.values).whereType<double>();
    if (all.isEmpty) return;
    final low = math.min(0.0, all.reduce(math.min));
    final high = math.max(0.0, all.reduce(math.max));
    final bounds = area.deflate(6);
    double y(double v) => high == low
        ? bounds.center.dy
        : bounds.bottom - (v - low) / (high - low) * bounds.height;
    final step = bounds.width / chart.labels.length;
    double x(int i) => bounds.left + (i + .5) * step;
    final bars = chart.series.where((s) => s.kind == 'bar').toList();
    canvas.drawLine(
      Offset(bounds.left, y(0)),
      Offset(bounds.right, y(0)),
      paint..color = Colors.black38,
    );
    final bw = bars.isEmpty ? 0.0 : step * .72 / bars.length;
    for (final (si, s) in chart.series.indexed) {
      paint.color = _colors[si % _colors.length];
      paint.strokeWidth = 2;
      Offset? previous;
      for (final (i, v) in s.values.indexed) {
        if (v == null) {
          previous = null;
          continue;
        }
        final pos = Offset(x(i), y(v));
        if (s.kind == 'bar') {
          final left = x(i) - step * .36 + bars.indexOf(s) * bw;
          canvas.drawRect(
            Rect.fromLTRB(
              left,
              math.min(y(0), pos.dy),
              left + bw,
              math.max(y(0), pos.dy),
            ),
            paint,
          );
        } else {
          if (previous != null) canvas.drawLine(previous, pos, paint);
          if (i == point || chart.labels.length == 1) {
            canvas.drawCircle(pos, 3.5, paint);
          }
        }
        previous = pos;
      }
    }
    canvas.drawLine(
      Offset(x(point), bounds.top),
      Offset(x(point), bounds.bottom),
      paint
        ..color = Colors.black26
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_Plot old) => chart != old.chart || point != old.point;
}
