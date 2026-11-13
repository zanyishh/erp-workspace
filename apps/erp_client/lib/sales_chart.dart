import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'design.dart';
import 'erp_models.dart';
import 'ui/workspace_ui.dart';
import 'widgets.dart';

const _muted = Color(0xFFBCC9C2);
const _accent = Color(0xFFFFAE80);

String invoiceMoney(num? value, String currency) {
  if (value == null) return '—';
  final format = NumberFormat.simpleCurrency(
    name: currency,
    locale: currency == 'INR' ? 'en_IN' : 'en_US',
    decimalDigits: value % 1 == 0 ? 0 : null,
  );
  return format.format(value);
}

class SalesChart extends StatefulWidget {
  const SalesChart({super.key, required this.data, this.range});
  final ErpSnapshot data;
  final DateRange? range;

  @override
  State<SalesChart> createState() => _SalesChartState();
}

DateTime _date(DateTime d) => DateTime.utc(d.year, d.month, d.day);

class _SalesChartState extends State<SalesChart> {
  List<SalesDay> buckets = [];
  int selected = 0;
  bool monthly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SalesChart old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data ||
        old.range?.start != widget.range?.start ||
        old.range?.end != widget.range?.end) {
      _load();
    }
  }

  void _load() {
    final sales = widget.data.sales;
    if (!widget.data.invoicesAvailable || sales.isEmpty) {
      buckets = [];
      return;
    }
    // ERPNext groups submitted invoices by posting date. Missing dates within
    // a permitted, loaded period therefore contribute zero to its total.
    final first = _date(widget.range?.start ?? sales.first.day);
    final lastExclusive = widget.range == null
        ? _date(sales.last.day).add(const Duration(days: 1))
        : _date(widget.range!.end);
    monthly = lastExclusive.difference(first).inDays > 62;
    DateTime bucket(DateTime d) =>
        monthly ? DateTime.utc(d.year, d.month) : _date(d);
    final totals = <DateTime, double>{};
    for (final day in sales) {
      final date = _date(day.day);
      if (date.isBefore(first) || !date.isBefore(lastExclusive)) continue;
      final key = bucket(date);
      totals[key] = (totals[key] ?? 0) + day.amount;
    }
    buckets = totals.isEmpty
        ? []
        : [
            for (
              var date = bucket(first);
              date.isBefore(lastExclusive);
              date = monthly
                  ? DateTime.utc(date.year, date.month + 1)
                  : date.add(const Duration(days: 1))
            )
              SalesDay(date, totals[date] ?? 0),
          ];
    selected = buckets.lastIndexWhere((b) => totals.containsKey(b.day));
  }

  String _label(DateTime date) =>
      (monthly ? DateFormat.yMMM() : DateFormat.yMMMd()).format(date);

  String _reading(int index) =>
      '${_label(buckets[index].day)}, ${invoiceMoney(buckets[index].amount, widget.data.currency)}';

  void _select(int index) {
    if (index >= 0 && index < buckets.length && index != selected) {
      setState(() => selected = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final compact = MediaQuery.sizeOf(context).width < 660;
    final pad = compact ? 17.0 : 24.0;
    final range = widget.range;
    final dateRange = range == null
        ? null
        : '${DateFormat.MMMd().format(range.start)} – ${DateFormat.yMMMd().format(_date(range.end).subtract(const Duration(days: 1)))}';
    return Panel(
      dark: true,
      frosted: true,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(.72, -1.1),
            radius: 1.28,
            colors: [Color(0xAD465951), Color(0x00394941)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  const Text(
                    'BILLED SALES',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (dateRange != null)
                    Text(
                      dateRange,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                invoiceMoney(data.billed, data.currency),
                style: TextStyle(
                  fontSize: compact ? 35 : 46,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.7,
                  height: 1.1,
                  color: WorkspaceTheme.light,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Posted sales invoices · ${data.currency}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 19),
              if (buckets.isEmpty)
                Container(
                  constraints: const BoxConstraints(minHeight: 168),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x25202C29),
                    border: Border.all(color: const Color(0xFF505B54)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        data.invoicesAvailable
                            ? Icons.show_chart
                            : Icons.lock_outline,
                        color: _muted,
                        size: 26,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.invoicesAvailable
                            ? 'No posted invoices yet'
                            : 'Invoice access unavailable',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: WorkspaceTheme.light),
                      ),
                    ],
                  ),
                )
              else ...[
                _plot(context),
                const Divider(
                  color: Color(0xFF4B5851),
                  height: 20,
                  thickness: .8,
                ),
                _reader(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _reader() {
    final day = buckets[selected];
    final unit = monthly ? 'month' : 'day';
    final text =
        '${_label(day.day)} · ${invoiceMoney(day.amount, widget.data.currency)}';
    Widget step(int offset, IconData icon, String label) {
      final next = selected + offset;
      return IconButton(
        tooltip: '$label $unit',
        onPressed: next >= 0 && next < buckets.length
            ? () => _select(next)
            : null,
        color: WorkspaceTheme.light,
        disabledColor: const Color(0xFF86918C),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(icon, size: 19),
      );
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: _accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                monthly ? 'Monthly sales' : 'Daily sales',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: const TextStyle(
                    color: WorkspaceTheme.light,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        step(-1, Icons.chevron_left, 'Previous'),
        step(1, Icons.chevron_right, 'Next'),
      ],
    );
  }

  Widget _plot(BuildContext context) {
    final scale = SalesScale(buckets.map((e) => e.amount));
    // Two to four readable intervals keep both signs and the zero axis visible.
    final roughStep = ((scale.maximum - scale.minimum) / 3).abs();
    final magnitude = math
        .pow(10, (math.log(roughStep == 0 ? 1 : roughStep) / math.ln10).floor())
        .toDouble();
    final step =
        [1, 2, 5, 10].firstWhere((n) => n * magnitude >= roughStep) * magnitude;
    final low = (scale.minimum / step).floor();
    final high = math.max(low + 1, (scale.maximum / step).ceil());
    final format = NumberFormat.compact(locale: 'en_US');
    final axisStyle = const TextStyle(fontSize: 11, color: _muted);
    String amountLabel(double value) => value == 0
        ? '0'
        : value.abs() < 1
        ? NumberFormat.decimalPatternDigits(
            decimalDigits: math.min(
              8,
              math.max(0, -(math.log(step) / math.ln10).floor()),
            ),
          ).format(value)
        : format.format(value);
    final ticks = [for (int i = high; i >= low; i--) amountLabel(i * step)];
    final scaler = MediaQuery.textScalerOf(context);
    final metrics = ticks
        .map(
          (t) => TextPainter(
            text: TextSpan(text: t, style: axisStyle),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout(),
        )
        .toList();
    final labelWidth = metrics.map((p) => p.width).reduce(math.max) + 10;
    final labelHeight = metrics.first.height;
    for (final p in metrics) {
      p.dispose();
    }
    String tickDate(int i) =>
        (monthly ? DateFormat.MMM() : DateFormat.MMMd()).format(buckets[i].day);

    return Column(
      children: [
        SizedBox(
          height: 148 + labelHeight,
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final label in ticks) Text(label, style: axisStyle),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    const inset = 5.0;
                    int nearest(double dx) =>
                        (((dx - inset) /
                                    math.max(1, box.maxWidth - inset * 2)) *
                                (buckets.length - 1))
                            .round()
                            .clamp(0, buckets.length - 1);
                    return Semantics(
                      label: monthly
                          ? 'Monthly sales chart'
                          : 'Daily sales chart',
                      value: _reading(selected),
                      increasedValue: selected < buckets.length - 1
                          ? _reading(selected + 1)
                          : null,
                      decreasedValue: selected > 0
                          ? _reading(selected - 1)
                          : null,
                      onIncrease: selected < buckets.length - 1
                          ? () => _select(selected + 1)
                          : null,
                      onDecrease: selected > 0
                          ? () => _select(selected - 1)
                          : null,
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.arrowLeft,
                          ): () =>
                              _select(selected - 1),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowRight,
                          ): () =>
                              _select(selected + 1),
                        },
                        child: Focus(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.precise,
                            onHover: (event) =>
                                _select(nearest(event.localPosition.dx)),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              excludeFromSemantics: true,
                              onTapUp: (e) =>
                                  _select(nearest(e.localPosition.dx)),
                              onHorizontalDragUpdate: (e) =>
                                  _select(nearest(e.localPosition.dx)),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: labelHeight / 2,
                                  horizontal: inset,
                                ),
                                child: TweenAnimationBuilder<double>(
                                  duration: workspaceMotion(context),
                                  curve: Curves.easeOutCubic,
                                  tween: Tween<double>(
                                    begin: selected.toDouble(),
                                    end: selected.toDouble(),
                                  ),
                                  builder: (_, cursor, _) => CustomPaint(
                                    size: Size.infinite,
                                    painter: _SeriesPainter(
                                      buckets,
                                      low,
                                      high,
                                      step,
                                      cursor.clamp(0, buckets.length - 1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: labelWidth, top: 3),
          child: Row(
            mainAxisAlignment: buckets.length == 1
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              Text(tickDate(0), style: axisStyle),
              if (buckets.length >= 5 && scaler.scale(12) < 19)
                Text(tickDate((buckets.length - 1) ~/ 2), style: axisStyle),
              if (buckets.length > 1)
                Text(tickDate(buckets.length - 1), style: axisStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeriesPainter extends CustomPainter {
  const _SeriesPainter(
    this.buckets,
    this.low,
    this.high,
    this.step,
    this.cursor,
  );
  final List<SalesDay> buckets;
  final int low, high;
  final double step, cursor;

  @override
  void paint(Canvas canvas, Size size) {
    double y(double value) =>
        size.height * (high - value / step) / (high - low);
    double x(double index) => buckets.length == 1
        ? size.width / 2
        : size.width * index / (buckets.length - 1);
    final grid = Paint()..strokeWidth = .7;
    for (int tick = low; tick <= high; tick++) {
      grid.color = tick == 0
          ? const Color(0xFF78867D)
          : const Color(0xFF505E55);
      canvas.drawLine(
        Offset(0, y(tick * step)),
        Offset(size.width, y(tick * step)),
        grid,
      );
    }
    final line = Path()..moveTo(x(0), y(buckets[0].amount));
    for (var i = 1; i < buckets.length; i++) {
      line.lineTo(x(i.toDouble()), y(buckets[i].amount));
    }
    if (buckets.length > 1) {
      final fill = Path.from(line)
        ..lineTo(size.width, y(0))
        ..lineTo(0, y(0))
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66FDB488), Color(0x13E6AE88)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = _accent
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    final fraction = cursor - cursor.floor();
    final amount =
        buckets[cursor.floor()].amount * (1 - fraction) +
        buckets[cursor.ceil()].amount * fraction;
    final position = Offset(x(cursor), y(amount));
    final guide = Paint()
      ..color = const Color(0xAAAEBDB3)
      ..strokeWidth = .8;
    for (var dy = 0.0; dy < size.height; dy += 7) {
      canvas.drawLine(
        Offset(position.dx, dy),
        Offset(position.dx, math.min(size.height, dy + 3)),
        guide,
      );
    }
    canvas.drawCircle(position, 7.5, Paint()..color = const Color(0x46FFAE80));
    canvas.drawCircle(position, 4.5, Paint()..color = _accent);
    canvas.drawCircle(position, 2, Paint()..color = const Color(0xFF39433B));
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      old.buckets != buckets ||
      old.cursor != cursor ||
      old.low != low ||
      old.high != high ||
      old.step != step;
}
