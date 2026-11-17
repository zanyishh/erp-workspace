import '../../../core/models/erp_models.dart';

class SalesChartViewModel {
  SalesChartViewModel(this._data, {this._range}) {
    _load();
  }
  ErpSnapshot _data;
  DateRange? _range;
  List<SalesDay> _buckets = const [];
  int _selected = 0;
  bool _monthly = false;
  List<SalesDay> get buckets => _buckets;
  int get selected => _selected;
  bool get monthly => _monthly;
  static DateTime _date(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  void update(ErpSnapshot data, {DateRange? range}) {
    if (_data == data &&
        _range?.start == range?.start &&
        _range?.end == range?.end) {
      return;
    }
    final preserve =
        _data.company == data.company &&
            _range?.start == range?.start &&
            _range?.end == range?.end &&
            _buckets.isNotEmpty
        ? _buckets[_selected].day
        : null;
    _data = data;
    _range = range;
    _load();
    if (preserve != null) {
      final index = _buckets.indexWhere((d) => d.day == preserve);
      if (index >= 0) {
        _selected = index;
      }
    }
  }

  void _load() {
    final sales = _data.sales;
    if (!_data.invoicesAvailable || sales.isEmpty) {
      _buckets = const [];
      return;
    }
    // Missing dates inside a permitted, loaded period contribute zero.
    final first = _date(_range?.start ?? sales.first.day);
    final lastExclusive = _range == null
        ? _date(sales.last.day).add(const Duration(days: 1))
        : _date(_range!.end);
    _monthly = lastExclusive.difference(first).inDays > 62;
    DateTime bucket(DateTime d) =>
        _monthly ? DateTime.utc(d.year, d.month) : _date(d);
    final totals = <DateTime, double>{};
    for (final day in sales) {
      final date = _date(day.day);
      if (date.isBefore(first) || !date.isBefore(lastExclusive)) {
        continue;
      }
      final key = bucket(date);
      totals[key] = (totals[key] ?? 0) + day.amount;
    }
    _buckets = List.unmodifiable(
      totals.isEmpty
          ? <SalesDay>[]
          : [
              for (
                var date = bucket(first);
                date.isBefore(lastExclusive);
                date = _monthly
                    ? DateTime.utc(date.year, date.month + 1)
                    : date.add(const Duration(days: 1))
              )
                SalesDay(date, totals[date] ?? 0),
            ],
    );
    _selected = _buckets.lastIndexWhere((b) => totals.containsKey(b.day));
  }

  bool select(int index) {
    if (index < 0 || index >= _buckets.length || index == _selected) {
      return false;
    }
    _selected = index;
    return true;
  }
}
