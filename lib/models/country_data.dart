/// Country configurations: tax rates, holidays, insurance, currencies
/// for 8 supported countries.

enum CountryCode { kr }

class CountryConfig {
  final CountryCode code;
  final String currencySymbol;
  final String currencyCode;
  final double defaultHourlyRate;
  final double standardWorkHours; // per day
  final List<TaxBracket> incomeTaxBrackets;
  final double localTaxRate; // flat rate on income tax (e.g. KR 10% of income tax)
  final InsuranceRates? insurance;      // 2026
  final InsuranceRates? insurance2025;
  final double dailyWorkerFlatTax; // e.g. KR 3.3%
  final bool usesDailyWorkerFlat;
  final List<Holiday> holidays2025;
  final List<Holiday> holidays2026;
  final MinimumWage minimumWage;
  final OvertimeRule overtimeRule;

  const CountryConfig({
    required this.code,
    required this.currencySymbol,
    required this.currencyCode,
    required this.defaultHourlyRate,
    required this.standardWorkHours,
    required this.incomeTaxBrackets,
    required this.localTaxRate,
    this.insurance,
    this.insurance2025,
    this.dailyWorkerFlatTax = 0,
    this.usesDailyWorkerFlat = false,
    required this.holidays2025,
    required this.holidays2026,
    required this.minimumWage,
    required this.overtimeRule,
  });
}

class TaxBracket {
  final double minIncome;
  final double maxIncome; // double.infinity for top bracket
  final double rate;
  const TaxBracket(this.minIncome, this.maxIncome, this.rate);
}

class InsuranceRates {
  final double nationalPension;
  final double healthInsurance;
  final double longTermCare; // as % of gross pay
  final double employmentInsurance;
  const InsuranceRates({
    this.nationalPension = 0,
    this.healthInsurance = 0,
    this.longTermCare = 0,
    this.employmentInsurance = 0,
  });
}

class Holiday {
  final DateTime date;
  final String nameKey; // i18n key or direct name
  const Holiday(this.date, this.nameKey);
}

class MinimumWage {
  final double hourly2025;
  final double hourly2026;
  final double? daily2025;
  final double? daily2026;
  const MinimumWage({
    required this.hourly2025,
    required this.hourly2026,
    this.daily2025,
    this.daily2026,
  });
}

class OvertimeRule {
  final double multiplier; // e.g. 1.5x
  final double holidayMultiplier;
  final double nightShiftMultiplier; // 야간근무 (22:00~06:00)
  final String description;
  const OvertimeRule({
    required this.multiplier,
    required this.holidayMultiplier,
    this.nightShiftMultiplier = 1.0,
    required this.description,
  });
}

/// Work entry for a single day
class WorkEntry {
  final DateTime date;
  final double value; // hours (단가 mode) or payment amount (단건 mode)
  final double? rate; // custom hourly rate override (단가 mode only)
  final bool isLumpSum; // true = 단건 (fixed payment), false = 단가 (hours × rate)
  final bool isOvertime;
  final bool isHoliday;
  final bool isNightShift;
  final String workplace;
  final double taxRate; // income tax percentage (e.g. 3.3)
  final double insuranceRate; // insurance percentage (e.g. 9.4)
  // 단가 mode only — bonus percentage applied to the first N hours.
  final double incentivePercent;
  final double incentiveEffectHours;

  const WorkEntry({
    required this.date,
    required this.value,
    this.rate,
    this.isLumpSum = false,
    this.isOvertime = false,
    this.isHoliday = false,
    this.isNightShift = false,
    this.workplace = '',
    this.taxRate = 0,
    this.insuranceRate = 0,
    this.incentivePercent = 0,
    this.incentiveEffectHours = 0,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'value': value,
        if (rate != null) 'rate': rate,
        'isLumpSum': isLumpSum,
        'isOvertime': isOvertime,
        'isHoliday': isHoliday,
        'isNightShift': isNightShift,
        'workplace': workplace,
        'taxRate': taxRate,
        'insuranceRate': insuranceRate,
        'incentivePercent': incentivePercent,
        'incentiveEffectHours': incentiveEffectHours,
      };

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
        date: DateTime.parse(json['date']),
        value: (json['value'] as num).toDouble(),
        rate: (json['rate'] as num?)?.toDouble(),
        isLumpSum: json['isLumpSum'] ?? false,
        isOvertime: json['isOvertime'] ?? false,
        isHoliday: json['isHoliday'] ?? false,
        isNightShift: json['isNightShift'] ?? false,
        workplace: json['workplace'] ?? json['memo'] ?? '',
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? (json['includeFlatTax'] == true ? 3.3 : 0),
        insuranceRate: (json['insuranceRate'] as num?)?.toDouble() ?? (json['includeInsurance'] == true ? 9.4 : 0),
        incentivePercent: (json['incentivePercent'] as num?)?.toDouble() ?? 0,
        incentiveEffectHours: (json['incentiveEffectHours'] as num?)?.toDouble() ?? 0,
      );
}

/// Tax calculation result
class TaxResult {
  final double grossPay;
  final double incomeTax;
  final double localTax;
  final double nationalPension;
  final double healthInsurance;
  final double longTermCare;
  final double employmentInsurance;

  double get totalTax =>
      incomeTax + localTax + nationalPension + healthInsurance + longTermCare + employmentInsurance;
  double get netPay => grossPay - totalTax;

