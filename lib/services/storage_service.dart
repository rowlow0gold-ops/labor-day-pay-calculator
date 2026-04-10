import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/country_data.dart';

class StorageService {
  static const _keyCountry = 'country';
  static const _keyLanguage = 'language';
  static const _keyHourlyRate = 'hourly_rate';
  static const _keyTaxRateHourly = 'tax_rate_hourly';
  static const _keyTaxRateDaily = 'tax_rate_daily';
  static const _keyInsuranceRateHourly = 'insurance_rate_hourly';
  static const _keyInsuranceRateDaily = 'insurance_rate_daily';
  static const _keyDefaultWorkplaceHourly = 'default_workplace_hourly';
  static const _keyDefaultWorkplaceDaily = 'default_workplace_daily';
  static const _keyDarkMode = 'dark_mode';
  static const _keyDefaultHours = 'default_hours';
  static const _keyDefaultLumpSum = 'default_lump_sum';
  static const _keyDefaultPayment = 'default_payment';
  static const _keyIncentiveHourly = 'incentive_hourly';
  static const _keyIncentiveEffectHoursHourly = 'incentive_effect_hours_hourly';
  static const _keyWorkEntries = 'work_entries';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Country
  CountryCode getCountry() {
    final code = _prefs.getString(_keyCountry) ?? 'kr';
    return CountryCode.values.firstWhere(
      (c) => c.name == code,
      orElse: () => CountryCode.kr,
    );
  }

  Future<void> setCountry(CountryCode country) async {
    await _prefs.setString(_keyCountry, country.name);
  }

  // Language
  String getLanguage() => _prefs.getString(_keyLanguage) ?? 'en';
  Future<void> setLanguage(String lang) async {
    await _prefs.setString(_keyLanguage, lang);
  }

  // Rates

  double getHourlyRate(CountryCode country) {
    return _prefs.getDouble('${_keyHourlyRate}_${country.name}') ??
        countryConfigs[country]!.defaultHourlyRate;
  }

  Future<void> setHourlyRate(CountryCode country, double rate) async {
    await _prefs.setDouble('${_keyHourlyRate}_${country.name}', rate);
  }

  // Tax rate % (per mode)
  double getTaxRateHourly() => _prefs.getDouble(_keyTaxRateHourly) ?? 3.3;
  Future<void> setTaxRateHourly(double v) async => _prefs.setDouble(_keyTaxRateHourly, v);
  double getTaxRateDaily() => _prefs.getDouble(_keyTaxRateDaily) ?? 0;
  Future<void> setTaxRateDaily(double v) async => _prefs.setDouble(_keyTaxRateDaily, v);

  // Insurance rate % (per mode)
  double getInsuranceRateHourly() => _prefs.getDouble(_keyInsuranceRateHourly) ?? 0;
  Future<void> setInsuranceRateHourly(double v) async => _prefs.setDouble(_keyInsuranceRateHourly, v);
  double getInsuranceRateDaily() => _prefs.getDouble(_keyInsuranceRateDaily) ?? 9.4;
  Future<void> setInsuranceRateDaily(double v) async => _prefs.setDouble(_keyInsuranceRateDaily, v);

  // Default hours
  double getDefaultHours() => _prefs.getDouble(_keyDefaultHours) ?? 8.0;
  Future<void> setDefaultHours(double hours) async {
    await _prefs.setDouble(_keyDefaultHours, hours);
  }

  // Default workplace alias (per mode)
  String getDefaultWorkplaceHourly() => _prefs.getString(_keyDefaultWorkplaceHourly) ?? '';
  Future<void> setDefaultWorkplaceHourly(String v) async => _prefs.setString(_keyDefaultWorkplaceHourly, v);
  String getDefaultWorkplaceDaily() => _prefs.getString(_keyDefaultWorkplaceDaily) ?? '';
  Future<void> setDefaultWorkplaceDaily(String v) async => _prefs.setString(_keyDefaultWorkplaceDaily, v);

  // Default lump sum mode (단건/단가)
  bool getDefaultLumpSum() => _prefs.getBool(_keyDefaultLumpSum) ?? false;
  Future<void> setDefaultLumpSum(bool lumpSum) async {
    await _prefs.setBool(_keyDefaultLumpSum, lumpSum);
  }

  // Default payment (단건 mode)
  double getDefaultPayment() => _prefs.getDouble(_keyDefaultPayment) ?? 150000;
  Future<void> setDefaultPayment(double amount) async {
    await _prefs.setDouble(_keyDefaultPayment, amount);
  }

  // Default incentive % (hourly mode only) — percentage added on top of the rate
  double getIncentiveHourly() => _prefs.getDouble(_keyIncentiveHourly) ?? 0;
  Future<void> setIncentiveHourly(double v) async {
    await _prefs.setDouble(_keyIncentiveHourly, v);
  }
  // How many hours the incentive percentage applies to (hourly mode only)
  double getIncentiveEffectHoursHourly() => _prefs.getDouble(_keyIncentiveEffectHoursHourly) ?? 0;
  Future<void> setIncentiveEffectHoursHourly(double v) async {
    await _prefs.setDouble(_keyIncentiveEffectHoursHourly, v);
  }

  // Theme
  bool getDarkMode() => _prefs.getBool(_keyDarkMode) ?? false;
  Future<void> setDarkMode(bool dark) async {
    await _prefs.setBool(_keyDarkMode, dark);
  }

  // Work entries — stored per month as JSON
  List<WorkEntry> getWorkEntries(int year, int month) {
    final key = '${_keyWorkEntries}_${year}_$month';
    final json = _prefs.getString(key);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => WorkEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setWorkEntries(int year, int month, List<WorkEntry> entries) async {
    final key = '${_keyWorkEntries}_${year}_$month';
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _prefs.setString(key, json);
  }

  /// Get all work entries for a given year (for yearly summary)
  List<WorkEntry> getYearEntries(int year) {
    final all = <WorkEntry>[];
    for (int m = 1; m <= 12; m++) {
      all.addAll(getWorkEntries(year, m));
    }
    return all;
  }

  /// Remove every work entry stored for the given year (all 12 months).
  Future<void> clearYear(int year) async {
    for (int m = 1; m <= 12; m++) {
      final key = '${_keyWorkEntries}_${year}_$m';
      await _prefs.remove(key);
    }
  }

  /// Remove every work entry for every year/month.
  Future<void> clearAllWorkEntries() async {
    final keys = _prefs.getKeys()
        .where((k) => k.startsWith('${_keyWorkEntries}_'))
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
