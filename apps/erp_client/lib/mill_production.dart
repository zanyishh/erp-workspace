part of 'mill_overview.dart';

typedef _Entry = Map<String, dynamic>;

class _PostedDay {
  _PostedDay(this.date);
  final DateTime date;
  final entries = <_Entry>[];
  BigInt? milli = BigInt.zero;
  int? sourceCount;
  int get count => sourceCount ?? entries.length;

  void add(_Entry entry) {
    entries.add(entry);
    try {
      final value = (entry['result'] as Map?)?['quantity_kg'];
      final quantity = Kg.parse(value.toString());
      if (milli != null) milli = milli! + quantity.milli;
    } on FormatException {
      milli = null;
    }
  }
}

class _MillProductionChart extends StatefulWidget {
  const _MillProductionChart({
    required this.snapshot,
    required this.api,
    this.onOriginalProduction,
  });
  final ErpApi api;
  final KnittingSnapshot snapshot;
  final VoidCallback? onOriginalProduction;
  @override
  State<_MillProductionChart> createState() => _MillProductionChartState();
}

class _MillProductionChartState extends State<_MillProductionChart> {
  DateTime? selected;
  final days = <DateTime, _PostedDay>{};
  bool missingDate = false;
  int loaded = 0;

  @override
  void initState() {
    super.initState();
    aggregate();
  }

