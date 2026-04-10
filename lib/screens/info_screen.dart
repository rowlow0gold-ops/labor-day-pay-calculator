import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/country_data.dart';
import '../services/app_state.dart';
import '../services/firestore_tax_service.dart';
import '../services/tax_calculator.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  static const _accent = Color(0xFF00B8A9);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    final ts = context.read<FirestoreTaxService>();
    final config = countryConfigs[app.country]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.get('tax_rates')),
      ),
      body: _buildTaxRatesTab(l, config, app, ts),
    );
  }

  // ─── TAX RATES TAB ──────────────────────────────────────────────
  Widget _buildTaxRatesTab(AppLocalizations l, CountryConfig config, AppState app, FirestoreTaxService ts) {
    final flat = ts.getFlatTax(app.country);
    final ins = ts.getInsurance(app.country);
    final ins2025 = config.insurance2025;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Daily Worker Flat Tax: Big number
          if (config.usesDailyWorkerFlat) ...[
            _sectionTitle('${l.get('income_tax_full')} (3.3%)'),
            const SizedBox(height: 8),
            Row(
              children: [
                _taxCircle(l.get('income_tax_full'), flat * 10 / 11 * 100, Colors.orange),
                const SizedBox(width: 12),
                _taxCircle(l.get('local_tax'), flat * 1 / 11 * 100, Colors.blueGrey),
                const SizedBox(width: 12),
                _taxCircle(l.get('total'), flat * 100, _accent),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // ── 사대보험 Bar Chart
          if (ins != null) ...[
            _sectionTitle('${l.get('social_insurance')} (${((ins.nationalPension + ins.healthInsurance + ins.longTermCare + ins.employmentInsurance) * 100).toStringAsFixed(2)}%)'),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _maxInsurance(ins) * 1.3,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final labels = [
                          l.get('national_pension'),
                          l.get('health_insurance'),
                          l.get('long_term_care'),
                          l.get('employment_insurance'),
                        ];
                        return BarTooltipItem(
                          '${labels[groupIndex]}\n${rod.toY.toStringAsFixed(3)}%',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final labels = [l.get('national_pension'), l.get('health_insurance'), l.get('long_term_care'), l.get('employment_insurance')];
                          if (value.toInt() >= 0 && value.toInt() < labels.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(labels[value.toInt()],
                                  style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 9,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)));
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    _insuranceBar(0, ins.nationalPension * 100, const Color(0xFF00B8A9)),
                    _insuranceBar(1, ins.healthInsurance * 100, const Color(0xFF0097A7)),
                    _insuranceBar(2, ins.longTermCare * 100, const Color(0xFF4DD0E1)),
                    _insuranceBar(3, ins.employmentInsurance * 100, const Color(0xFF80CBC4)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Percentage labels under bars
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _percentLabel('${(ins.nationalPension * 100).toStringAsFixed(2)}%'),
                _percentLabel('${(ins.healthInsurance * 100).toStringAsFixed(2)}%'),
                _percentLabel('${(ins.longTermCare * 100).toStringAsFixed(4)}%'),
                _percentLabel('${(ins.employmentInsurance * 100).toStringAsFixed(2)}%'),
              ],
            ),
          ],

          // 총세금 summary
          if (config.usesDailyWorkerFlat && ins != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accent.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: _accent),
                      const SizedBox(width: 8),
                      Text(l.get('total_tax_label'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(
                    '${((flat + ins.nationalPension + ins.healthInsurance + ins.longTermCare + ins.employmentInsurance) * 100).toStringAsFixed(2)}%',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00B8A9)),
                  ),
                ],
              ),
            ),
          ],

          // 2025 vs 2026 comparison
          if (ins != null && ins2025 != null) ...[
            const SizedBox(height: 24),
            _sectionTitle('2025 vs 2026'),
            const SizedBox(height: 8),
            _insCompareRow(l.get('national_pension'), ins2025.nationalPension, ins.nationalPension),
            const SizedBox(height: 6),
            _insCompareRow(l.get('health_insurance'), ins2025.healthInsurance, ins.healthInsurance),
            const SizedBox(height: 6),
            _insCompareRow(l.get('long_term_care'), ins2025.longTermCare, ins.longTermCare),
            const SizedBox(height: 6),
            _insCompareRow(l.get('employment_insurance'), ins2025.employmentInsurance, ins.employmentInsurance),
          ],
        ],
      ),
    );
  }

  Widget _insCompareRow(String label, double rate2025, double rate2026) {
    final pct2025 = (rate2025 * 100).toStringAsFixed(2);
    final pct2026 = (rate2026 * 100).toStringAsFixed(2);
    final changed = rate2025 != rate2026;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Text('$pct2025%', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          const Text('  →  ', style: TextStyle(fontSize: 12)),
          Text('$pct2026%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          if (changed) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+${((rate2026 - rate2025) * 100).toStringAsFixed(2)}%',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF00B8A9)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _maxInsurance(InsuranceRates ins) {
    final values = [ins.nationalPension, ins.healthInsurance, ins.longTermCare, ins.employmentInsurance];
    return values.reduce((a, b) => a > b ? a : b) * 100;
  }

  BarChartGroupData _insuranceBar(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 28,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ],
    );
  }

  Widget _taxCircle(String label, double percent, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              '${percent.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }

  Widget _percentLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _accent,
      ),
    );
  }

  // ─── SHARED WIDGETS ───────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}
