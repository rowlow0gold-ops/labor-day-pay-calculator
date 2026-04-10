import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../l10n/app_localizations.dart';
import '../models/country_data.dart';
import '../services/app_state.dart';
import '../services/tax_calculator.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const int _maxEntriesPerDay = 3;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // Multiple entries can exist on the same day (up to _maxEntriesPerDay).
  Map<String, List<WorkEntry>> _entries = {};
  double _hourlyRate = 0;

  // Range selection mode
  bool _isSelectMode = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // Number input rule: non-negative, up to 2 decimal places.
  // Accepts "7", "7.25", "0.5", rejects "7.345", "-1", "abc".
  // Optional [max] caps the numeric value (inclusive) — rejected edits are
  // bounced so the controller text never exceeds the limit.
  static List<TextInputFormatter> _makeNumberFormatters({double? max}) {
    return [
      TextInputFormatter.withFunction((oldValue, newValue) {
        if (newValue.text.isEmpty) return newValue;
        final regex = RegExp(r'^\d*\.?\d{0,2}$');
        if (!regex.hasMatch(newValue.text)) return oldValue;
        if (max != null) {
          final parsed = double.tryParse(newValue.text);
          if (parsed != null && parsed > max) return oldValue;
        }
        return newValue;
      }),
    ];
  }

  static final List<TextInputFormatter> _numberInputFormatters =
      _makeNumberFormatters();
  // One calendar cell = one calendar day = at most 24 hours.
  static final List<TextInputFormatter> _hoursFormatters =
      _makeNumberFormatters(max: 24);
  // Incentive % is capped at 5,000.
  static final List<TextInputFormatter> _incentiveFormatters =
      _makeNumberFormatters(max: 5000);
  // Hourly rate is capped at 10,000,000.
  static final List<TextInputFormatter> _hourlyRateFormatters =
      _makeNumberFormatters(max: 10000000);
  // Tax / insurance percentages are capped at 99%.
  static final List<TextInputFormatter> _percentFormatters =
      _makeNumberFormatters(max: 99);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  void _loadData() {
    final app = context.read<AppState>();
    _hourlyRate = app.storage.getHourlyRate(app.country);

    final entries = app.storage.getWorkEntries(_focusedDay.year, _focusedDay.month);
    _entries = {};
    for (final e in entries) {
      _entries.putIfAbsent(_dateKey(e.date), () => []).add(e);
    }
    if (mounted) setState(() {});
  }

  /// Pay for a single work entry, including incentive bonus (단가 mode only).
  /// Incentive = percent × rate × min(hours, incentiveEffectHours).
  double _entryPay(WorkEntry e) {
    if (e.isLumpSum) return e.value;
    final rate = e.rate ?? _hourlyRate;
    final basePay = e.value * rate;
    if (e.incentivePercent <= 0 || e.incentiveEffectHours <= 0) return basePay;
    final bonusHours = e.value < e.incentiveEffectHours ? e.value : e.incentiveEffectHours;
    return basePay + bonusHours * rate * e.incentivePercent / 100;
  }

  /// Aggregate payment for a day (sum across all entries on that day).
  double _dayTotalPay(List<WorkEntry> entries) {
    double sum = 0;
    for (final e in entries) {
      sum += _entryPay(e);
    }
    return sum;
  }

  /// Format a raw number with thousands separators & up to 2 decimals.
  String _formatMoney(double pay) {
    var s = pay.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    final dotIdx = s.indexOf('.');
    final intPart = dotIdx == -1 ? s : s.substring(0, dotIdx);
    final decPart = dotIdx == -1 ? '' : s.substring(dotIdx);
    final withCommas = intPart.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return withCommas + decPart;
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  Color _getValueColor(double value) {
    // Muted, soft tones — easy on the eyes
    if (value <= 0.5) return const Color(0xFF7E9AB8);       // soft steel blue
    if (value <= 1.0) return const Color(0xFF6B9E8A);       // sage green
    if (value <= 1.5) return const Color(0xFFB89E6B);       // warm tan
    if (value <= 2.0) return const Color(0xFFA87E6B);       // dusty terracotta
    // Hours mode or custom high values
    if (value <= 4.0) return const Color(0xFF7E9AB8);
    if (value <= 8.0) return const Color(0xFF6B9E8A);
    if (value <= 10.0) return const Color(0xFFB89E6B);
    return const Color(0xFFA87E6B);
  }

  /// Format a number for use in a TextField's initial text.
  /// Preserves decimals when present (7.25 stays "7.25") and strips
  /// trailing ".0" for whole numbers ("100.0" -> "100"). Shows "0" for 0.
  String _fmtNumInput(double n) {
    if (n == 0) return '0';
    if (n == n.truncateToDouble()) return n.toStringAsFixed(0);
    var s = n.toString();
    // Safety: strip trailing zeros after the decimal if any
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  void _saveEntries() {
    final app = context.read<AppState>();
    final list = <WorkEntry>[];
    for (final entries in _entries.values) {
      list.addAll(entries);
    }
    app.storage.setWorkEntries(_focusedDay.year, _focusedDay.month, list);
    app.refreshRates(); // notify dashboard & other screens
  }

  List<Holiday> _getHolidays() {
    final app = context.read<AppState>();
    final config = countryConfigs[app.country]!;
    return _focusedDay.year == 2025 ? config.holidays2025 : config.holidays2026;
  }

  bool _isHoliday(DateTime day) {
    final holidays = _getHolidays();
    return holidays.any((h) =>
        h.date.year == day.year && h.date.month == day.month && h.date.day == day.day);
  }

  String? _getHolidayName(DateTime day) {
    final holidays = _getHolidays();
    for (final h in holidays) {
      if (h.date.year == day.year && h.date.month == day.month && h.date.day == day.day) {
        return h.nameKey;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    final config = countryConfigs[app.country]!;

    // Monthly totals — each entry has its own tax/insurance rates
    double totalValue = 0;
    int workDays = 0;
    double grossPay = 0;
    double totalTaxDeduction = 0;
    double totalInsuranceDeduction = 0;
    for (final dayEntries in _entries.values) {
      if (dayEntries.isEmpty) continue;
      workDays++; // count the day once, regardless of how many entries on it
      for (final e in dayEntries) {
        if (!e.isLumpSum) totalValue += e.value;
        final entryGross = _entryPay(e);
        grossPay += entryGross;
        totalTaxDeduction += entryGross * e.taxRate / 100;
        totalInsuranceDeduction += entryGross * e.insuranceRate / 100;
      }
    }

    final totalDeduction = totalTaxDeduction + totalInsuranceDeduction;
    final taxResult = TaxResult(
      grossPay: grossPay,
      incomeTax: totalTaxDeduction,
      localTax: 0,
      nationalPension: totalInsuranceDeduction,
      healthInsurance: 0,
      longTermCare: 0,
      employmentInsurance: 0,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () => _showCalendarSettings(context, app, l),
        ),
        title: Text(
          _isSelectMode
              ? (_rangeStart != null && _rangeEnd != null
                  ? l.get('tap_to_paste')
                  : l.get('select_range'))
              : l.get('calendar_title'),
          style: _isSelectMode
              ? const TextStyle(color: Color(0xFF42A5F5), fontWeight: FontWeight.w600)
              : null,
        ),
        actions: [
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
              tooltip: l.get('cancel'),
              onPressed: () {
                setState(() {
                  _isSelectMode = false;
                  _rangeStart = null;
                  _rangeEnd = null;
                  _selectedDay = null;
                });
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              switch (value) {
                case 'select':
                  setState(() {
                    _isSelectMode = !_isSelectMode;
                    _rangeStart = null;
                    _rangeEnd = null;
                    _selectedDay = null;
                  });
                  break;
                case 'clear':
                  _clearMonth(app, l);
                  break;
                case 'clear_year':
                  _clearYear(app, l);
                  break;
                case 'clear_all':
                  _clearAllData(app, l);
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'select',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B894).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.copy_all, size: 18, color: Color(0xFF00B894)),
                    ),
                    const SizedBox(width: 12),
                    Text(l.get('select_copy')),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_sweep, size: 18, color: Colors.redAccent),
                    ),
                    const SizedBox(width: 12),
                    Text(l.get('clear_month')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_year',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.event_busy, size: 18, color: Colors.redAccent),
                    ),
                    const SizedBox(width: 12),
                    Text(l.get('clear_year')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_forever, size: 18, color: Colors.redAccent),
                    ),
                    const SizedBox(width: 12),
                    Text(l.get('clear_all')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Calendar — expanded, row height calculated dynamically
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Available height minus header(~52) minus dow row(~32) minus padding(~4)
                final availableHeight = constraints.maxHeight - 96;
                // Always assume 6 rows (max possible)
                final rowHeight = (availableHeight / 6).floorToDouble().clamp(48, 120).toDouble();

                return TableCalendar(
                  firstDay: DateTime(2024, 1, 1),
                  lastDay: DateTime(2027, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) =>
                      _selectedDay != null && isSameDay(_selectedDay, day),
                  calendarFormat: CalendarFormat.month,
                  startingDayOfWeek: StartingDayOfWeek.sunday,
                  locale: app.locale.languageCode,
                  availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                  sixWeekMonthsEnforced: true,
                  onDaySelected: (selected, focused) {
                    // Ignore taps on days outside the current month
                    if (selected.month != _focusedDay.month || selected.year != _focusedDay.year) return;

                    if (_isSelectMode) {
                      _handleSelectModeTap(selected, app, l);
                      return;
                    }

                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                    _showWorkEntryDialog(selected, app, l);
                  },
                  onPageChanged: (focused) {
                    setState(() => _focusedDay = focused);
                    _loadData();
                  },
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focused) =>
                        _buildDayCell(day, false, false),
                    selectedBuilder: (context, day, focused) =>
                        _buildDayCell(day, true, false),
                    todayBuilder: (context, day, focused) =>
                        _buildDayCell(day, false, true),
                    outsideBuilder: (context, day, focused) =>
                        _buildOutsideDayCell(day),
                    dowBuilder: (context, day) => _buildDowCell(day),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    leftChevronIcon: const Icon(Icons.chevron_left, size: 28),
                    rightChevronIcon: const Icon(Icons.chevron_right, size: 28),
                    headerPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                  onHeaderTapped: (_) => _showMonthYearJumper(),
                  daysOfWeekHeight: 30,
                  calendarStyle: const CalendarStyle(
                    outsideDaysVisible: true,
                    outsideTextStyle: TextStyle(color: Colors.transparent),
                    cellMargin: EdgeInsets.all(0),
                    cellPadding: EdgeInsets.all(0),
                  ),
                  rowHeight: rowHeight,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    AppLocalizations l,
    double totalValue,
    int workDays,
    TaxResult taxResult,
    CountryConfig config,
    AppState app,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00B8A9).withOpacity(0.3),
            const Color(0xFF00B8A9).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00B8A9).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.get('monthly_total')}: ${TaxCalculator.formatAmount(taxResult.netPay, app.country)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l.get('before_tax')}: ${TaxCalculator.formatAmount(taxResult.grossPay, app.country)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _statChip(l.get('work_days'), '$workDays', Icons.work_outline),
              const SizedBox(height: 4),
              _statChip(
                l.get('total_hours'),
                totalValue.toStringAsFixed(1),
                Icons.access_time,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF00B8A9)),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildDowCell(DateTime day) {
    final app = context.read<AppState>();
    final lang = app.locale.languageCode;
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    const dowLabels = {
      'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      'ko': ['월', '화', '수', '목', '금', '토', '일'],
      'ja': ['月', '火', '水', '木', '金', '土', '日'],
      'zh': ['一', '二', '三', '四', '五', '六', '日'],
      'ru': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
      'vi': ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'],
      'tl': ['Lun', 'Mar', 'Miy', 'Huw', 'Biy', 'Sab', 'Lin'],
      'th': ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'],
      'id': ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'],
      'km': ['ច', 'អ', 'ពុ', 'ព្រ', 'សុ', 'ស', 'អា'],
      'ne': ['सोम', 'मंगल', 'बुध', 'बिही', 'शुक्र', 'शनि', 'आइत'],
      'my': ['တနလ', 'အင်္', 'ဗုဒ', 'ကြာ', 'သော', 'စန', 'တနင်'],
      'mn': ['Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя', 'Ня'],
      'uz': ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'],
      'bn': ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'],
    };
    final labels = dowLabels[lang] ?? dowLabels['en']!;
    final label = labels[day.weekday - 1];
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
            width: 1,
          ),
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isWeekend ? Colors.redAccent : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildOutsideDayCell(DateTime day) {
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
            width: 0.5,
          ),
        ),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
          ),
        ),
      ),
    );
  }

  bool _isDayInRange(DateTime day) {
    if (_rangeStart == null || _rangeEnd == null) return false;
    final start = _rangeStart!.isBefore(_rangeEnd!) ? _rangeStart! : _rangeEnd!;
    final end = _rangeStart!.isBefore(_rangeEnd!) ? _rangeEnd! : _rangeStart!;
    return !day.isBefore(start) && !day.isAfter(end);
  }

  List<WorkEntry> _getRangeEntries() {
    if (_rangeStart == null || _rangeEnd == null) return [];
    final start = _rangeStart!.isBefore(_rangeEnd!) ? _rangeStart! : _rangeEnd!;
    final end = _rangeStart!.isBefore(_rangeEnd!) ? _rangeEnd! : _rangeStart!;
    final entries = <WorkEntry>[];
    var d = start;
    while (!d.isAfter(end)) {
      final key = _dateKey(d);
      if (_entries.containsKey(key)) entries.addAll(_entries[key]!);
      d = d.add(const Duration(days: 1));
    }
    return entries;
  }

  Widget _buildDayCell(DateTime day, bool isSelected, bool isToday) {
    final key = _dateKey(day);
    final dayEntries = _entries[key];
    final hasEntries = dayEntries != null && dayEntries.isNotEmpty;
    final holidayName = _getHolidayName(day);
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final inRange = _isSelectMode && _isDayInRange(day);

    Color textColor = Theme.of(context).colorScheme.onSurface;

    if (holidayName != null || isWeekend) {
      textColor = Colors.redAccent;
    }

    // Sum all values on the day for the color ramp (total hours for 단가,
    // or 1 per lump-sum entry to approximate intensity).
    double valueForColor = 0;
    if (hasEntries) {
      for (final e in dayEntries) {
        valueForColor += e.isLumpSum ? 1.0 : e.value;
      }
    }
    final valueColor = hasEntries ? _getValueColor(valueForColor) : null;
    final lineColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.15);

    // Range cells fill solid blue with no inner borders — adjacent cells merge into one box
    Border cellBorder;
    Color? cellBg;
    if (inRange) {
      cellBorder = Border.all(color: Colors.transparent, width: 0);
      cellBg = const Color(0xFF42A5F5);
      textColor = Colors.white;
    } else if (isSelected) {
      cellBorder = Border.all(color: const Color(0xFF00B8A9), width: 2.5);
    } else if (isToday) {
      cellBorder = Border.all(color: lineColor, width: 1);
      cellBg = Theme.of(context).colorScheme.onSurface.withOpacity(0.08);
    } else {
      cellBorder = Border.all(color: lineColor, width: 1);
    }

    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          color: cellBg,
          border: cellBorder,
        ),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${day.day}',
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (hasEntries) ...[
            // One row per entry — pay amount + workplace on the same line.
            for (final e in dayEntries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _formatMoney(_entryPay(e)),
                        style: TextStyle(
                          fontSize: 10,
                          color: valueColor,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (e.workplace.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          e.workplace,
                          style: const TextStyle(
                            fontSize: 8,
                            color: Color(0xFF00B8A9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ] else if (holidayName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                holidayName,
                style: TextStyle(
                  fontSize: 7,
                  color: Colors.redAccent.withOpacity(0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      ),
    );
  }

  void _handleSelectModeTap(DateTime day, AppState app, AppLocalizations l) {
    setState(() {
      // If tapping inside the current range → clear selection
      if (_isDayInRange(day)) {
        _rangeStart = null;
        _rangeEnd = null;
        return;
      }

      // First tap → set range start
      if (_rangeStart == null) {
        _rangeStart = day;
        _rangeEnd = null;
        return;
      }

      // Second tap (no range yet) → set range end
      if (_rangeEnd == null) {
        _rangeEnd = day;
        return;
      }

      // Range is set, tapping outside → paste entries starting from tapped day
      _pasteRangeEntries(day, app, l);
    });
  }

  void _pasteRangeEntries(DateTime day, AppState app, AppLocalizations l) {
    final rangeEntries = _getRangeEntries();
    if (rangeEntries.isEmpty) {
      // Alert: user tapped on empty-only cells, nothing to copy
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(l.get('empty_selection'))),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {
        _rangeStart = null;
        _rangeEnd = null;
      });
      return;
    }

    final start = _rangeStart!.isBefore(_rangeEnd!) ? _rangeStart! : _rangeEnd!;

    // Check if any target cells already have data (count unique days, not entries)
    final seenTargetKeys = <String>{};
    int overlapCount = 0;
    for (final src in rangeEntries) {
      final offset = src.date.difference(start).inDays;
      final targetDate = day.add(Duration(days: offset));
      if (targetDate.month != _focusedDay.month || targetDate.year != _focusedDay.year) continue;
      final key = _dateKey(targetDate);
      if (seenTargetKeys.add(key) && _entries.containsKey(key)) overlapCount++;
    }

    if (overlapCount > 0) {
      // Show confirmation dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Text(l.get('overwrite_title'), style: const TextStyle(fontSize: 16))),
            ],
          ),
          content: Text(l.getWith('overwrite_message', {'n': '$overlapCount'})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _doPaste(day, start, rangeEntries, l);
              },
              child: Text(l.get('confirm')),
            ),
          ],
        ),
      );
    } else {
      _doPaste(day, start, rangeEntries, l);
    }
  }

  void _doPaste(DateTime day, DateTime start, List<WorkEntry> rangeEntries, AppLocalizations l) {
    // Group source entries by the day-offset from the range start, so we can
    // paste all entries for a given source day as a list onto the target day.
    final grouped = <int, List<WorkEntry>>{};
    for (final src in rangeEntries) {
      final offset = src.date.difference(start).inDays;
      grouped.putIfAbsent(offset, () => []).add(src);
    }

    int copied = 0;
    grouped.forEach((offset, sources) {
      final targetDate = day.add(Duration(days: offset));
      if (targetDate.month != _focusedDay.month || targetDate.year != _focusedDay.year) return;
      final key = _dateKey(targetDate);
      final newEntries = sources
          .map((src) => WorkEntry(
                date: targetDate,
                value: src.value,
                rate: src.rate,
                isLumpSum: src.isLumpSum,
                isHoliday: _isHoliday(targetDate),
                isOvertime: src.isOvertime,
                isNightShift: src.isNightShift,
                workplace: src.workplace,
                taxRate: src.taxRate,
                insuranceRate: src.insuranceRate,
              ))
          .toList();
      _entries[key] = newEntries;
      copied += newEntries.length;
    });
    _saveEntries();

    setState(() {
      _isSelectMode = false;
      _rangeStart = null;
      _rangeEnd = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.getWith('entries_copied', {'n': '$copied'})),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF00B894),
      ),
    );
  }

  void _clearYear(AppState app, AppLocalizations l) {
    final yearEntries = app.storage.getYearEntries(_focusedDay.year);
    if (yearEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.get('already_empty')),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l.get('clear_year'), style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(l.getWith('delete_year', {
          'n': '${yearEntries.length}',
          'year': '${_focusedDay.year}',
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.get('cancel')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await app.storage.clearYear(_focusedDay.year);
              // Reload current month — will be empty since we're inside the
              // cleared year.
              _loadData();
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.get('year_cleared')),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            icon: const Icon(Icons.delete, size: 18),
            label: Text(l.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _clearAllData(AppState app, AppLocalizations l) {
    // Count entries across a reasonable range of years stored in prefs.
    // The calendar is bounded to 2024–2027, so that's the only range we load.
    int totalCount = 0;
    for (int y = 2024; y <= 2027; y++) {
      totalCount += app.storage.getYearEntries(y).length;
    }
    if (totalCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.get('already_empty')),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l.get('clear_all'), style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(l.getWith('delete_all_data', {'n': '$totalCount'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.get('cancel')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await app.storage.clearAllWorkEntries();
              _loadData();
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.get('all_cleared')),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            icon: const Icon(Icons.delete_forever, size: 18),
            label: Text(l.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _clearMonth(AppState app, AppLocalizations l) {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.get('already_empty')),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l.get('clear_month'), style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(l.getWith('delete_all', {'n': '${_entries.values.fold<int>(0, (s, list) => s + list.length)}'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.get('cancel')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              setState(() => _entries.clear());
              _saveEntries();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.get('month_cleared')),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            icon: const Icon(Icons.delete, size: 18),
            label: Text(l.get('confirm')),
          ),
        ],
      ),
    );
  }

  void _showMonthYearJumper() {
    showDialog(
      context: context,
      builder: (ctx) {
        int tempYear = _focusedDay.year;
        int tempMonth = _focusedDay.month;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Select Month'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setDialogState(() => tempYear--),
                      ),
                      Text(
                        '$tempYear',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setDialogState(() => tempYear++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 280,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (i) {
                        final m = i + 1;
                        final isSelected = m == tempMonth;
                        return Material(
                          color: isSelected
                              ? const Color(0xFF00B8A9)
                              : const Color(0xFF00B8A9).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setDialogState(() => tempMonth = m),
                            child: Container(
                              width: 60,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              alignment: Alignment.center,
                              child: Text(
                                '$m',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF00B8A9),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(tempYear, tempMonth, 1);
                    });
                    _loadData();
                    Navigator.pop(ctx);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showWorkEntryDialog(
      DateTime day, AppState app, AppLocalizations l) {
    final key = _dateKey(day);
    final existing = _entries[key] ?? const <WorkEntry>[];
    final holiday = _isHoliday(day);
    final holidayName = _getHolidayName(day);

    // Build mutable draft list from existing entries, or start with one blank.
    final drafts = <_EntryDraft>[];
    if (existing.isEmpty) {
      drafts.add(_EntryDraft.newDefault(app, _hourlyRate));
    } else {
      for (final e in existing) {
        drafts.add(_EntryDraft.fromEntry(e));
      }
    }

    int selectedIndex = 0;

    // Controllers are shared across tabs — we swap the text on tab change.
    final workplaceController = TextEditingController();
    final rateController = TextEditingController();
    final paymentController = TextEditingController();
    final hoursController = TextEditingController();
    final taxRateController = TextEditingController();
    final insuranceRateController = TextEditingController();
    final incentiveController = TextEditingController();
    final incentiveHoursController = TextEditingController();
    String? incentiveHoursError;

    void loadDraftToControllers(_EntryDraft d) {
      workplaceController.text = d.workplace;
      rateController.text = _fmtNumInput(d.rate ?? _hourlyRate);
      paymentController.text = d.isLumpSum ? _fmtNumInput(d.value) : '';
      hoursController.text = d.isLumpSum ? '' : _fmtNumInput(d.value);
      taxRateController.text = _fmtNumInput(d.taxRate);
      insuranceRateController.text = _fmtNumInput(d.insuranceRate);
      incentiveController.text = _fmtNumInput(d.incentivePercent);
      incentiveHoursController.text = _fmtNumInput(d.incentiveEffectHours);
      incentiveHoursError = null;
    }

    void flushControllersToDraft(_EntryDraft d) {
      d.workplace = workplaceController.text;
      if (d.isLumpSum) {
        d.value = double.tryParse(paymentController.text) ?? d.value;
      } else {
        d.value = double.tryParse(hoursController.text) ?? d.value;
        d.rate = double.tryParse(rateController.text) ?? d.rate;
        d.incentivePercent = double.tryParse(incentiveController.text) ?? d.incentivePercent;
        d.incentiveEffectHours = double.tryParse(incentiveHoursController.text) ?? d.incentiveEffectHours;
      }
      d.taxRate = double.tryParse(taxRateController.text) ?? d.taxRate;
      d.insuranceRate = double.tryParse(insuranceRateController.text) ?? d.insuranceRate;
    }

    loadDraftToControllers(drafts[0]);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Guard: after deleting the last draft we pop the dialog, but
            // Flutter may still run one more build before the route is
            // disposed. Return an empty shell in that case.
            if (drafts.isEmpty) return const SizedBox.shrink();
            if (selectedIndex >= drafts.length) {
              selectedIndex = drafts.length - 1;
            }
            final current = drafts[selectedIndex];

            void switchTo(int i) {
              flushControllersToDraft(drafts[selectedIndex]);
              setDialogState(() {
                selectedIndex = i;
                loadDraftToControllers(drafts[selectedIndex]);
              });
            }

            void addNewDraft() {
              if (drafts.length >= _maxEntriesPerDay) return;
              flushControllersToDraft(drafts[selectedIndex]);
              setDialogState(() {
                // New drafts inherit the current tab's mode for consistency.
                drafts.add(_EntryDraft.newDefault(
                  app,
                  _hourlyRate,
                  isLumpSum: current.isLumpSum,
                ));
                selectedIndex = drafts.length - 1;
                loadDraftToControllers(drafts[selectedIndex]);
              });
            }

            void deleteCurrentDraft() {
              // Remove the current draft first (outside setDialogState) so
              // the subsequent rebuild can't read stale indices.
              drafts.removeAt(selectedIndex);
              if (drafts.isEmpty) {
                // No drafts left → remove the whole day and close the dialog
                // *before* any rebuild runs. A rebuild with an empty list
                // would crash on drafts[selectedIndex].
                setState(() => _entries.remove(key));
                _saveEntries();
                Navigator.pop(ctx);
                return;
              }
              if (selectedIndex >= drafts.length) {
                selectedIndex = drafts.length - 1;
              }
              loadDraftToControllers(drafts[selectedIndex]);
              setDialogState(() {});
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Text(
                    '${day.year}/${day.month}/${day.day}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (holidayName != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          holidayName,
                          style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Entry tab row — one chip per draft + "add" button
                    SizedBox(
                      height: 34,
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (int i = 0; i < drafts.length; i++) ...[
                                    _buildEntryTabChip(
                                      index: i,
                                      isSelected: i == selectedIndex,
                                      onTap: () => switchTo(i),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Material(
                            color: drafts.length < _maxEntriesPerDay
                                ? const Color(0xFF00B8A9).withOpacity(0.15)
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: drafts.length < _maxEntriesPerDay ? addNewDraft : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: drafts.length < _maxEntriesPerDay
                                      ? const Color(0xFF00B8A9)
                                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Per-entry mode toggle (hourly vs lump sum)
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        segments: [
                          ButtonSegment(value: false, label: Text(l.get('rate_mode'), style: const TextStyle(fontSize: 12))),
                          ButtonSegment(value: true, label: Text(l.get('lump_sum_mode'), style: const TextStyle(fontSize: 12))),
                        ],
                        selected: {current.isLumpSum},
                        onSelectionChanged: (s) {
                          flushControllersToDraft(current);
                          setDialogState(() {
                            current.isLumpSum = s.first;
                            // Reset value to default when switching modes
                            if (current.isLumpSum) {
                              current.value = app.storage.getDefaultPayment();
                              if (current.workplace.isEmpty) {
                                current.workplace = app.storage.getDefaultWorkplaceDaily();
                              }
                              current.taxRate = app.taxRate(true);
                              current.insuranceRate = app.insuranceRate(true);
                            } else {
                              current.value = app.storage.getDefaultHours();
                              current.rate = _hourlyRate;
                              if (current.workplace.isEmpty) {
                                current.workplace = app.storage.getDefaultWorkplaceHourly();
                              }
                              current.taxRate = app.taxRate(false);
                              current.insuranceRate = app.insuranceRate(false);
                            }
                            loadDraftToControllers(current);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (current.isLumpSum) ...[
                      // 일시금 mode: payment + workplace (mirrors hourly layout)
                      Text(
                        l.get('rate_setting'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00B8A9),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: paymentController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _numberInputFormatters,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: l.get('payment'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v);
                          if (val != null && val >= 0) current.value = val;
                        },
                      ),
                      const SizedBox(height: 12),
                      // Workplace — same styling as hourly mode
                      TextField(
                        controller: workplaceController,
                        decoration: InputDecoration(
                          labelText: l.get('workplace'),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: const Icon(Icons.business, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ] else ...[
                      Text(
                        l.get('rate_setting'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00B8A9),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Row 1: hours + hourly rate
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: hoursController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: _hoursFormatters,
                              decoration: InputDecoration(
                                labelText: l.get('default_hours'),
                                suffixText: 'h',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                if (val != null && val >= 0) current.value = val;
                                setDialogState(() {
                                  incentiveHoursError = current.incentiveEffectHours > current.value
                                      ? '≤ ${_fmtNumInput(current.value)}h'
                                      : null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: rateController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: _hourlyRateFormatters,
                              decoration: InputDecoration(
                                labelText: l.get('hourly_rate'),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                if (val != null && val >= 0) current.rate = val;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Row 2: incentive % + incentive effect hours
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: incentiveController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: _incentiveFormatters,
                              decoration: InputDecoration(
                                labelText: l.get('incentive'),
                                suffixText: '%',
                                prefixIcon: const Icon(Icons.star_border, size: 18),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                current.incentivePercent = (val != null && val >= 0) ? val : 0;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: incentiveHoursController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: _hoursFormatters,
                              decoration: InputDecoration(
                                labelText: l.get('incentive_hours'),
                                suffixText: 'h',
                                errorText: incentiveHoursError,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                current.incentiveEffectHours = (val != null && val >= 0) ? val : 0;
                                setDialogState(() {
                                  incentiveHoursError = current.incentiveEffectHours > current.value
                                      ? '≤ ${_fmtNumInput(current.value)}h'
                                      : null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Row 3: workplace (full width)
                      TextField(
                        controller: workplaceController,
                        decoration: InputDecoration(
                          labelText: l.get('workplace'),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: const Icon(Icons.business, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Tax / 공제 section header
                    Text(
                      l.get('tax_section'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00B8A9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Tax rate inputs (combined tax + insurance must be ≤ 99%)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: taxRateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: _percentFormatters,
                            decoration: InputDecoration(
                              labelText: l.get('include_flat_tax'),
                              suffixText: '%',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (v) {
                              var val = double.tryParse(v) ?? 0;
                              if (val < 0) val = 0;
                              final maxAllowed = 99 - current.insuranceRate;
                              if (val > maxAllowed) {
                                val = maxAllowed < 0 ? 0 : maxAllowed;
                                final clamped = val == val.roundToDouble()
                                    ? val.toStringAsFixed(0)
                                    : val.toString();
                                taxRateController.value = TextEditingValue(
                                  text: clamped,
                                  selection: TextSelection.collapsed(offset: clamped.length),
                                );
                              }
                              current.taxRate = val;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: insuranceRateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: _percentFormatters,
                            decoration: InputDecoration(
                              labelText: l.get('include_insurance'),
                              suffixText: '%',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (v) {
                              var val = double.tryParse(v) ?? 0;
                              if (val < 0) val = 0;
                              final maxAllowed = 99 - current.taxRate;
                              if (val > maxAllowed) {
                                val = maxAllowed < 0 ? 0 : maxAllowed;
                                final clamped = val == val.roundToDouble()
                                    ? val.toStringAsFixed(0)
                                    : val.toString();
                                insuranceRateController.value = TextEditingValue(
                                  text: clamped,
                                  selection: TextSelection.collapsed(offset: clamped.length),
                                );
                              }
                              current.insuranceRate = val;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: deleteCurrentDraft,
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      label: Text(
                        l.get('clear'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l.get('cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: incentiveHoursError != null
                          ? null
                          : () {
                              flushControllersToDraft(drafts[selectedIndex]);
                              final newList = drafts
                                  .map((d) => WorkEntry(
                                        date: day,
                                        value: d.value,
                                        rate: d.isLumpSum ? null : d.rate,
                                        isLumpSum: d.isLumpSum,
                                        isHoliday: holiday,
                                        isOvertime: d.isOvertime,
                                        isNightShift: d.isNightShift,
                                        workplace: d.workplace,
                                        taxRate: d.taxRate,
                                        insuranceRate: d.insuranceRate,
                                        incentivePercent: d.isLumpSum ? 0 : d.incentivePercent,
                                        incentiveEffectHours: d.isLumpSum ? 0 : d.incentiveEffectHours,
                                      ))
                                  .toList();
                              setState(() => _entries[key] = newList);
                              _saveEntries();
                              Navigator.pop(ctx);
                            },
                      child: Text(l.get('confirm')),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Small chip used as a tab in the entry dialog to switch between drafts.
  Widget _buildEntryTabChip({
    required int index,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected
          ? const Color(0xFF00B8A9)
          : const Color(0xFF00B8A9).withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF00B8A9),
            ),
          ),
        ),
      ),
    );
  }

  void _showCalendarSettings(BuildContext context, AppState app, AppLocalizations l) {
    final config = countryConfigs[app.country]!;

    // Snapshot original values for revert on cancel
    final origHourlyRate = _hourlyRate;
    final origDefaultHours = app.storage.getDefaultHours();
    final origWorkplaceHourly = app.storage.getDefaultWorkplaceHourly();
    final origWorkplaceDaily = app.storage.getDefaultWorkplaceDaily();
    final origLumpSum = app.storage.getDefaultLumpSum();
    final origDefaultPayment = app.storage.getDefaultPayment();
    final origTaxRateHourly = app.taxRateHourly;
    final origInsuranceRateHourly = app.insuranceRateHourly;
    final origTaxRateDaily = app.taxRateDaily;
    final origInsuranceRateDaily = app.insuranceRateDaily;
    final origIncentiveHourly = app.incentiveHourly;
    final origIncentiveEffectHours = app.incentiveEffectHoursHourly;

    // Temp values edited in the sheet
    double tempHourlyRate = origHourlyRate;
    double tempDefaultHours = origDefaultHours;
    String tempWorkplaceHourly = origWorkplaceHourly;
    String tempWorkplaceDaily = origWorkplaceDaily;
    bool tempLumpSum = origLumpSum;
    double tempDefaultPayment = origDefaultPayment;
    double tempTaxRateHourly = origTaxRateHourly;
    double tempInsuranceRateHourly = origInsuranceRateHourly;
    double tempTaxRateDaily = origTaxRateDaily;
    double tempInsuranceRateDaily = origInsuranceRateDaily;
    double tempIncentiveHourly = origIncentiveHourly;
    double tempIncentiveEffectHours = origIncentiveEffectHours;
    String? incentiveHoursError;

    final hourlyController = TextEditingController(text: _fmtNumInput(origHourlyRate));
    final defaultHoursController = TextEditingController(text: _fmtNumInput(origDefaultHours));
    final defaultPaymentController = TextEditingController(text: _fmtNumInput(origDefaultPayment));
    final workplaceHourlyController = TextEditingController(text: origWorkplaceHourly);
    final workplaceDailyController = TextEditingController(text: origWorkplaceDaily);
    final settingsTaxHourlyController = TextEditingController(text: _fmtNumInput(origTaxRateHourly));
    final settingsInsHourlyController = TextEditingController(text: _fmtNumInput(origInsuranceRateHourly));
    final settingsTaxDailyController = TextEditingController(text: _fmtNumInput(origTaxRateDaily));
    final settingsInsDailyController = TextEditingController(text: _fmtNumInput(origInsuranceRateDaily));
    final incentiveHourlyController = TextEditingController(text: _fmtNumInput(origIncentiveHourly));
    final incentiveEffectHoursController = TextEditingController(text: _fmtNumInput(origIncentiveEffectHours));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(l.get('default_settings'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),

              // 단건/단가 toggle
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(l.get('rate_mode'), style: const TextStyle(fontSize: 13))),
                    ButtonSegment(value: true, label: Text(l.get('lump_sum_mode'), style: const TextStyle(fontSize: 13))),
                  ],
                  selected: {tempLumpSum},
                  onSelectionChanged: (s) {
                    setSheetState(() {
                      tempLumpSum = s.first;
                      // Reset fields to stored defaults for the selected mode
                      if (tempLumpSum) {
                        tempDefaultPayment = origDefaultPayment;
                        defaultPaymentController.text = _fmtNumInput(origDefaultPayment);
                        tempWorkplaceDaily = origWorkplaceDaily;
                        workplaceDailyController.text = origWorkplaceDaily;
                        tempTaxRateDaily = origTaxRateDaily;
                        settingsTaxDailyController.text = _fmtNumInput(origTaxRateDaily);
                        tempInsuranceRateDaily = origInsuranceRateDaily;
                        settingsInsDailyController.text = _fmtNumInput(origInsuranceRateDaily);
                      } else {
                        tempHourlyRate = origHourlyRate;
                        hourlyController.text = _fmtNumInput(origHourlyRate);
                        tempDefaultHours = origDefaultHours;
                        defaultHoursController.text = _fmtNumInput(origDefaultHours);
                        tempWorkplaceHourly = origWorkplaceHourly;
                        workplaceHourlyController.text = origWorkplaceHourly;
                        tempTaxRateHourly = origTaxRateHourly;
                        settingsTaxHourlyController.text = _fmtNumInput(origTaxRateHourly);
                        tempInsuranceRateHourly = origInsuranceRateHourly;
                        settingsInsHourlyController.text = _fmtNumInput(origInsuranceRateHourly);
                        tempIncentiveHourly = origIncentiveHourly;
                        incentiveHourlyController.text = _fmtNumInput(origIncentiveHourly);
                        tempIncentiveEffectHours = origIncentiveEffectHours;
                        incentiveEffectHoursController.text = _fmtNumInput(origIncentiveEffectHours);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 단건 mode: default payment
              if (tempLumpSum) ...[
                Text(l.get('rate_setting'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF00B8A9))),
                const SizedBox(height: 8),
                TextField(
                  controller: defaultPaymentController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _numberInputFormatters,
                  decoration: InputDecoration(
                    labelText: l.get('payment'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (v) {
                    final val = double.tryParse(v);
                    if (val != null && val >= 0) tempDefaultPayment = val;
                  },
                ),
                const SizedBox(height: 12),
              ],
              // Rate fields (only for 단가 mode)
              if (!tempLumpSum) ...[
                Text(l.get('rate_setting'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF00B8A9))),
                const SizedBox(height: 8),
                // Row 1: hours + hourly rate
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: defaultHoursController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _hoursFormatters,
                        decoration: InputDecoration(
                          labelText: l.get('default_hours'),
                          suffixText: 'h',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v);
                          if (val != null && val >= 0) tempDefaultHours = val;
                          // Re-validate incentive hours
                          setSheetState(() {
                            incentiveHoursError = tempIncentiveEffectHours > tempDefaultHours
                                ? '≤ ${tempDefaultHours.toStringAsFixed(tempDefaultHours.truncateToDouble() == tempDefaultHours ? 0 : 1)}h'
                                : null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: hourlyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _hourlyRateFormatters,
                        decoration: InputDecoration(
                          labelText: l.get('hourly_rate'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v);
                          if (val != null && val >= 0) tempHourlyRate = val;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Row 2: incentive % + incentive effect hours
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: incentiveHourlyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _incentiveFormatters,
                        decoration: InputDecoration(
                          labelText: l.get('incentive'),
                          suffixText: '%',
                          prefixIcon: const Icon(Icons.star_border, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v);
                          tempIncentiveHourly = (val != null && val >= 0) ? val : 0;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: incentiveEffectHoursController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: _hoursFormatters,
                        decoration: InputDecoration(
                          labelText: l.get('incentive_hours'),
                          suffixText: 'h',
                          errorText: incentiveHoursError,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v);
                          tempIncentiveEffectHours = (val != null && val >= 0) ? val : 0;
                          setSheetState(() {
                            incentiveHoursError = tempIncentiveEffectHours > tempDefaultHours
                                ? '≤ ${tempDefaultHours.toStringAsFixed(tempDefaultHours.truncateToDouble() == tempDefaultHours ? 0 : 1)}h'
                                : null;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Row 3: workplace (full width)
                TextField(
                  controller: workplaceHourlyController,
                  decoration: InputDecoration(
                    labelText: l.get('workplace'),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: const Icon(Icons.business, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (v) {
                    tempWorkplaceHourly = v;
                  },
                ),
                const SizedBox(height: 12),
              ],
              // Workplace field — lump sum mode only (hourly has its own inside the rate section)
              if (tempLumpSum) ...[
                TextField(
                  controller: workplaceDailyController,
                  decoration: InputDecoration(
                    labelText: l.get('workplace'),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: const Icon(Icons.business, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (v) {
                    tempWorkplaceDaily = v;
                  },
                ),
              ],
              const SizedBox(height: 20),

              // Tax rate inputs (per mode)
              Text(l.get('tax_section'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF00B8A9))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: tempLumpSum ? settingsTaxDailyController : settingsTaxHourlyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: _percentFormatters,
                      decoration: InputDecoration(
                        labelText: l.get('include_flat_tax'),
                        suffixText: '%',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (v) {
                        var val = double.tryParse(v) ?? 0;
                        if (val < 0) val = 0;
                        final otherIns = tempLumpSum ? tempInsuranceRateDaily : tempInsuranceRateHourly;
                        final maxAllowed = 99 - otherIns;
                        if (val > maxAllowed) {
                          val = maxAllowed < 0 ? 0 : maxAllowed;
                          final clamped = val == val.roundToDouble()
                              ? val.toStringAsFixed(0)
                              : val.toString();
                          final ctrl = tempLumpSum ? settingsTaxDailyController : settingsTaxHourlyController;
                          ctrl.value = TextEditingValue(
                            text: clamped,
                            selection: TextSelection.collapsed(offset: clamped.length),
                          );
                        }
                        if (tempLumpSum) { tempTaxRateDaily = val; } else { tempTaxRateHourly = val; }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: tempLumpSum ? settingsInsDailyController : settingsInsHourlyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: _percentFormatters,
                      decoration: InputDecoration(
                        labelText: l.get('include_insurance'),
                        suffixText: '%',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (v) {
                        var val = double.tryParse(v) ?? 0;
                        if (val < 0) val = 0;
                        final otherTax = tempLumpSum ? tempTaxRateDaily : tempTaxRateHourly;
                        final maxAllowed = 99 - otherTax;
                        if (val > maxAllowed) {
                          val = maxAllowed < 0 ? 0 : maxAllowed;
                          final clamped = val == val.roundToDouble()
                              ? val.toStringAsFixed(0)
                              : val.toString();
                          final ctrl = tempLumpSum ? settingsInsDailyController : settingsInsHourlyController;
                          ctrl.value = TextEditingValue(
                            text: clamped,
                            selection: TextSelection.collapsed(offset: clamped.length),
                          );
                        }
                        if (tempLumpSum) { tempInsuranceRateDaily = val; } else { tempInsuranceRateHourly = val; }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Save / Cancel buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(l.get('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: incentiveHoursError != null ? null : () {
                        // Apply all changes
                        _hourlyRate = tempHourlyRate;
                        app.storage.setHourlyRate(app.country, tempHourlyRate);
                        app.storage.setDefaultHours(tempDefaultHours);
                        app.storage.setDefaultWorkplaceHourly(tempWorkplaceHourly);
                        app.storage.setDefaultWorkplaceDaily(tempWorkplaceDaily);
                        app.storage.setDefaultLumpSum(tempLumpSum);
                        app.storage.setDefaultPayment(tempDefaultPayment);
                        app.setTaxRateHourly(tempTaxRateHourly);
                        app.setInsuranceRateHourly(tempInsuranceRateHourly);
                        app.setTaxRateDaily(tempTaxRateDaily);
                        app.setInsuranceRateDaily(tempInsuranceRateDaily);
                        app.setIncentiveHourly(tempIncentiveHourly);
                        app.setIncentiveEffectHoursHourly(tempIncentiveEffectHours);
                        app.refreshRates();
                        setState(() {});
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l.get('save')),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            backgroundColor: const Color(0xFF00B8A9),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(l.get('save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mutable in-dialog draft for a single work entry.
/// Lets the user edit up to [_CalendarScreenState._maxEntriesPerDay] entries
/// per day and commit them all at once.
class _EntryDraft {
  double value;
  double? rate;
  bool isLumpSum;
  bool isOvertime;
  bool isNightShift;
  String workplace;
  double taxRate;
  double insuranceRate;
  double incentivePercent;
  double incentiveEffectHours;

  _EntryDraft({
    required this.value,
    this.rate,
    required this.isLumpSum,
    this.isOvertime = false,
    this.isNightShift = false,
    this.workplace = '',
    this.taxRate = 0,
    this.insuranceRate = 0,
    this.incentivePercent = 0,
    this.incentiveEffectHours = 0,
  });

  factory _EntryDraft.fromEntry(WorkEntry e) => _EntryDraft(
        value: e.value,
        rate: e.rate,
        isLumpSum: e.isLumpSum,
        isOvertime: e.isOvertime,
        isNightShift: e.isNightShift,
        workplace: e.workplace,
        taxRate: e.taxRate,
        insuranceRate: e.insuranceRate,
        incentivePercent: e.incentivePercent,
        incentiveEffectHours: e.incentiveEffectHours,
      );

  factory _EntryDraft.newDefault(
    AppState app,
    double defaultHourlyRate, {
    bool? isLumpSum,
  }) {
    final lump = isLumpSum ?? app.storage.getDefaultLumpSum();
    return _EntryDraft(
      value: lump ? app.storage.getDefaultPayment() : app.storage.getDefaultHours(),
      rate: lump ? null : defaultHourlyRate,
      isLumpSum: lump,
      workplace: lump
          ? app.storage.getDefaultWorkplaceDaily()
          : app.storage.getDefaultWorkplaceHourly(),
      taxRate: app.taxRate(lump),
      insuranceRate: app.insuranceRate(lump),
      incentivePercent: lump ? 0 : app.incentiveHourly,
      incentiveEffectHours: lump ? 0 : app.incentiveEffectHoursHourly,
    );
  }
}