  @override
  void didUpdateWidget(covariant _MillProductionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) aggregate();
  }

  void aggregate() {
    days.clear();
    missingDate = false;
    final summary = (widget.snapshot.data['overview'] as Map?)?['production'];
    if (summary is List) {
      loaded = 0;
      for (final row in summary) {
        final date = DateTime.tryParse('${row['date']}T00:00:00Z');
        if (date == null) {
          missingDate = true;
          continue;
        }
        final day = _PostedDay(date);
        day.milli = _milli(row['quantity_kg']);
        day.sourceCount = (row['count'] as num?)?.toInt() ?? 0;
        loaded += day.count;
        days[date] = day;
      }
      if (!days.containsKey(selected)) selected = days.keys.lastOrNull;
      return;
    }
    if (widget.snapshot.data['overview'] is Map) {
      // A withheld company reconciliation must never become a first-page total.
      loaded = 0;
      selected = null;
      return;
    }
    final events = widget.snapshot.rows('events');
    loaded = events.length;
    final posted = <(DateTime, _Entry)>[];
    DateTime? latest;
    for (final event in events) {
      if (event['cancelled'] == 1 ||
          event['cancelled'] == true ||
          !const {
            'produce',
            'produce_bulk',
            'produce_batch',
          }.contains(event['kind'])) {
        continue;
      }
      // Frappe posts in the site's own calendar. Preserve the date part and ignore client timezone.
      final text = event['occurred_at']?.toString() ?? '';
      final prefix = RegExp(r'^\d{4}-\d{2}-\d{2}').stringMatch(text);
      final date = prefix == null
          ? null
          : DateTime.tryParse('${prefix}T00:00:00Z');
      if (date == null) {
        missingDate = true;
        continue;
      }
      posted.add((date, event));
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    if (latest == null) {
      selected = null;
      return;
    }
    for (var i = 6; i >= 0; i--) {
      final date = latest.subtract(Duration(days: i));
      days[date] = _PostedDay(date);
    }
    for (final (date, entry) in posted) {
      days[date]?.add(entry);
    }
    if (!days.containsKey(selected)) selected = latest;
  }

  void sources(_PostedDay day) {
    if (widget.snapshot.paginated) {
      _showMillSources(
        context,
        widget.api,
        (_) => KnittingSourcesDialog(
          api: widget.api,
          snapshot: widget.snapshot,
          collection: 'events',
          title: 'Production entries · ${DateFormat.yMMMd().format(day.date)}',
          productionDate: DateFormat('yyyy-MM-dd').format(day.date),
          row: (event) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(event['name'].toString()),
            subtitle: Text(event['job']?.toString() ?? 'Job unavailable'),
            trailing: Text(
              '${(event['result'] as Map?)?['quantity_kg'] ?? '—'} kg',
            ),
          ),
        ),
      );
      return;
    }
    _showMillSources(
      context,
      widget.api,
      (dialog) => AlertDialog(
        title: const Text('Production entries'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(DateFormat.yMMMd().format(day.date)),
              if (day.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No loaded production postings on this date.'),
                ),
              for (final event in day.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(event['name'].toString()),
                  subtitle: Text(event['job']?.toString() ?? 'Job unavailable'),
                  trailing: Text(
                    '${(event['result'] as Map?)?['quantity_kg'] ?? '—'} kg',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = days[selected];
    final complete =
        (widget.snapshot.data['overview'] as Map?)?['production'] is List;
    final hasSummary = widget.snapshot.data['overview'] is Map;
    final sourceAvailable = hasSummary
        ? complete
        : widget.snapshot.data['events'] is List;
    final peak = days.values
        .map((d) => d.milli?.toDouble() ?? 0.0)
        .fold<double>(0, math.max);
    return Panel(
      border: true,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Display('Posted production', size: 24),
                    if (day != null)
                      Text(
                        '${DateFormat.MMMd().format(days.keys.first)} – ${DateFormat.yMMMd().format(days.keys.last)}',
                        style: _meta,
                      ),
                  ],
                ),
              ),
              if (day != null)
                IconButton.outlined(
                  onPressed: () => sources(day),
                  tooltip: 'View production entries',
                  icon: const Icon(Icons.north_east, size: 16),
                ),
            ],
          ),
          if (widget.onOriginalProduction != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onOriginalProduction,
                icon: const Icon(Icons.history_outlined, size: 17),
                label: const Text('Original production records'),
              ),
            ),
          if (day == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                !sourceAvailable
                    ? hasSummary
                          ? 'Production totals are unavailable with the current source access.'
                          : 'Production entries unavailable.'
                    : missingDate
                    ? 'Production posting dates unavailable.'
                    : complete
                    ? 'No in-house production recorded.'
                    : 'No in-house production in the loaded postings.',
                style: _meta,
              ),
            )
          else ...[
            const SizedBox(height: 7),
            _bars(day, peak),
            const Divider(height: 12),
            Semantics(
              liveRegion: true,
              child: Wrap(
                spacing: 9,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    day.milli == null ? '— kg' : '${_quantity(day.milli!)} kg',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      height: 1.18,
                    ),
                  ),
                  Text(
                    '${DateFormat.MMMd().format(day.date)} · ${day.count} ${day.count == 1 ? 'entry' : 'entries'}',
                    style: _meta,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              complete
                  ? 'All $loaded production entries in this period'
                  : 'In-house output · $loaded loaded postings${missingDate ? ' · some dates unavailable' : ''}',
              style: _meta,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bars(_PostedDay selectedDay, double peakMilli) {
    final peakKg = peakMilli / 1000;
    final unit = math
        .pow(10, (math.log(peakKg == 0 ? 1 : peakKg) / math.ln10).floor())
        .toDouble();
    final top = [1, 2, 5, 10].firstWhere((n) => n * unit >= peakKg) * unit;
    const axisStyle = TextStyle(fontSize: 11, color: WorkspaceTheme.muted);
    final scaler = MediaQuery.textScalerOf(context);
    final labelHeight = scaler.scale(11) * 1.5;
    const plotHeight = 64.0;
    String tick(double kg) => kg == 0
        ? '0'
        : kg >= 1000
        ? NumberFormat.compact().format(kg)
        : NumberFormat('0.####').format(kg);
    final axisWidth = math.max(
      29.0,
      scaler.scale(7) * math.max(tick(top).length, tick(top / 2).length) + 5,
    );
    final minimumBarWidth = math.max(44.0, scaler.scale(30));
    return LayoutBuilder(
      builder: (context, box) {
        final plotWidth = math.max(
          box.maxWidth - axisWidth,
          minimumBarWidth * days.length,
        );
        final columns = <Widget>[
          for (final point in days.values)
            Expanded(
              child: _bar(
                point,
                selectedDay.date == point.date,
                top,
                plotHeight,
                labelHeight / 2,
                math.min(38, plotWidth / days.length * .55),
              ),
            ),
        ];
        final axes = SizedBox(
          width: axisWidth,
          height: plotHeight + labelHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final v in [top, top / 2, 0.0])
                Text(tick(v), style: axisStyle),
            ],
          ),
        );
        final plot = SizedBox(
          width: plotWidth,
          child: Stack(
            children: [
              for (final y in [0.0, .5, 1.0])
                Positioned(
                  top: labelHeight / 2 + y * plotHeight,
                  left: 0,
                  right: 0,
                  child: Divider(
                    height: 1,
                    color: y == 1
                        ? const Color(0xFF9E9F99)
                        : WorkspaceTheme.border,
                  ),
                ),
              Row(children: columns),
            ],
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            axes,
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: plot,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(
    _PostedDay point,
    bool active,
    double top,
    double plotHeight,
    double topInset,
    double width,
  ) {
    final qty = point.milli;
    final label =
        '${DateFormat.MMMd().format(point.date)} · ${qty == null ? 'Unknown weight' : '${_quantity(qty)} kg'}';
    void select() {
      if (!active) setState(() => selected = point.date);
    }

    final duration = workspaceMotion(context);
    final immediate = duration == Duration.zero ? ValueKey(active) : null;
    final bar = qty == null
        ? const Text('—', style: _meta)
        : AnimatedContainer(
            key: immediate,
            duration: duration,
            curve: Curves.easeOutCubic,
            width: width,
            height: math.max(2, plotHeight * (qty.toDouble() / 1000) / top),
            decoration: BoxDecoration(
              color: active ? WorkspaceTheme.peach : const Color(0xFF60615D),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          );
    final dateLabel = AnimatedContainer(
      key: immediate,
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: active ? WorkspaceTheme.charcoal : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        DateFormat('EEE').format(point.date),
        style: TextStyle(
          fontSize: 11,
          color: active ? WorkspaceTheme.light : WorkspaceTheme.muted,
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: select,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: select,
            borderRadius: BorderRadius.circular(7),
            child: Column(
              children: [
                SizedBox(
                  height: topInset + plotHeight,
                  child: Align(alignment: Alignment.bottomCenter, child: bar),
                ),
                const SizedBox(height: 4),
                dateLabel,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
