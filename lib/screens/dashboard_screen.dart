import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/country_data.dart';
import '../services/app_state.dart';
import '../services/tax_calculator.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _showYearly = false;
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
  }

  /// Calculate aggregated tax across entries using each entry's own tax/insurance rates
  TaxResult _calcPerEntryTax(List<WorkEntry> entries, double hourlyRate) {
    double grossPay = 0;
    double totalTax = 0;
    double totalInsurance = 0;
    for (final e in entries) {
      final entryGross = e.isLumpSum ? e.value : e.value * (e.rate ?? hourlyRate);
      grossPay += entryGross;
      totalTax += entryGross * e.taxRate / 100;
      totalInsurance += entryGross * e.insuranceRate / 100;
    }
    return TaxResult(
      grossPay: grossPay,
      incomeTax: totalTax,
      nationalPension: totalInsurance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.get('dashboard_title')),
        actions: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(l.get('monthly_summary'), style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: true, label: Text(l.get('yearly_summary'), style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            selected: {_showYearly},
            onSelectionChanged: (s) => setState(() => _showYearly = s.first),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Month/Year selector
          _buildDateSelector(l),
          // Content
          Expanded(
            child: _showYearly
                ? _buildYearlyView(app, l)
                : _buildMonthlyView(app, l),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector(AppLocalizations l) {
    if (_showYearly) {
      // Year selector
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _selectedYear--),
            ),
            GestureDetector(
              onTap: () => _showYearPicker(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B8A9).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_selectedYear',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00B8A9),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _selectedYear++),
            ),
          ],
        ),
      );
    } else {
      // Month + Year selector
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _selectedMonth--;
                  if (_selectedMonth < 1) {
                    _selectedMonth = 12;
                    _selectedYear--;
                  }
                });
              },
            ),
            GestureDetector(
              onTap: () => _showMonthYearPicker(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B8A9).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_selectedYear / $_selectedMonth',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00B8A9),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _selectedMonth++;
                  if (_selectedMonth > 12) {
                    _selectedMonth = 1;
                    _selectedYear++;
                  }
                });
              },
            ),
          ],
        ),
      );
    }
  }

  void _showYearPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        int tempYear = _selectedYear;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Select Year'),
              content: SizedBox(
                height: 200,
                width: 200,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 50,
                  perspective: 0.005,
                  controller: FixedExtentScrollController(
                    initialItem: _selectedYear - 2024,
                  ),
                  onSelectedItemChanged: (index) {
                    setDialogState(() => tempYear = 2024 + index);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (ctx, index) {
                      final year = 2024 + index;
                      if (year < 2024 || year > 2030) return null;
                      return Center(
                        child: Text(
                          '$year',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: year == tempYear
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: year == tempYear
                                ? const Color(0xFF00B8A9)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() => _selectedYear = tempYear);
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

  void _showMonthYearPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        int tempYear = _selectedYear;
        int tempMonth = _selectedMonth;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Select Month'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Year row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setDialogState(() => tempYear--),
                      ),
                      Text(
                        '$tempYear',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setDialogState(() => tempYear++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Month grid
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
                      _selectedYear = tempYear;
                      _selectedMonth = tempMonth;
                    });
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

  Widget _buildMonthlyView(AppState app, AppLocalizations l) {
    final entries = app.storage.getWorkEntries(_selectedYear, _selectedMonth);
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 64,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text(l.get('no_data'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }

    final hourlyRate = app.storage.getHourlyRate(app.country);

    final tax = _calcPerEntryTax(entries, hourlyRate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildPayCard(l, tax, app),
          const SizedBox(height: 16),
          _buildTaxBreakdown(l, tax, app),
          const SizedBox(height: 16),
          _buildWorkStats(l, entries, _selectedYear, _selectedMonth),
        ],
      ),
    );
  }

  Widget _buildYearlyView(AppState app, AppLocalizations l) {
    final hourlyRate = app.storage.getHourlyRate(app.country);

    final monthlyData = <int, double>{};
    final monthlyWorkDays = <int, int>{};
    final monthlyTotalMd = <int, double>{};
    final monthlyCalendarDays = <int, int>{};

    for (int m = 1; m <= 12; m++) {
      final entries = app.storage.getWorkEntries(_selectedYear, m);
      monthlyCalendarDays[m] = DateTime(_selectedYear, m + 1, 0).day;
      if (entries.isEmpty) {
        monthlyData[m] = 0;
        monthlyWorkDays[m] = 0;
        monthlyTotalMd[m] = 0;
        continue;
      }
      monthlyWorkDays[m] = entries.length;
      monthlyTotalMd[m] = entries.where((e) => !e.isLumpSum).fold<double>(0, (sum, e) => sum + e.value);
      final tax = _calcPerEntryTax(entries, hourlyRate);
      monthlyData[m] = tax.netPay;
    }

    final yearEntries = app.storage.getYearEntries(_selectedYear);
    if (yearEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 64,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text(l.get('no_data'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }

    final yearTax = _calcPerEntryTax(yearEntries, hourlyRate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildPayCard(l, yearTax, app),
          const SizedBox(height: 16),
          _buildMonthlyChart(l, monthlyData, monthlyWorkDays, monthlyTotalMd, monthlyCalendarDays, app),
          const SizedBox(height: 16),
          _buildTaxBreakdown(l, yearTax, app),
        ],
      ),
    );
  }

  Widget _buildPayCard(AppLocalizations l, TaxResult tax, AppState app) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              l.get('net_pay'),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              TaxCalculator.formatCurrency(tax.netPay, app.country),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _miniStat(l.get('gross_pay'),
                    TaxCalculator.formatCurrency(tax.grossPay, app.country),
                    const Color(0xFF00B8A9)),
                _miniStat(l.get('total_tax'),
                    '-${TaxCalculator.formatCurrency(tax.totalTax, app.country)}',
                    Colors.redAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildTaxBreakdown(AppLocalizations l, TaxResult tax, AppState app) {
    final items = <MapEntry<String, double>>[];
    if (tax.incomeTax > 0) items.add(MapEntry(l.get('income_tax'), tax.incomeTax));
    if (tax.localTax > 0) items.add(MapEntry(l.get('local_tax'), tax.localTax));
    if (tax.nationalPension > 0) items.add(MapEntry(l.get('national_pension'), tax.nationalPension));
    if (tax.healthInsurance > 0) items.add(MapEntry(l.get('health_insurance'), tax.healthInsurance));
    if (tax.longTermCare > 0) items.add(MapEntry(l.get('long_term_care'), tax.longTermCare));
    if (tax.employmentInsurance > 0) items.add(MapEntry(l.get('employment_insurance'), tax.employmentInsurance));

    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.get('tax_breakdown'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.key, style: TextStyle(fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                      Text(
                        '-${TaxCalculator.formatCurrency(item.value, app.country)}',
                        style: const TextStyle(fontSize: 13, color: Colors.redAccent),
                      ),
                    ],
                  ),
                )),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.get('total_tax'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  '-${TaxCalculator.formatCurrency(tax.totalTax, app.country)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: Colors.redAccent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkStats(
      AppLocalizations l, List<WorkEntry> entries, int year, int month) {
    double totalHours = 0;
    int lumpSumCount = 0;
    int holidayDays = 0;
    int overtimeDays = 0;
    int nightDays = 0;
    final workDaySet = <String>{};
    for (final e in entries) {
      workDaySet.add('${e.date.year}-${e.date.month}-${e.date.day}');
      if (e.isLumpSum) {
        lumpSumCount++;
      } else {
        totalHours += e.value;
      }
      if (e.isHoliday) holidayDays++;
      if (e.isOvertime) overtimeDays++;
      if (e.isNightShift) nightDays++;
    }
    final workDays = workDaySet.length;
    // Days in the selected month (handles Feb leap years correctly).
    final daysInMonth = DateTime(year, month + 1, 0).day;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.get('work_days'), style: const TextStyle(fontSize: 13)),
                Text('$workDays',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.get('total_hours'),
                    style: const TextStyle(fontSize: 13)),
                Text(totalHours.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            if (lumpSumCount > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.get('lump_sum_count'),
                      style: const TextStyle(fontSize: 13)),
                  Text('$lumpSumCount',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            if (holidayDays > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.get('holiday_work'), style: const TextStyle(fontSize: 13)),
                  Text('$holidayDays',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent)),
                ],
              ),
            ],
            if (overtimeDays > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.get('overtime'), style: const TextStyle(fontSize: 13)),
                  Text('$overtimeDays',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orangeAccent)),
                ],
              ),
            ],
            if (nightDays > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('야간 Night', style: TextStyle(fontSize: 13)),
                  Text('$nightDays',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueAccent)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyChart(
      AppLocalizations l,
      Map<int, double> data,
      Map<int, int> workDays,
      Map<int, double> totalMd,
      Map<int, int> calendarDays,
      AppState app) {
    final maxVal = data.values.fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.get('monthly_chart'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipRoundedRadius: 10,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final month = group.x;
                        final days = workDays[month] ?? 0;
                        final md = totalMd[month] ?? 0;
                        final total = calendarDays[month] ?? 0;
                        final pay = TaxCalculator.formatAmount(rod.toY, app.country);
                        final lines = <String>[
                          '$month${l.get('per_month')}',
                          '${l.get('salary')}: $pay',
                          '${l.get('work_days')} $days/$total${l.get('per_day')}',
                        ];
                        return BarTooltipItem(
                          lines.join('\n'),
                          const TextStyle(fontSize: 11, color: Colors.white, height: 1.4),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: data.entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: e.value > 0
                              ? const Color(0xFF00B8A9)
                              : Colors.grey.withOpacity(0.3),
                          width: 16,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
