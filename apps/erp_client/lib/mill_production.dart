part of 'mill_overview.dart';

typedef _Entry = Map<String, dynamic>;

class _PostedDay {
  _PostedDay(this.date);
  final DateTime date;
  final entries = <_Entry>[];
  BigInt? milli = BigInt.zero;

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
  const _MillProductionChart({required this.snapshot, required this.api});
  final ErpApi api;
  final KnittingSnapshot snapshot;
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
    final events = widget.snapshot.rows('events');
    loaded = events.length;
    final posted = <(DateTime, _Entry)>[];
    DateTime? latest;
    for (final event in events) {
      if (event['cancelled'] == 1 ||
          event['cancelled'] == true ||
          !const {'produce', 'produce_bulk'}.contains(event['kind'])) {
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
    final sourceAvailable = widget.snapshot.data['events'] is List;
    final peak = days.values
        .map((d) => d.milli?.toDouble() ?? 0.0)
        .fold<double>(0, math.max);
    const light = Color(0xFFE0E6DC);
    return Panel(
      frosted: true,
      dark: true,
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Display('Posted production', size: 28, light: true),
                    const SizedBox(height: 4),
                    Text(
                      day == null
                          ? 'In-house output · kg'
                          : '${DateFormat.MMMd().format(days.keys.first)} – ${DateFormat.yMMMd().format(days.keys.last)}',
                      style: const TextStyle(fontSize: 12, color: light),
                    ),
                  ],
                ),
              ),
              if (day != null)
                IconButton(
                  onPressed: () => sources(day),
                  tooltip: 'View production entries',
                  style: IconButton.styleFrom(
                    foregroundColor: light,
                    side: const BorderSide(color: Color(0xFF64726A)),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 17),
                ),
            ],
          ),
          if (day == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                !sourceAvailable
                    ? 'Production entries unavailable.'
                    : missingDate
                    ? 'Production posting dates unavailable.'
                    : 'No in-house production in the loaded postings.',
                style: const TextStyle(color: light),
              ),
            )
          else ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 9,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  day.milli == null ? '— kg' : '${_quantity(day.milli!)} kg',
                  style: displayStyle(33, color: const Color(0xFFFFD0AD)),
                ),
                Text(
                  '${DateFormat.MMMd().format(day.date)} · ${day.entries.length} ${day.entries.length == 1 ? 'entry' : 'entries'}',
                  style: const TextStyle(color: light, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (_, bounds) {
                final width = math.max(308.0, bounds.maxWidth);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Stack(
                      children: [
                        const Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Divider(height: 1, color: Color(0xFF49564D)),
                        ),
                        const Positioned(
                          top: 48,
                          left: 0,
                          right: 0,
                          child: Divider(height: 1, color: Color(0xFF49564D)),
                        ),
                        const Positioned(
                          top: 84,
                          left: 0,
                          right: 0,
                          child: Divider(height: 1, color: Color(0xFF657165)),
                        ),
                        Row(
                          children: [
                            for (final point in days.values)
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final active = point.date == day.date;
                                    final qty = point.milli;
                                    final label =
                                        '${DateFormat.MMMd().format(point.date)} · ${qty == null ? 'Unknown weight' : '${_quantity(qty)} kg'}';
                                    return Semantics(
                                      button: true,
                                      selected: active,
                                      label: label,
                                      excludeSemantics: true,
                                      child: Tooltip(
                                        message: label,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () => setState(
                                              () => selected = point.date,
                                            ),
                                            child: Column(
                                              children: [
                                                SizedBox(
                                                  height: 85,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.bottomCenter,
                                                    child: AnimatedContainer(
                                                      duration: workspaceMotion(
                                                        context,
                                                      ),
                                                      curve:
                                                          Curves.easeOutCubic,
                                                      width: math.min(
                                                        48,
                                                        (width / 7) * .52,
                                                      ),
                                                      height:
                                                          qty == null ||
                                                              qty ==
                                                                  BigInt.zero ||
                                                              peak == 0
                                                          ? 2
                                                          : math.max(
                                                              3.0,
                                                              qty.toDouble() /
                                                                  peak *
                                                                  74,
                                                            ),
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment
                                                              .topCenter,
                                                          end: Alignment
                                                              .bottomCenter,
                                                          colors: active
                                                              ? const [
                                                                  Color(
                                                                    0xFFFFCCA7,
                                                                  ),
                                                                  Color(
                                                                    0xFFCC8969,
                                                                  ),
                                                                ]
                                                              : const [
                                                                  Color(
                                                                    0xFFB5C9AB,
                                                                  ),
                                                                  Color(
                                                                    0xFF708E78,
                                                                  ),
                                                                ],
                                                        ),
                                                        borderRadius:
                                                            const BorderRadius.vertical(
                                                              top:
                                                                  Radius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  DateFormat(
                                                    'EE',
                                                  ).format(point.date),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: active
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                    color: active
                                                        ? const Color(
                                                            0xFFFFD3B4,
                                                          )
                                                        : light,
                                                  ),
                                                ),
                                              ],
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
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 10),
          Text(
            !sourceAvailable
                ? 'Recent entries unavailable'
                : 'In-house output · ${loaded == 500 ? 'latest 500 postings' : '$loaded loaded postings'}${missingDate ? ' · some dates unavailable' : ''}',
            style: const TextStyle(fontSize: 11, color: Color(0xFFBFCBC0)),
          ),
        ],
      ),
    );
  }
}
