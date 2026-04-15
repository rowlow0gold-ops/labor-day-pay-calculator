/// Country configurations: tax rates, holidays, insurance, currencies
/// for 5 supported countries.

enum CountryCode { kr, jp, ca, au, us }

class CountryConfig {
  final CountryCode code;
  final String flag; // emoji flag
  final String nameEn;
  final String? nameLocal; // in country's own language (null = English only)
  final String currencySymbol;
  final String currencyCode;
  final double defaultHourlyRate;
  final double standardWorkHours; // per day
  final List<TaxBracket> incomeTaxBrackets;
  final double localTaxRate; // flat rate on income tax (e.g. KR 10% of income tax)
  final InsuranceRates? insurance;      // 2026 (employee share, for tax calc)
  final InsuranceRates? insurance2025;
  final InsuranceRates? insuranceTotal;     // 2026 (employer+employee, for display)
  final InsuranceRates? insuranceTotal2025;
  final double dailyWorkerFlatTax; // e.g. KR 3.3%
  final bool usesDailyWorkerFlat;
  final String? flatTaxLabelEn;
  final String? flatTaxLabelLocal;
  /// Display names for the 4 deduction slots [pension, health, care, employment].
  final List<String> deductionLabelsEn;
  final List<String>? deductionLabelsLocal;
  /// Group label for deductions (e.g. "4대보험", "Social Insurance")
  final String deductionGroupEn;
  final String? deductionGroupLocal;
  /// Who pays each deduction slot (e.g. "50/50", "Employer only")
  final List<String> deductionNotesEn;
  final List<String>? deductionNotesLocal;
  /// Minor additional taxes (local tax, state tax, etc.)
  final List<MinorTax> minorTaxes;
  /// Default annual income for tax calculator (중산층 single 28-32)
  final double defaultAnnualIncome;
  final List<Holiday> holidays2025;
  final List<Holiday> holidays2026;
  final MinimumWage minimumWage;
  final OvertimeRule overtimeRule;

  const CountryConfig({
    required this.code,
    this.flag = '',
    this.nameEn = '',
    this.nameLocal,
    required this.currencySymbol,
    required this.currencyCode,
    required this.defaultHourlyRate,
    required this.standardWorkHours,
    required this.incomeTaxBrackets,
    required this.localTaxRate,
    this.insurance,
    this.insurance2025,
    this.insuranceTotal,
    this.insuranceTotal2025,
    this.dailyWorkerFlatTax = 0,
    this.usesDailyWorkerFlat = false,
    this.flatTaxLabelEn,
    this.flatTaxLabelLocal,
    this.deductionLabelsEn = const ['Pension', 'Health', 'Care', 'Employment'],
    this.deductionLabelsLocal,
    this.deductionGroupEn = 'Social Insurance',
    this.deductionGroupLocal,
    this.deductionNotesEn = const [],
    this.deductionNotesLocal,
    this.minorTaxes = const [],
    this.defaultAnnualIncome = 0,
    required this.holidays2025,
    required this.holidays2026,
    required this.minimumWage,
    required this.overtimeRule,
  });
}

