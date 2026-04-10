import '../models/country_data.dart';
import 'firestore_tax_service.dart';

class TaxCalculator {
  /// Calculate tax for a given gross pay and country.
  /// Uses Firestore data if available, otherwise local defaults.
  /// [includeFlatTax] — apply 3.3% flat tax (소득세 3% + 지방소득세 0.3%)
  /// [includeInsurance] — apply 4대보험
  /// Both flags are independent and can be combined.
  static TaxResult calculate({
    required double grossPay,
    required CountryCode country,
    required bool includeInsurance,
    bool includeFlatTax = true,
    FirestoreTaxService? taxService,
  }) {
    final config = countryConfigs[country]!;
    final flatTax = taxService?.getFlatTax(country) ?? config.dailyWorkerFlatTax;
    final insurance = taxService?.getInsurance(country) ?? config.insurance;

    double incomeTax = 0;
    double localTax = 0;

    // 3.3% flat tax (소득세 3% + 지방소득세 0.3%)
    if (config.usesDailyWorkerFlat && includeFlatTax) {
      incomeTax = grossPay * (flatTax * 10 / 11); // 3% portion
      localTax = grossPay * (flatTax * 1 / 11);   // 0.3% portion
    }

    // Insurance — all rates are % of gross
    double pension = 0, health = 0, ltc = 0, employment = 0;
    if (includeInsurance && insurance != null) {
      pension = grossPay * insurance.nationalPension;
      health = grossPay * insurance.healthInsurance;
      ltc = grossPay * insurance.longTermCare;
      employment = grossPay * insurance.employmentInsurance;
    }

    return TaxResult(
      grossPay: grossPay,
      incomeTax: incomeTax,
      localTax: localTax,
      nationalPension: pension,
      healthInsurance: health,
      longTermCare: ltc,
      employmentInsurance: employment,
    );
  }

  static double _calculateProgressiveTax(double income, List<TaxBracket> brackets) {
    double tax = 0;
    double remaining = income;

    for (final bracket in brackets) {
      if (remaining <= 0) break;
      final taxableInBracket = remaining.clamp(0, bracket.maxIncome - bracket.minIncome);
      tax += taxableInBracket * bracket.rate;
      remaining -= taxableInBracket;
    }

    return tax;
  }

  /// Calculate gross pay from work entries
  static double calculateGrossPay({
    required List<WorkEntry> entries,
    required CountryCode country,
    required double hourlyRate,
    FirestoreTaxService? taxService,
  }) {
    final config = countryConfigs[country]!;
    final overtime = taxService?.getOvertime(country) ?? config.overtimeRule;
    double total = 0;

    for (final entry in entries) {
      double baseAmount;
      if (entry.isLumpSum) {
        baseAmount = entry.value;
      } else {
        final rate = entry.rate ?? hourlyRate;
        baseAmount = entry.value * rate;
      }

      if (entry.isHoliday) {
        baseAmount *= overtime.holidayMultiplier;
      } else if (entry.isOvertime) {
        baseAmount *= overtime.multiplier;
      }
      if (entry.isNightShift) {
        baseAmount *= overtime.nightShiftMultiplier;
      }

      total += baseAmount;
    }

    return total;
  }

  /// Format currency value (with symbol)
  static String formatCurrency(double amount, CountryCode country) {
    final config = countryConfigs[country]!;
    final symbol = config.currencySymbol;

    // No decimals for KRW
    if (country == CountryCode.kr) {
      return '$symbol${_formatNumber(amount.round())}';
    }

    return '$symbol${amount.toStringAsFixed(2)}';
  }

  /// Format amount only (no symbol)
  static String formatAmount(double amount, CountryCode country) {
    if (country == CountryCode.kr) {
      return _formatNumber(amount.round());
    }
    return amount.toStringAsFixed(2);
  }

  static String _formatNumber(int number) {
    final str = number.abs().toString();
    final result = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      result.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) result.write(',');
    }
    final formatted = result.toString().split('').reversed.join();
    return number < 0 ? '-$formatted' : formatted;
  }
}
