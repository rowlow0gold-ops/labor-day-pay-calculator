import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../l10n/app_localizations.dart';
import '../models/country_data.dart';


class TaxRatesScreen extends StatefulWidget {
  const TaxRatesScreen({super.key});

  @override
  State<TaxRatesScreen> createState() => _TaxRatesScreenState();
}

class _TaxRatesScreenState extends State<TaxRatesScreen> with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF00B8A9);

  static const _countryColors = {
    CountryCode.kr: Color(0xFF00B8A9),
    CountryCode.jp: Color(0xFFE91E63),
    CountryCode.ca: Color(0xFFFF5722),
    CountryCode.au: Color(0xFF2196F3),
    CountryCode.us: Color(0xFF9C27B0),
  };

  late TabController _tabController;

  // Per-country calculator state
  final Map<CountryCode, TextEditingController> _incomeControllers = {};
  final Map<CountryCode, double> _calcIncomes = {};

  /// Country tab order based on current locale. The user's home country
  /// appears first so their own tax context is the default view.
  List<CountryCode> _orderedCountries(String langCode) {
    switch (langCode) {
      case 'ko':
        return const [CountryCode.kr, CountryCode.jp, CountryCode.us, CountryCode.au, CountryCode.ca];
      case 'ja':
        return const [CountryCode.jp, CountryCode.kr, CountryCode.us, CountryCode.au, CountryCode.ca];
      default: // English & others
        return const [CountryCode.us, CountryCode.au, CountryCode.ca, CountryCode.kr, CountryCode.jp];
    }
  }

  String _countryTabLabel(CountryCode code, String langCode) {
    final ko = langCode == 'ko';
    final ja = langCode == 'ja';
    switch (code) {
      case CountryCode.kr:
        return ko ? '한국' : (ja ? '韓国' : 'KR');
      case CountryCode.jp:
        return ko ? '일본' : (ja ? '日本' : 'JP');
      case CountryCode.us:
        return ko ? '미국' : (ja ? 'アメリカ' : 'US');
      case CountryCode.au:
        return ko ? '호주' : (ja ? 'オーストラリア' : 'AU');
      case CountryCode.ca:
        return ko ? '캐나다' : (ja ? 'カナダ' : 'CA');
    }
  }

  String _countryFlag(CountryCode code) {
    switch (code) {
      case CountryCode.kr: return '🇰🇷';
      case CountryCode.jp: return '🇯🇵';
      case CountryCode.us: return '🇺🇸';
      case CountryCode.au: return '🇦🇺';
      case CountryCode.ca: return '🇨🇦';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    for (final code in CountryCode.values) {
      final cfg = countryConfigs[code];
      if (cfg != null) {
        final def = cfg.defaultAnnualIncome;
        _incomeControllers[code] = TextEditingController(text: _fmtIncome(def));
        _calcIncomes[code] = def;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _incomeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmtIncome(double v) {
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = l.locale.languageCode;
    final isKo = lang == 'ko';
    final isJa = lang == 'ja';
    final order = _orderedCountries(lang);

    return Scaffold(
      appBar: AppBar(
        title: Text(isKo ? '세율' : (isJa ? '税率' : 'Tax Rates')),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            Tab(text: isKo ? '비교' : (isJa ? '比較' : 'Compare')),
            ...order.map((code) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_countryFlag(code), style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 4),
                      Text(_countryTabLabel(code, lang)),
                    ],
                  ),
                )),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(isKo),
          ...order.map((code) => _buildCountryTab(code, isKo)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════
  // SUMMARY TAB
  // ════════════════════════════════════════════════

  double _getInsuranceRate(CountryCode code) {
    final ins = countryConfigs[code]?.insurance;
    if (ins == null) return 0;
    return (ins.nationalPension + ins.healthInsurance + ins.longTermCare + ins.employmentInsurance) * 100;
  }

  double _getTopBracketRate(CountryCode code) {
    final brackets = countryConfigs[code]?.incomeTaxBrackets ?? [];
    if (brackets.isEmpty) return 0;
    return brackets.last.rate * 100;
  }

  double _getEffectiveRate(CountryCode code) {
    final cfg = countryConfigs[code];
    if (cfg == null) return 0;
    final income = cfg.defaultAnnualIncome;
    final brackets = cfg.incomeTaxBrackets;
    final ins = cfg.insurance;

    // Income tax
    double incomeTax = 0;
    double marginalRate = 0;
    for (final b in brackets) {
      if (income <= b.minIncome) continue;
      final taxable = (income > b.maxIncome ? b.maxIncome : income) - b.minIncome;
      incomeTax += taxable * b.rate;
      marginalRate = b.rate;
    }

    // Minor taxes
    double minorTotal = 0;
    for (final t in cfg.minorTaxes) {
      if (t.rate <= 0) continue;
      minorTotal += t.isPercentOfIncomeTax ? incomeTax * t.rate : income * t.rate;
    }

    // Insurance
    double insTotal = 0;
    if (ins != null) {
      insTotal = income * (ins.nationalPension + ins.healthInsurance + ins.longTermCare + ins.employmentInsurance);
    }

    final totalDeduction = incomeTax + minorTotal + insTotal;
    return (totalDeduction / income) * 100;
  }

  Widget _buildSummaryTab(bool isKo) {
    final lang = AppLocalizations.of(context).locale.languageCode;
    final countries = _orderedCountries(lang).where((c) => countryConfigs.containsKey(c)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _badge(isKo ? '2026년 기준' : '2026', Colors.orange),
          const SizedBox(height: 6),
          Text(
            isKo ? '5개국 세율 비교' : '5-Country Tax Rate Comparison',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),

          // Insurance Rate
          _chartSection(
            title: isKo ? '4대보험 (근로자)' : 'Insurance (Employee)',
            countries: countries,
            getValue: (c) => _getInsuranceRate(c),
            format: (v) => '${v.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 20),

          // Top Tax Bracket
          _chartSection(
            title: isKo ? '최고 소득세율' : 'Top Income Tax Rate',
            countries: countries,
            getValue: (c) => _getTopBracketRate(c),
            format: (v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%',
          ),
          const SizedBox(height: 20),

          // Effective Rate at default income
          _chartSection(
            title: isKo ? '실효세율 (기본 연봉 기준)' : 'Effective Rate (at default salary)',
            countries: countries,
            getValue: (c) => _getEffectiveRate(c),
            format: (v) => '${v.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isKo ? '기본 연봉 기준' : 'Default salaries used',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
                ),
                const SizedBox(height: 4),
                ...countries.map((c) {
                  final cfg = countryConfigs[c]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${cfg.flag} ${cfg.currencySymbol}${_fmtIncome(cfg.defaultAnnualIncome)}',
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Number of brackets
          _chartSection(
            title: isKo ? '소득세 구간 수' : 'Number of Tax Brackets',
            countries: countries,
            getValue: (c) => countryConfigs[c]!.incomeTaxBrackets.length.toDouble(),
            format: (v) => '${v.toInt()}',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _chartSection({
    required String title,
    required List<CountryCode> countries,
    required double Function(CountryCode) getValue,
    required String Function(double) format,
  }) {
    final values = {for (final c in countries) c: getValue(c)};
    final maxVal = values.values.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...countries.map((c) {
          final val = values[c]!;
          final ratio = maxVal > 0 ? val / maxVal : 0.0;
          final cfg = countryConfigs[c]!;
          final color = _countryColors[c] ?? _accent;

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(cfg.flag, style: const TextStyle(fontSize: 16)),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Container(
                            height: 22,
                            width: constraints.maxWidth * ratio,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 55,
                  child: Text(
                    format(val),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════
  // COUNTRY TAB
  // ════════════════════════════════════════════════

  Widget _buildCountryTab(CountryCode code, bool isKo) {
    final config = countryConfigs[code];
    if (config == null) return const SizedBox.shrink();

    final ins = config.insuranceTotal ?? config.insurance;
    final deductionLabels = _getDeductionLabels(config, isKo);
    final deductionGroup = _getDeductionGroup(config, isKo);
    final deductionNotes = _getDeductionNotes(config, isKo);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _badge(isKo ? '2026년 기준' : '2026', Colors.orange),
          const SizedBox(height: 16),
          if (ins != null) ...[
            _buildInsuranceChart(ins, deductionLabels, deductionGroup, deductionNotes),
          ],
          if (config.minorTaxes.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildMinorTaxes(config, isKo),
          ],
          const SizedBox(height: 24),
          _buildIncomeTaxBrackets(config, isKo),
          const SizedBox(height: 24),
          _buildTaxCalculator(config, code, isKo),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<String> _getDeductionLabels(CountryConfig config, bool isKo) {
    if (config.deductionLabelsLocal != null) {
      if (config.code == CountryCode.kr && isKo) return config.deductionLabelsLocal!;
      if (config.code == CountryCode.jp) return config.deductionLabelsLocal!;
    }
    return config.deductionLabelsEn;
  }

  String _getDeductionGroup(CountryConfig config, bool isKo) {
    if (config.deductionGroupLocal != null) {
      if (config.code == CountryCode.kr && isKo) return config.deductionGroupLocal!;
      if (config.code == CountryCode.jp) return config.deductionGroupLocal!;
    }
    return config.deductionGroupEn;
  }

  List<String> _getDeductionNotes(CountryConfig config, bool isKo) {
    if (config.deductionNotesLocal != null) {
      if (config.code == CountryCode.kr && isKo) return config.deductionNotesLocal!;
      if (config.code == CountryCode.jp) return config.deductionNotesLocal!;
    }
    return config.deductionNotesEn;
  }

  Widget _buildInsuranceChart(InsuranceRates ins, List<String> labels, String groupTitle, List<String> notes) {
    final items = <_InsItem>[];
    final allRates = [ins.nationalPension, ins.healthInsurance, ins.longTermCare, ins.employmentInsurance];
    final colors = [const Color(0xFF00B8A9), const Color(0xFF0097A7), const Color(0xFF4DD0E1), const Color(0xFF80CBC4)];

    for (var i = 0; i < 4; i++) {
      if (allRates[i] > 0) {
        final note = i < notes.length ? notes[i] : '';
        items.add(_InsItem(labels[i], allRates[i] * 100, colors[i], note));
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    final totalRate = items.fold<double>(0, (s, e) => s + e.pct);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('$groupTitle (${totalRate.toStringAsFixed(2)}%)'),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: items.map((e) => e.pct).reduce((a, b) => a > b ? a : b) * 1.3,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${items[groupIndex].label}\n${rod.toY.toStringAsFixed(3)}%',
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
                      final idx = value.toInt();
                      if (idx >= 0 && idx < items.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(items[idx].label,
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
                    interval: _calcYInterval(items.map((e) => e.pct).reduce((a, b) => a > b ? a : b)),
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox.shrink();
                      }
                      return Text('${value.toStringAsFixed(0)}%',
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
              barGroups: items.asMap().entries.map((e) => _insuranceBar(e.key, e.value.pct, e.value.color)).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items.map((e) => _percentLabel('${e.pct.toStringAsFixed(2)}%')).toList(),
        ),
        if (items.any((e) => e.note.isNotEmpty)) ...[
          const SizedBox(height: 16),
          ...items.where((e) => e.note.isNotEmpty).map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(e.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(e.note,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
          )),
        ],
      ],
    );
  }

  double _calcYInterval(double maxVal) {
    if (maxVal <= 2) return 0.5;
    if (maxVal <= 5) return 1.0;
    if (maxVal <= 10) return 2.0;
    if (maxVal <= 25) return 5.0;
    return 10.0;
  }

  Widget _buildMinorTaxes(CountryConfig config, bool isKo) {
    final taxes = config.minorTaxes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isKo && config.code == CountryCode.kr ? '기타 세금' : 'Additional Taxes'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: taxes.asMap().entries.map((entry) {
              final t = entry.value;
              final isLast = entry.key == taxes.length - 1;
              final label = (isKo && t.labelLocal != null) || (config.code == CountryCode.jp && t.labelLocal != null)
                  ? t.labelLocal!
                  : t.labelEn;
              final desc = (isKo && t.descLocal != null) || (config.code == CountryCode.jp && t.descLocal != null)
                  ? t.descLocal!
                  : t.descEn;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: isLast ? null : Border(bottom: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(desc, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                        ],
                      ),
                    ),
                    if (t.rate > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${(t.rate * 100).toStringAsFixed(t.rate * 100 == (t.rate * 100).roundToDouble() ? 0 : 2)}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTaxCalculator(CountryConfig config, CountryCode code, bool isKo) {
    final sym = config.currencySymbol;
    final brackets = config.incomeTaxBrackets;
    final ins = config.insurance;
    final calcIncome = _calcIncomes[code] ?? config.defaultAnnualIncome;
    final controller = _incomeControllers[code]!;

    double incomeTax = 0;
    double marginalRate = 0;
    for (final b in brackets) {
      if (calcIncome <= b.minIncome) continue;
      final taxable = (calcIncome > b.maxIncome ? b.maxIncome : calcIncome) - b.minIncome;
      incomeTax += taxable * b.rate;
      marginalRate = b.rate;
    }

    double minorTotal = 0;
    final minorItems = <_CalcRow>[];
    for (final t in config.minorTaxes) {
      if (t.rate <= 0) continue;
      final amt = t.isPercentOfIncomeTax ? incomeTax * t.rate : calcIncome * t.rate;
      minorTotal += amt;
      final label = (isKo && t.labelLocal != null) || (config.code == CountryCode.jp && t.labelLocal != null)
          ? t.labelLocal!
          : t.labelEn;
      final displayRate = t.isPercentOfIncomeTax ? marginalRate * t.rate : t.rate;
      minorItems.add(_CalcRow(label, amt, displayRate));
    }

    double insTotal = 0;
    double insRate = 0;
    if (ins != null) {
      insRate = ins.nationalPension + ins.healthInsurance + ins.longTermCare + ins.employmentInsurance;
      insTotal = calcIncome * insRate;
    }

    final totalDeduction = incomeTax + minorTotal + insTotal;
    final netIncome = calcIncome - totalDeduction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isKo && config.code == CountryCode.kr ? '세금 계산기' : 'Tax Calculator'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isKo && config.code == CountryCode.kr ? '연간 소득 (세전)' : 'Annual Income (before tax)',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(sym, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) {
                        final num = double.tryParse(v.replaceAll(',', '')) ?? 0;
                        setState(() => _calcIncomes[code] = num);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withOpacity(0.15)),
          ),
          child: Column(
            children: [
              _calcResultRow(
                '${isKo && config.code == CountryCode.kr ? '소득세' : 'Income Tax'} (${isKo ? '최고구간' : 'top bracket'} ${(marginalRate * 100).toStringAsFixed(marginalRate * 100 == (marginalRate * 100).roundToDouble() ? 0 : 1)}% → ${isKo ? '실효' : 'effective'} ${calcIncome > 0 ? (incomeTax / calcIncome * 100).toStringAsFixed(1) : '0.0'}%)',
                '$sym${_fmtCalc(incomeTax)}',
                bold: false,
              ),
              ...minorItems.map((r) => _calcResultRow(
                '${r.label} (${calcIncome > 0 ? (r.amount / calcIncome * 100).toStringAsFixed(1) : '0.0'}%)',
                '$sym${_fmtCalc(r.amount)}',
                bold: false,
              )),
              if (insTotal > 0) ...[
                _calcResultRow(
                  '${isKo && config.code == CountryCode.kr ? '4대보험 (근로자)' : 'Insurance (Employee)'} (${calcIncome > 0 ? (insTotal / calcIncome * 100).toStringAsFixed(1) : '0.0'}%)',
                  '$sym${_fmtCalc(insTotal)}',
                  bold: false,
                ),
              ],
              Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
              _calcResultRow(
                isKo && config.code == CountryCode.kr ? '총 공제액' : 'Total Deductions',
                '$sym${_fmtCalc(totalDeduction)}',
                color: Colors.red.shade400,
              ),
              const SizedBox(height: 4),
              _calcResultRow(
                isKo && config.code == CountryCode.kr ? '실수령액' : 'Net Income',
                '$sym${_fmtCalc(netIncome)}',
                color: _accent,
                large: true,
              ),
              const SizedBox(height: 4),
              Builder(builder: (_) {
                // Effective rate = actual total deductions / income. Each
                // component is shown as its real contribution (piece ÷ income)
                // so the three parts always sum to the effective rate — unlike
                // the old display which added marginal bracket + listed rates
                // and overstated the true burden.
                if (calcIncome <= 0) return const SizedBox.shrink();
                final incomeTaxShare = incomeTax / calcIncome * 100;
                final minorShare = minorTotal / calcIncome * 100;
                final insShare = insTotal / calcIncome * 100;
                final effectiveRate = totalDeduction / calcIncome * 100;
                final parts = <String>[];
                parts.add('${incomeTaxShare.toStringAsFixed(1)}%');
                if (minorShare > 0) parts.add('${minorShare.toStringAsFixed(1)}%');
                if (insShare > 0) parts.add('${insShare.toStringAsFixed(1)}%');
                final label = isKo && config.code == CountryCode.kr ? '실효세율' : 'Effective rate';
                return Text(
                  '$label ${parts.join(' + ')} = ${effectiveRate.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIncomeTaxBrackets(CountryConfig config, bool isKo) {
    final brackets = config.incomeTaxBrackets;
    if (brackets.isEmpty) return const SizedBox.shrink();

    final sym = config.currencySymbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isKo && config.code == CountryCode.kr ? '소득세율' : 'Income Tax Brackets'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: brackets.asMap().entries.map((entry) {
              final b = entry.value;
              final isLast = entry.key == brackets.length - 1;
              final range = b.maxIncome == double.infinity
                  ? '$sym${_fmtNum(b.minIncome)}+'
                  : '$sym${_fmtNum(b.minIncome)} ~ $sym${_fmtNum(b.maxIncome)}';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: isLast ? null : Border(bottom: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06))),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(range, style: const TextStyle(fontSize: 12))),
                    Text('${(b.rate * 100).toStringAsFixed(b.rate * 100 == (b.rate * 100).roundToDouble() ? 0 : 1)}%',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF00B8A9))),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _calcResultRow(String label, String value, {bool bold = true, Color? color, bool large = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: large ? 14 : 12, fontWeight: bold || large ? FontWeight.bold : FontWeight.w500))),
          Text(value, style: TextStyle(
            fontSize: large ? 16 : 13,
            fontWeight: bold || large ? FontWeight.bold : FontWeight.w500,
            color: color,
          )),
        ],
      ),
    );
  }

  String _fmtCalc(double v) {
    final abs = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    if (v < 0) buf.write('-');
    for (var i = 0; i < abs.length; i++) {
      if (i > 0 && (abs.length - i) % 3 == 0) buf.write(',');
      buf.write(abs[i]);
    }
    return buf.toString();
  }

  String _fmtNum(double n) {
    String _trim(double v) {
      // Keep up to 2 decimals but strip trailing zeros so 2.00→2, 1.95→1.95, 6.95→6.95
      var s = v.toStringAsFixed(2);
      if (s.contains('.')) {
        s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      }
      return s;
    }
    if (n >= 1000000000) return '${_trim(n / 1000000000)}B';
    if (n >= 1000000) return '${_trim(n / 1000000)}M';
    if (n >= 1000) return '${_trim(n / 1000)}K';
    return n.toStringAsFixed(0);
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

  Widget _percentLabel(String text) {
    return Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _accent));
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }
}

class _InsItem {
  final String label;
  final double pct;
  final Color color;
  final String note;
  const _InsItem(this.label, this.pct, this.color, [this.note = '']);
}

class _CalcRow {
  final String label;
  final double amount;
  final double rate;
  const _CalcRow(this.label, this.amount, this.rate);
}
