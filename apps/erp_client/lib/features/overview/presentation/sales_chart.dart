import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'sales_chart_view_model.dart';

import '../../../core/ui/design.dart';
import '../../../core/models/erp_models.dart';
import '../../../core/ui/workspace_ui.dart';
import '../../../core/ui/workspace_art.dart';
import '../../../core/ui/widgets.dart';

const _muted = WorkspaceTheme.muted;
const _accent = Color(0xFFA35631);

DateTime _date(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

class SalesChart extends StatefulWidget {
  const SalesChart({super.key, required this.data, this.range});
  final ErpSnapshot data;
  final DateRange? range;

  @override
  State<SalesChart> createState() => _SalesChartState();
}

class _SalesChartState extends State<SalesChart> {
  late final _model = SalesChartViewModel(widget.data, range: widget.range);
  List<SalesDay> get buckets => _model.buckets;
  int get selected => _model.selected;
  bool get monthly => _model.monthly;
  @override
  void didUpdateWidget(covariant SalesChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _model.update(widget.data, range: widget.range);
  }

  String _label(DateTime date) =>
      (monthly ? DateFormat.yMMM() : DateFormat.yMMMd()).format(date);

  String _reading(int index) =>
      '${_label(buckets[index].day)}, ${money(buckets[index].amount, widget.data.currency)}';

  void _select(int index) {
    if (_model.select(index)) {
      setState(() {});
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
      border: true,
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Display('BILLED SALES', size: 23),
                    Text(
                      money(data.billed, data.currency),
                      style: TextStyle(
                        fontSize: compact ? 26 : 31,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: -.9,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const WorkspaceArt(ArtObject.sales, width: 74, height: 52),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 10,
            runSpacing: 3,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Posted sales invoices · ${data.currency}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              if (dateRange != null)
                Text(
                  dateRange,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  Icon(
                    data.invoicesAvailable
                        ? Icons.show_chart
                        : Icons.lock_outline,
                    color: _muted,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.invoicesAvailable
                          ? 'No posted invoices yet'
                          : 'Invoice access unavailable',
                      style: const TextStyle(color: _muted),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _plot(context),
            const Divider(height: 12, thickness: .7),
            _reader(),
          ],
        ],
      ),
    );
  }

  Widget _reader() {
    final day = buckets[selected];
    final unit = monthly ? 'month' : 'day';
    final text =
        '${_label(day.day)} · ${money(day.amount, widget.data.currency)}';
    Widget step(int offset, IconData icon, String label) {
      final next = selected + offset;
      return IconButton(
        style: ButtonStyle(animationDuration: workspaceMotion(context)),
        tooltip: '$label $unit',
        onPressed: next >= 0 && next < buckets.length
            ? () => _select(next)
            : null,
        color: WorkspaceTheme.ink,
        disabledColor: const Color(0xFF92938D),
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
                    color: WorkspaceTheme.ink,
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
          height: 82 + labelHeight,
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
                                      workspaceReduceMotion(context)
                                          ? selected.toDouble()
                                          : cursor.clamp(0, buckets.length - 1),
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
          ? const Color(0xFF9A9A94)
          : const Color(0xFFD3D3CC);
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
            colors: [Color(0x76EBBE9F), Color(0x07E6AE88)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = WorkspaceTheme.charcoal
          ..strokeWidth = 2.2
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
      ..color = const Color(0xFF8D8D88)
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
    canvas.drawCircle(position, 2, Paint()..color = WorkspaceTheme.light);
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      old.buckets != buckets ||
      old.cursor != cursor ||
      old.low != low ||
      old.high != high ||
      old.step != step;
}
