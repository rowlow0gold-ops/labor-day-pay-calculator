import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/country_data.dart';
import '../models/price_data.dart';


class PricesScreen extends StatefulWidget {
  const PricesScreen({super.key});

  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF00B8A9);

  static const _countryColors = {
    CountryCode.kr: Color(0xFF00B8A9),
    CountryCode.jp: Color(0xFFE91E63),
    CountryCode.ca: Color(0xFFFF5722),
    CountryCode.au: Color(0xFF2196F3),
    CountryCode.us: Color(0xFF9C27B0),
  };

  static const _tabCountries = [null, CountryCode.kr, CountryCode.jp, CountryCode.ca, CountryCode.au, CountryCode.us];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double _toUsd(double localAmount, CountryCode code) {
    final rate = usdRates[code] ?? 1.0;
    return localAmount / rate;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isKo = l.locale.languageCode == 'ko';

    return Scaffold(
      appBar: AppBar(
        title: Text(isKo ? '물가' : 'Prices'),
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
            Tab(text: isKo ? '비교' : 'Compare'),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('🇰🇷', style: TextStyle(fontSize: 16)), const SizedBox(width: 4), Text(isKo ? '한국' : 'KR')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('🇯🇵', style: TextStyle(fontSize: 16)), const SizedBox(width: 4), Text(isKo ? '일본' : 'JP')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('🇨🇦', style: TextStyle(fontSize: 16)), const SizedBox(width: 4), Text(isKo ? '캐나다' : 'CA')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('🇦🇺', style: TextStyle(fontSize: 16)), const SizedBox(width: 4), Text(isKo ? '호주' : 'AU')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('🇺🇸', style: TextStyle(fontSize: 16)), const SizedBox(width: 4), Text(isKo ? '미국' : 'US')])),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(isKo),
          ...[CountryCode.kr, CountryCode.jp, CountryCode.ca, CountryCode.au, CountryCode.us]
              .map((code) => _buildCountryTab(code, isKo)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════
  // SUMMARY TAB
  // ════════════════════════════════════════════════

  Widget _buildSummaryTab(bool isKo) {
    final countries = CountryCode.values.where((c) => countryPrices.containsKey(c)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _badge(isKo ? '2026년 기준' : '2026', Colors.orange),
              const SizedBox(width: 8),
              _badge('USD', Colors.green),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isKo ? '5개국 물가 비교 (미국 달러 기준)' : '5-Country Price Comparison (USD)',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),

          // Big Mac
          _chartSection(
            title: isKo ? '빅맥' : 'Big Mac',
            countries: countries,
            getValue: (c) => _toUsd(countryPrices[c]!.bigMacPrice, c),
            format: (v) => '\$${v.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 20),

          // 1BR Rent
          _chartSection(
            title: isKo ? '1룸 월세' : '1BR Rent/mo',
            countries: countries,
            getValue: (c) => _toUsd(countryPrices[c]!.rentOneBedroomCenter, c),
            format: (v) => '\$${_fmtUsd(v)}',
          ),
          const SizedBox(height: 20),

          // 1BR Monthly Bills
          _chartSection(
            title: isKo ? '월 고정비 (1룸)' : 'Monthly Bills (1BR)',
            countries: countries,
            getValue: (c) {
              final p = countryPrices[c]!;
              return _toUsd(p.utilities1Room + p.monthlyInternet, c);
            },
            format: (v) => '\$${_fmtUsd(v)}',
          ),
          const SizedBox(height: 20),

          // 3BR Rent
          _chartSection(
            title: isKo ? '3룸 월세' : '3BR Rent/mo',
            countries: countries,
            getValue: (c) => _toUsd(countryPrices[c]!.rentThreeRoom, c),
            format: (v) => '\$${_fmtUsd(v)}',
          ),
          const SizedBox(height: 20),

          // 3BR Monthly Bills
          _chartSection(
            title: isKo ? '월 고정비 (3룸)' : 'Monthly Bills (3BR)',
            countries: countries,
            getValue: (c) {
              final p = countryPrices[c]!;
              return _toUsd(p.utilities3Room + p.monthlyInternet, c);
            },
            format: (v) => '\$${_fmtUsd(v)}',
          ),
          const SizedBox(height: 20),

          // 3BR Apartment
          _chartSection(
            title: isKo ? '3룸 아파트 매매' : '3BR Apt Purchase',
            countries: countries,
            getValue: (c) => _toUsd(countryPrices[c]!.housing.first.threeRoomPrice, c),
            format: (v) => '\$${_fmtUsdLarge(v)}',
          ),
          const SizedBox(height: 20),

          // 3BR Villa/Townhouse
          _chartSection(
            title: isKo ? '3룸 빌라/타운하우스 매매' : '3BR Villa/Townhouse',
            countries: countries,
            getValue: (c) {
              final housing = countryPrices[c]!.housing;
              return housing.length > 1 ? _toUsd(housing[1].threeRoomPrice, c) : _toUsd(housing.first.threeRoomPrice, c);
            },
            format: (v) => '\$${_fmtUsdLarge(v)}',
          ),
          const SizedBox(height: 20),

          // Property Tax
          _chartSection(
            title: isKo ? '재산세율' : 'Property Tax',
            countries: countries,
            getValue: (c) => countryPrices[c]!.propertyTaxRate * 100,
            format: (v) => '${v.toStringAsFixed(2)}%',
            isPercent: true,
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
    bool isPercent = false,
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
                  width: 70,
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

  String _fmtUsd(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _fmtUsdLarge(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${_fmtUsd(v.roundToDouble())}';
    return v.toStringAsFixed(0);
  }

  // ════════════════════════════════════════════════
  // COUNTRY TAB
  // ════════════════════════════════════════════════

  Widget _buildCountryTab(CountryCode code, bool isKo) {
    final config = countryConfigs[code];
    final prices = countryPrices[code];
    if (config == null || prices == null) return const SizedBox.shrink();

    final sym = config.currencySymbol;
    final cityName = isKo && prices.cityLocal != null ? prices.cityLocal! : prices.cityEn;
    final areaName = isKo && prices.threeRoomAreaLocal != null ? prices.threeRoomAreaLocal! : prices.threeRoomAreaEn;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // City badge
          Row(
            children: [
              _badge(isKo ? '2026년 기준' : '2026', Colors.orange),
              const SizedBox(width: 8),
              _badge(cityName, _accent),
            ],
          ),

          const SizedBox(height: 20),

          // ── Big Mac ──
          _sectionTitle(isKo && code == CountryCode.kr ? '빅맥 가격' : 'Big Mac Price'),
          const SizedBox(height: 8),
          _priceCard(
            icon: Icons.lunch_dining,
            iconColor: Colors.orange,
            title: 'Big Mac',
            value: '$sym${_fmtPrice(prices.bigMacPrice)}',
            subtitle: isKo && code == CountryCode.kr ? '빅맥 지수 기준' : 'Big Mac Index',
          ),

          const SizedBox(height: 24),

          // ── 1BR ──
          _sectionTitle(isKo && code == CountryCode.kr ? '1룸 ($cityName)' : '1BR ($cityName)'),
          const SizedBox(height: 8),
          _priceCard(
            icon: Icons.apartment,
            iconColor: Colors.blue,
            title: isKo && code == CountryCode.kr ? '월세' : 'Rent',
            value: '$sym${_fmtPrice(prices.rentOneBedroomCenter)}',
            subtitle: isKo && code == CountryCode.kr ? '월' : '/month',
          ),
          const SizedBox(height: 8),
          _priceCard(
            icon: Icons.bolt,
            iconColor: Colors.amber,
            title: isKo && code == CountryCode.kr ? '공과금 + 인터넷' : 'Utilities + Internet',
            value: '$sym${_fmtPrice(prices.utilities1Room + prices.monthlyInternet)}',
            subtitle: isKo && code == CountryCode.kr ? '월' : '/month',
          ),

          const SizedBox(height: 24),

          // ── 3BR ──
          _sectionTitle(isKo && code == CountryCode.kr ? '3룸 ($areaName)' : '3BR ($areaName)'),
          const SizedBox(height: 8),
          _priceCard(
            icon: Icons.home,
            iconColor: Colors.indigo,
            title: isKo && code == CountryCode.kr ? '월세' : 'Rent',
            value: '$sym${_fmtPrice(prices.rentThreeRoom)}',
            subtitle: isKo && code == CountryCode.kr ? '월' : '/month',
          ),
          const SizedBox(height: 8),
          _priceCard(
            icon: Icons.bolt,
            iconColor: Colors.amber,
            title: isKo && code == CountryCode.kr ? '공과금 + 인터넷' : 'Utilities + Internet',
            value: '$sym${_fmtPrice(prices.utilities3Room + prices.monthlyInternet)}',
            subtitle: isKo && code == CountryCode.kr ? '월' : '/month',
          ),

          const SizedBox(height: 24),

          // ── Housing Purchase ──
          _sectionTitle(isKo && code == CountryCode.kr ? '매매가 (3룸)' : 'Purchase Price (3BR)'),
          const SizedBox(height: 4),
          Text(
            areaName,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
          ),
          const SizedBox(height: 10),
          ...prices.housing.map((h) => _buildHousingOption(config, h, sym, isKo)),

          const SizedBox(height: 24),

          // ── Property Tax ──
          _sectionTitle(isKo && code == CountryCode.kr ? '재산세' : 'Property Tax'),
          const SizedBox(height: 8),
          _buildPropertyTax(config, prices, sym, isKo),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHousingOption(CountryConfig config, HousingOption h, String sym, bool isKo) {
    final typeName = (isKo && h.typeLocal != null) || (config.code == CountryCode.jp && h.typeLocal != null)
        ? h.typeLocal!
        : h.typeEn;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(typeName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade400)),
            ),
            const Spacer(),
            Text(
              '$sym${_fmtLargePrice(h.threeRoomPrice, config.code)}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyTax(CountryConfig config, PriceData prices, String sym, bool isKo) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, size: 20, color: Colors.purple.shade300),
              const SizedBox(width: 10),
              Text(
                '${(prices.propertyTaxRate * 100).toStringAsFixed(prices.propertyTaxRate * 100 == (prices.propertyTaxRate * 100).roundToDouble() ? 0 : 2)}%',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _accent),
              ),
              const SizedBox(width: 8),
              Text(
                isKo && config.code == CountryCode.kr ? '(연간)' : '(annual)',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isKo && prices.propertyTaxNoteLocal != null
                ? prices.propertyTaxNoteLocal!
                : prices.propertyTaxNoteEn,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          ),
          if (prices.propertyTaxRate > 0 && prices.housing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calculate, size: 16, color: Colors.orange.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${isKo && config.code == CountryCode.kr ? '예상 연간 재산세 (3룸)' : 'Est. annual tax (3BR)'}: $sym${_fmtPrice(prices.housing.first.threeRoomPrice * prices.propertyTaxRate)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBills(CountryConfig config, PriceData prices, String sym, bool isKo) {
    return Column(
      children: [
        _priceCard(
          icon: Icons.bolt,
          iconColor: Colors.amber,
          title: isKo && config.code == CountryCode.kr ? '공과금 (전기/가스/수도)' : 'Utilities (Electric/Gas/Water)',
          value: '$sym${_fmtPrice(prices.utilities3Room)}',
          subtitle: isKo && config.code == CountryCode.kr ? '3룸 기준 / 월' : '3BR / month',
        ),
        const SizedBox(height: 8),
        _priceCard(
          icon: Icons.wifi,
          iconColor: Colors.cyan,
          title: isKo && config.code == CountryCode.kr ? '인터넷' : 'Internet',
          value: '$sym${_fmtPrice(prices.monthlyInternet)}',
          subtitle: isKo && config.code == CountryCode.kr ? '월' : '/month',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accent.withOpacity(0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isKo && config.code == CountryCode.kr ? '월 합계' : 'Monthly Total',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                '$sym${_fmtPrice(prices.utilities3Room + prices.monthlyInternet)}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _accent),
              ),
            ],
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

  Widget _priceCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
              ],
            ),
          ),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _accent)),
        ],
      ),
    );
  }

  String _fmtPrice(double v) {
    final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    if (parts.length > 1) buf.write('.${parts[1]}');
    return buf.toString();
  }

  String _fmtLargePrice(double v, CountryCode code) {
    if (code == CountryCode.kr) {
      if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(v % 100000000 == 0 ? 0 : 1)}억';
      if (v >= 10000) return '${_fmtPrice(v / 10000)}만';
    }
    if (v >= 1000000) return '${_fmtPrice(v / 1000000)}M';
    if (v >= 1000) return '${_fmtPrice(v / 1000)}K';
    return _fmtPrice(v);
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }
}