  /// Korean payroll practice: truncate each tax item to nearest 10원.
  /// 10원 미만 절사 (대부분의 회사 관행)
  TaxResult truncate10() {
    return TaxResult(
      grossPay: grossPay,
      incomeTax: (incomeTax / 10).floor() * 10.0,
      localTax: (localTax / 10).floor() * 10.0,
      nationalPension: (nationalPension / 10).floor() * 10.0,
      healthInsurance: (healthInsurance / 10).floor() * 10.0,
      longTermCare: (longTermCare / 10).floor() * 10.0,
      employmentInsurance: (employmentInsurance / 10).floor() * 10.0,
    );
  }

  const TaxResult({
    required this.grossPay,
    this.incomeTax = 0,
    this.localTax = 0,
    this.nationalPension = 0,
    this.healthInsurance = 0,
    this.longTermCare = 0,
    this.employmentInsurance = 0,
  });
}

// ─────────────────────────────────────────────
// Country Configurations
// ─────────────────────────────────────────────

final Map<CountryCode, CountryConfig> countryConfigs = {
  // ── South Korea ──
  CountryCode.kr: CountryConfig(
    code: CountryCode.kr,
    currencySymbol: '₩',
    currencyCode: 'KRW',
    defaultHourlyRate: 12000,
    standardWorkHours: 8,
    usesDailyWorkerFlat: true,
    dailyWorkerFlatTax: 0.033, // 3.3% (소득세 3% + 지방소득세 0.3%)
    incomeTaxBrackets: const [
      TaxBracket(0, 14000000, 0.06),
      TaxBracket(14000000, 50000000, 0.15),
      TaxBracket(50000000, 88000000, 0.24),
      TaxBracket(88000000, 150000000, 0.35),
      TaxBracket(150000000, 300000000, 0.38),
      TaxBracket(300000000, 500000000, 0.40),
      TaxBracket(500000000, 1000000000, 0.42),
      TaxBracket(1000000000, double.infinity, 0.45),
    ],
    localTaxRate: 0.1, // 10% of income tax
    insurance: const InsuranceRates(
      nationalPension: 0.0475,      // 국민연금 4.75% (2026)
      healthInsurance: 0.03595,     // 건강보험 3.595% (2026)
      longTermCare: 0.004724,       // 장기요양 0.4724% (2026)
      employmentInsurance: 0.009,   // 고용보험 0.9%
    ),
    insurance2025: const InsuranceRates(
      nationalPension: 0.045,       // 국민연금 4.5% (2025)
      healthInsurance: 0.03545,     // 건강보험 3.545% (2025)
      longTermCare: 0.004591,       // 장기요양 0.4591% (2025)
      employmentInsurance: 0.009,   // 고용보험 0.9%
    ),
    minimumWage: const MinimumWage(
      hourly2025: 10030,
      hourly2026: 10570,
      daily2025: 80240,
      daily2026: 84560,
    ),
    overtimeRule: const OvertimeRule(
      multiplier: 1.5,
      holidayMultiplier: 1.5,
      nightShiftMultiplier: 1.5, // 야간근무 22:00~06:00 150%
      description: '연장근무 150%, 휴일근무 150%, 공휴일근무 150%, 야간근무 150%\n야간+휴일 = 200%\n(시급제 전용, 1일 8시간 초과 시 적용)',
    ),
    holidays2025: [
      Holiday(DateTime(2025, 1, 1), '신정'),
      Holiday(DateTime(2025, 1, 28), '설날 연휴'),
      Holiday(DateTime(2025, 1, 29), '설날'),
      Holiday(DateTime(2025, 1, 30), '설날 연휴'),
      Holiday(DateTime(2025, 3, 1), '삼일절'),
      Holiday(DateTime(2025, 5, 5), '어린이날'),
      Holiday(DateTime(2025, 5, 6), '부처님오신날'),
      Holiday(DateTime(2025, 6, 6), '현충일'),
      Holiday(DateTime(2025, 8, 15), '광복절'),
      Holiday(DateTime(2025, 10, 3), '개천절'),
      Holiday(DateTime(2025, 10, 5), '추석 연휴'),
      Holiday(DateTime(2025, 10, 6), '추석'),
      Holiday(DateTime(2025, 10, 7), '추석 연휴'),
      Holiday(DateTime(2025, 10, 9), '한글날'),
      Holiday(DateTime(2025, 12, 25), '크리스마스'),
    ],
    holidays2026: [
      Holiday(DateTime(2026, 1, 1), '신정'),
      Holiday(DateTime(2026, 2, 16), '설날 연휴'),
      Holiday(DateTime(2026, 2, 17), '설날'),
      Holiday(DateTime(2026, 2, 18), '설날 연휴'),
      Holiday(DateTime(2026, 3, 1), '삼일절'),
      Holiday(DateTime(2026, 5, 5), '어린이날'),
      Holiday(DateTime(2026, 5, 24), '부처님오신날'),
      Holiday(DateTime(2026, 6, 6), '현충일'),
      Holiday(DateTime(2026, 8, 15), '광복절'),
      Holiday(DateTime(2026, 9, 24), '추석 연휴'),
      Holiday(DateTime(2026, 9, 25), '추석'),
      Holiday(DateTime(2026, 9, 26), '추석 연휴'),
      Holiday(DateTime(2026, 10, 3), '개천절'),
      Holiday(DateTime(2026, 10, 9), '한글날'),
      Holiday(DateTime(2026, 12, 25), '크리스마스'),
    ],
  ),
};