class MinorTax {
  final String labelEn;
  final String? labelLocal;
  final double rate;          // flat rate (e.g. 0.10 = 10%)
  final bool isPercentOfIncomeTax; // true = rate × income_tax, false = rate × gross
  final String descEn;
  final String? descLocal;
  const MinorTax({
    required this.labelEn,
    this.labelLocal,
    required this.rate,
    this.isPercentOfIncomeTax = false,
    this.descEn = '',
    this.descLocal,
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
  // Freeform memo text. Available in both hourly (단가) and lump-sum (일시금)
  // modes.
  final String memo;
  // Lump-sum (단건) only — optional worked-hours field so users can still
  // record *how long* a fixed-payment gig took. Zero means "not entered",
  // and the calendar cell falls back to the money-icon indicator.
  final double lumpSumHours;

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
    this.memo = '',
    this.lumpSumHours = 0,
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
        'memo': memo,
        if (lumpSumHours > 0) 'lumpSumHours': lumpSumHours,
      };

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
        date: DateTime.parse(json['date']),
        value: (json['value'] as num).toDouble(),
        rate: (json['rate'] as num?)?.toDouble(),
        isLumpSum: json['isLumpSum'] ?? false,
        isOvertime: json['isOvertime'] ?? false,
        isHoliday: json['isHoliday'] ?? false,
        isNightShift: json['isNightShift'] ?? false,
        workplace: json['workplace'] ?? '',
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? (json['includeFlatTax'] == true ? 3.3 : 0),
        insuranceRate: (json['insuranceRate'] as num?)?.toDouble() ?? (json['includeInsurance'] == true ? 9.4 : 0),
        incentivePercent: (json['incentivePercent'] as num?)?.toDouble() ?? 0,
        incentiveEffectHours: (json['incentiveEffectHours'] as num?)?.toDouble() ?? 0,
        memo: json['memo'] ?? '',
        lumpSumHours: (json['lumpSumHours'] as num?)?.toDouble() ?? 0,
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
    flag: '🇰🇷',
    nameEn: 'South Korea',
    nameLocal: '대한민국',
    currencySymbol: '₩',
    currencyCode: 'KRW',
    defaultHourlyRate: 12000,
    standardWorkHours: 8,
    usesDailyWorkerFlat: true,
    dailyWorkerFlatTax: 0.033, // 3.3% (소득세 3% + 지방소득세 0.3%)
    flatTaxLabelEn: 'Income Tax (3.3%)',
    flatTaxLabelLocal: '소득세 (3.3%)',
    deductionLabelsEn: const ['National Pension', 'Health Insurance', 'Long-term Care', 'Employment Insurance'],
    deductionLabelsLocal: const ['국민연금', '건강보험', '장기요양보험', '고용보험'],
    deductionGroupEn: 'Social Insurance',
    deductionGroupLocal: '사대보험',
    deductionNotesEn: const ['Employer 50% + Employee 50%', 'Employer 50% + Employee 50%', 'Employer 50% + Employee 50%', 'Employer 50% + Employee 50%'],
    deductionNotesLocal: const ['사업주 50% + 근로자 50%', '사업주 50% + 근로자 50%', '사업주 50% + 근로자 50%', '사업주 50% + 근로자 50%'],
    minorTaxes: const [
      MinorTax(labelEn: 'Local Income Tax', labelLocal: '지방소득세', rate: 0.10, isPercentOfIncomeTax: true, descEn: '10% of income tax', descLocal: '소득세의 10%'),
    ],
    defaultAnnualIncome: 36000000, // 300만원/월 × 12
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
    insuranceTotal: const InsuranceRates(
      nationalPension: 0.095,       // 국민연금 9.5% (2026 총)
      healthInsurance: 0.0719,      // 건강보험 7.19% (2026 총)
      longTermCare: 0.009448,       // 장기요양 0.9448% (2026 총)
      employmentInsurance: 0.018,   // 고용보험 1.8% (2026 총)
    ),
    insuranceTotal2025: const InsuranceRates(
      nationalPension: 0.09,        // 국민연금 9.0% (2025 총)
      healthInsurance: 0.0709,      // 건강보험 7.09% (2025 총)
      longTermCare: 0.009182,       // 장기요양 0.9182% (2025 총)
      employmentInsurance: 0.018,   // 고용보험 1.8% (2025 총)
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

  // ── Japan ──
  CountryCode.jp: CountryConfig(
    code: CountryCode.jp,
    flag: '🇯🇵',
    nameEn: 'Japan',
    nameLocal: '日本',
    currencySymbol: '¥',
    currencyCode: 'JPY',
    defaultHourlyRate: 1200,
    standardWorkHours: 8,
    usesDailyWorkerFlat: false,
    incomeTaxBrackets: const [
      TaxBracket(0, 1950000, 0.05),
      TaxBracket(1950000, 3300000, 0.10),
      TaxBracket(3300000, 6950000, 0.20),
      TaxBracket(6950000, 9000000, 0.23),
      TaxBracket(9000000, 18000000, 0.33),
      TaxBracket(18000000, 40000000, 0.40),
      TaxBracket(40000000, double.infinity, 0.45),
    ],
    localTaxRate: 0.10, // 住民税 ~10%
    insurance: const InsuranceRates(
      nationalPension: 0.0915, // 厚生年金 18.3% / 2 = 9.15% (employee share)
      healthInsurance: 0.05,   // 健康保険 ~10% / 2 = ~5% (varies by prefecture)
      longTermCare: 0.009,     // 介護保険 ~1.8% / 2 = 0.9% (age 40+)
      employmentInsurance: 0.006, // 雇用保険 0.6% (2026)
    ),
    insurance2025: const InsuranceRates(
      nationalPension: 0.0915,
      healthInsurance: 0.05,
      longTermCare: 0.009,
      employmentInsurance: 0.006,
    ),
    insuranceTotal: const InsuranceRates(
      nationalPension: 0.183,    // 厚生年金 18.3% 総
      healthInsurance: 0.10,     // 健康保険 ~10% 総
      longTermCare: 0.018,       // 介護保険 ~1.8% 総
      employmentInsurance: 0.0155, // 雇用保険 1.55% 総 (0.6% + 0.95%)
    ),
    insuranceTotal2025: const InsuranceRates(
      nationalPension: 0.183,
      healthInsurance: 0.10,
      longTermCare: 0.018,
      employmentInsurance: 0.0155,
    ),
    deductionLabelsEn: const ['Pension', 'Health Insurance', 'Long-term Care', 'Employment Insurance'],
    deductionLabelsLocal: const ['厚生年金', '健康保険', '介護保険', '雇用保険'],
    deductionGroupEn: 'Social Insurance',
    deductionGroupLocal: '社会保険',
    deductionNotesEn: const ['Employer 50% + Employee 50%', 'Employer 50% + Employee 50%', 'Employer 50% + Employee 50%', 'Employee 0.6% + Employer 0.95%'],
    deductionNotesLocal: const ['事業主 50% + 従業員 50%', '事業主 50% + 従業員 50%', '事業主 50% + 従業員 50%', '従業員 0.6% + 事業主 0.95%'],
    minorTaxes: const [
      MinorTax(labelEn: 'Resident Tax', labelLocal: '住民税', rate: 0.10, descEn: '~10% of income (municipal + prefectural)', descLocal: '所得の約10%（市町村民税+都道府県民税）'),
      MinorTax(labelEn: 'Reconstruction Tax', labelLocal: '復興特別所得税', rate: 0.021, isPercentOfIncomeTax: true, descEn: '2.1% of income tax (until 2037)', descLocal: '所得税の2.1%（2037年まで）'),
    ],
    defaultAnnualIncome: 4000000, // ¥400万 (28-32歳 中間層)
    minimumWage: const MinimumWage(
      hourly2025: 1055, // weighted avg ~1055 (2025)
      hourly2026: 1100, // projected ~1100
    ),
    overtimeRule: const OvertimeRule(
      multiplier: 1.25,
      holidayMultiplier: 1.35,
      nightShiftMultiplier: 1.25, // 深夜 22:00~05:00
      description: 'Overtime 125%, Holiday 135%, Night (22:00~05:00) 125%\nOvertime+Night = 150%, Holiday+Night = 160%\n時間外 125%、休日 135%、深夜 125%',
    ),
    holidays2025: [
      Holiday(DateTime(2025, 1, 1), '元日'),
      Holiday(DateTime(2025, 1, 13), '成人の日'),
      Holiday(DateTime(2025, 2, 11), '建国記念の日'),
      Holiday(DateTime(2025, 2, 23), '天皇誕生日'),
      Holiday(DateTime(2025, 2, 24), '振替休日'),
      Holiday(DateTime(2025, 3, 20), '春分の日'),
      Holiday(DateTime(2025, 4, 29), '昭和の日'),
      Holiday(DateTime(2025, 5, 3), '憲法記念日'),
      Holiday(DateTime(2025, 5, 4), 'みどりの日'),
      Holiday(DateTime(2025, 5, 5), 'こどもの日'),
      Holiday(DateTime(2025, 5, 6), '振替休日'),
      Holiday(DateTime(2025, 7, 21), '海の日'),
      Holiday(DateTime(2025, 8, 11), '山の日'),
      Holiday(DateTime(2025, 9, 15), '敬老の日'),
      Holiday(DateTime(2025, 9, 23), '秋分の日'),
      Holiday(DateTime(2025, 10, 13), 'スポーツの日'),
      Holiday(DateTime(2025, 11, 3), '文化の日'),
      Holiday(DateTime(2025, 11, 23), '勤労感謝の日'),
      Holiday(DateTime(2025, 11, 24), '振替休日'),
    ],
    holidays2026: [
      Holiday(DateTime(2026, 1, 1), '元日'),
      Holiday(DateTime(2026, 1, 12), '成人の日'),
      Holiday(DateTime(2026, 2, 11), '建国記念の日'),
      Holiday(DateTime(2026, 2, 23), '天皇誕生日'),
      Holiday(DateTime(2026, 3, 20), '春分の日'),
      Holiday(DateTime(2026, 4, 29), '昭和の日'),
      Holiday(DateTime(2026, 5, 3), '憲法記念日'),
      Holiday(DateTime(2026, 5, 4), 'みどりの日'),
      Holiday(DateTime(2026, 5, 5), 'こどもの日'),
      Holiday(DateTime(2026, 5, 6), '振替休日'),
      Holiday(DateTime(2026, 7, 20), '海の日'),
      Holiday(DateTime(2026, 8, 11), '山の日'),
      Holiday(DateTime(2026, 9, 21), '敬老の日'),
      Holiday(DateTime(2026, 9, 22), '国民の休日'),
      Holiday(DateTime(2026, 9, 23), '秋分の日'),
      Holiday(DateTime(2026, 10, 12), 'スポーツの日'),
      Holiday(DateTime(2026, 11, 3), '文化の日'),
      Holiday(DateTime(2026, 11, 23), '勤労感謝の日'),
    ],
  ),

  // ── Canada ──
  CountryCode.ca: CountryConfig(
    code: CountryCode.ca,
    flag: '🇨🇦',
    nameEn: 'Canada',
    currencySymbol: '\$',
    currencyCode: 'CAD',
    defaultHourlyRate: 20,
    standardWorkHours: 8,
    usesDailyWorkerFlat: false,
    incomeTaxBrackets: const [
      TaxBracket(0, 57375, 0.15),
      TaxBracket(57375, 114750, 0.205),
      TaxBracket(114750, 158468, 0.26),
      TaxBracket(158468, 220000, 0.29),
      TaxBracket(220000, double.infinity, 0.33),
    ],
    localTaxRate: 0.0, // provincial tax varies; not modeled as flat rate
    insurance: const InsuranceRates(
      nationalPension: 0.0595,   // CPP 5.95% (2026)
      healthInsurance: 0.0,       // covered by provincial tax, not payroll
      longTermCare: 0.0,
      employmentInsurance: 0.0166, // EI 1.66% (2026)
    ),
    insurance2025: const InsuranceRates(
      nationalPension: 0.0595,
      healthInsurance: 0.0,
      longTermCare: 0.0,
      employmentInsurance: 0.0166,
    ),
    insuranceTotal: const InsuranceRates(
      nationalPension: 0.119,    // CPP 11.9% total (5.95% × 2)
      healthInsurance: 0.0,
      longTermCare: 0.0,
      employmentInsurance: 0.03986, // EI 3.986% total (employee 1.66% + employer 1.4× = 2.324%)
    ),
    insuranceTotal2025: const InsuranceRates(
      nationalPension: 0.119,
      healthInsurance: 0.0,
      longTermCare: 0.0,
      employmentInsurance: 0.03986,
    ),
    deductionLabelsEn: const ['CPP', 'Health', 'Care', 'EI'],
    deductionGroupEn: 'Payroll Deductions',
    deductionNotesEn: const ['Employer 50% + Employee 50%', '', '', 'Employee 1.66% + Employer 2.32%'],
    minorTaxes: const [
      MinorTax(labelEn: 'Provincial Tax (Alberta)', rate: 0.10, descEn: '10% flat rate on taxable income'),
    ],
    defaultAnnualIncome: 65000, // CAD 65K (28-32 single median)
    minimumWage: const MinimumWage(
      hourly2025: 17.20, // Federal min wage 2025
      hourly2026: 17.75, // projected
    ),
    overtimeRule: const OvertimeRule(
      multiplier: 1.5,
      holidayMultiplier: 1.5,
      nightShiftMultiplier: 1.0, // no federal night premium
      description: 'Overtime 150% after 8h/day or 40h/week (federal).\nHoliday work: 150% + holiday pay.\nProvincial rules may differ.',
    ),
    holidays2025: [
      Holiday(DateTime(2025, 1, 1), 'New Year\'s Day'),
      Holiday(DateTime(2025, 2, 17), 'Family Day'),
      Holiday(DateTime(2025, 4, 18), 'Good Friday'),
      Holiday(DateTime(2025, 5, 19), 'Victoria Day'),
      Holiday(DateTime(2025, 7, 1), 'Canada Day'),
      Holiday(DateTime(2025, 9, 1), 'Labour Day'),
      Holiday(DateTime(2025, 9, 30), 'National Day for Truth and Reconciliation'),
      Holiday(DateTime(2025, 10, 13), 'Thanksgiving'),
      Holiday(DateTime(2025, 11, 11), 'Remembrance Day'),
      Holiday(DateTime(2025, 12, 25), 'Christmas Day'),
    ],
    holidays2026: [
      Holiday(DateTime(2026, 1, 1), 'New Year\'s Day'),
      Holiday(DateTime(2026, 2, 16), 'Family Day'),
      Holiday(DateTime(2026, 4, 3), 'Good Friday'),
      Holiday(DateTime(2026, 5, 18), 'Victoria Day'),
      Holiday(DateTime(2026, 7, 1), 'Canada Day'),
      Holiday(DateTime(2026, 9, 7), 'Labour Day'),
      Holiday(DateTime(2026, 9, 30), 'National Day for Truth and Reconciliation'),
      Holiday(DateTime(2026, 10, 12), 'Thanksgiving'),
      Holiday(DateTime(2026, 11, 11), 'Remembrance Day'),
      Holiday(DateTime(2026, 12, 25), 'Christmas Day'),
    ],
  ),

  // ── Australia ──
  CountryCode.au: CountryConfig(
    code: CountryCode.au,
    flag: '🇦🇺',
    nameEn: 'Australia',
    currencySymbol: '\$',
    currencyCode: 'AUD',
    defaultHourlyRate: 25,
    standardWorkHours: 7.6,
    usesDailyWorkerFlat: false,
    incomeTaxBrackets: const [
      TaxBracket(0, 18200, 0.0),
      TaxBracket(18200, 45000, 0.16),
      TaxBracket(45000, 135000, 0.30),
      TaxBracket(135000, 190000, 0.37),
      TaxBracket(190000, double.infinity, 0.45),
    ],
    localTaxRate: 0.02, // Medicare levy 2%
    insurance: const InsuranceRates(
      nationalPension: 0.0,   // Super is employer-only, employee pays $0
      healthInsurance: 0.0,
      longTermCare: 0.0,
      employmentInsurance: 0.0,
    ),
    insurance2025: const InsuranceRates(
      nationalPension: 0.0,
      healthInsurance: 0.0,
      longTermCare: 0.0,
      employmentInsurance: 0.0,
    ),
    insuranceTotal: const InsuranceRates(
      nationalPension: 0.115,  // Super 11.5% (employer-only)
      healthInsurance: 0.0,
      longTermCare: 0.0,
      employmentInsurance: 0.0,
    ),
    insuranceTotal2025: const InsuranceRates(
      nationalPension: 0.115,
      healthInsurance: 0.0,
      longTermCare: 0.0,
      employmentInsurance: 0.0,
    ),
    deductionLabelsEn: const ['Superannuation', 'Health', 'Care', 'Employment'],
    deductionGroupEn: 'Payroll Deductions',
    deductionNotesEn: const ['Employer only (11.5%)', '', '', ''],
    minorTaxes: const [
      MinorTax(labelEn: 'Medicare Levy', rate: 0.02, descEn: '2% of taxable income'),
      MinorTax(labelEn: 'Medicare Levy Surcharge', rate: 0.0, descEn: '1-1.5% if no private health insurance & income >\$93K'),
    ],
    defaultAnnualIncome: 70000, // AUD 70K (28-32 single median)
    minimumWage: const MinimumWage(
      hourly2025: 24.10, // AUD
      hourly2026: 24.90, // projected
    ),
    overtimeRule: const OvertimeRule(
      multiplier: 1.5,
      holidayMultiplier: 2.0,
      nightShiftMultiplier: 1.15, // shift loading ~15%
      description: 'Overtime: 150% first 2h, 200% after.\nPublic holiday: 200%.\nShift loading varies by award (typically 15-30%).',
    ),
    holidays2025: [
      Holiday(DateTime(2025, 1, 1), 'New Year\'s Day'),
      Holiday(DateTime(2025, 1, 27), 'Australia Day'),
      Holiday(DateTime(2025, 4, 18), 'Good Friday'),
      Holiday(DateTime(2025, 4, 19), 'Saturday before Easter Sunday'),
      Holiday(DateTime(2025, 4, 21), 'Easter Monday'),
      Holiday(DateTime(2025, 4, 25), 'ANZAC Day'),
      Holiday(DateTime(2025, 6, 9), 'Queen\'s Birthday'),
      Holiday(DateTime(2025, 12, 25), 'Christmas Day'),
      Holiday(DateTime(2025, 12, 26), 'Boxing Day'),
    ],
    holidays2026: [
      Holiday(DateTime(2026, 1, 1), 'New Year\'s Day'),
      Holiday(DateTime(2026, 1, 26), 'Australia Day'),
      Holiday(DateTime(2026, 4, 3), 'Good Friday'),
      Holiday(DateTime(2026, 4, 4), 'Saturday before Easter Sunday'),
      Holiday(DateTime(2026, 4, 6), 'Easter Monday'),
      Holiday(DateTime(2026, 4, 25), 'ANZAC Day'),
      Holiday(DateTime(2026, 6, 8), 'Queen\'s Birthday'),
      Holiday(DateTime(2026, 12, 25), 'Christmas Day'),
      Holiday(DateTime(2026, 12, 26), 'Boxing Day'),
    ],
  ),

  // ── United States ──
  CountryCode.us: CountryConfig(
    code: CountryCode.us,
    flag: '🇺🇸',
    nameEn: 'United States',
    currencySymbol: '\$',
    currencyCode: 'USD',
    defaultHourlyRate: 15,
    standardWorkHours: 8,
    usesDailyWorkerFlat: false,
    incomeTaxBrackets: const [
      TaxBracket(0, 11925, 0.10),
      TaxBracket(11925, 48475, 0.12),
      TaxBracket(48475, 103350, 0.22),
      TaxBracket(103350, 197300, 0.24),
      TaxBracket(197300, 250525, 0.32),
      TaxBracket(250525, 626350, 0.35),
      TaxBracket(626350, double.infinity, 0.37),
    ],
    localTaxRate: 0.0, // state tax varies; not flat
    insurance: const InsuranceRates(
      nationalPension: 0.062,    // Social Security 6.2%
      healthInsurance: 0.0145,   // Medicare 1.45%
      longTermCare: 0.0,
      employmentInsurance: 0.0,  // FUTA paid by employer only
    ),
    insurance2025: const InsuranceRates(
      nationalPension: 0.062,
      healthInsurance: 0.0145,
      longTermCare: 0.0,
      employmentInsurance: 0.0,
    ),
    insuranceTotal: const InsuranceRates(
      nationalPension: 0.124,   // Social Security 12.4% total (6.2% × 2)
      healthInsurance: 0.029,   // Medicare 2.9% total (1.45% × 2)
      longTermCare: 0.0,
      employmentInsurance: 0.006, // FUTA 0.6% (employer only, after credit)
    ),
    insuranceTotal2025: const InsuranceRates(
      nationalPension: 0.124,
      healthInsurance: 0.029,
      longTermCare: 0.0,
      employmentInsurance: 0.006,
    ),
    deductionLabelsEn: const ['Social Security', 'Medicare', 'Care', 'Employment'],
    deductionGroupEn: 'FICA Taxes',
    deductionNotesEn: const ['Employer 50% + Employee 50%', 'Employer 50% + Employee 50%', '', 'Employer only (FUTA)'],
    minorTaxes: const [
      MinorTax(labelEn: 'State Tax (Texas)', rate: 0.0, descEn: 'No state income tax'),
    ],
    defaultAnnualIncome: 60000, // USD 60K (28-32 single median)
    minimumWage: const MinimumWage(
      hourly2025: 7.25, // federal
      hourly2026: 7.25, // federal (unchanged)
    ),
    overtimeRule: const OvertimeRule(
      multiplier: 1.5,
      holidayMultiplier: 1.0, // no federal holiday premium
      nightShiftMultiplier: 1.0, // no federal night differential
      description: 'Overtime 150% after 40h/week (FLSA).\nNo federal holiday or night premium.\nState laws may add additional requirements.',
    ),
    holidays2025: [
      Holiday(DateTime(2025, 1, 1), 'New Year\'s Day'),
      Holiday(DateTime(2025, 1, 20), 'Martin Luther King Jr. Day'),
      Holiday(DateTime(2025, 2, 17), 'Presidents\' Day'),
      Holiday(DateTime(2025, 5, 26), 'Memorial Day'),
      Holiday(DateTime(2025, 6, 19), 'Juneteenth'),
      Holiday(DateTime(2025, 7, 4), 'Independence Day'),
      Holiday(DateTime(2025, 9, 1), 'Labor Day'),
      Holiday(DateTime(2025, 10, 13), 'Columbus Day'),
      Holiday(DateTime(2025, 11, 11), 'Veterans Day'),
      Holiday(DateTime(2025, 11, 27), 'Thanksgiving'),
      Holiday(DateTime(2025, 12, 25), 'Christmas Day'),
    ],
    holidays2026: [
      Holiday(DateTime(2026, 1, 1), 'New Year\'s Day'),
      Holiday(DateTime(2026, 1, 19), 'Martin Luther King Jr. Day'),
      Holiday(DateTime(2026, 2, 16), 'Presidents\' Day'),
      Holiday(DateTime(2026, 5, 25), 'Memorial Day'),
      Holiday(DateTime(2026, 6, 19), 'Juneteenth'),
      Holiday(DateTime(2026, 7, 3), 'Independence Day (Observed)'),
      Holiday(DateTime(2026, 9, 7), 'Labor Day'),
      Holiday(DateTime(2026, 10, 12), 'Columbus Day'),
      Holiday(DateTime(2026, 11, 11), 'Veterans Day'),
      Holiday(DateTime(2026, 11, 26), 'Thanksgiving'),
      Holiday(DateTime(2026, 12, 25), 'Christmas Day'),
    ],
  ),
};
