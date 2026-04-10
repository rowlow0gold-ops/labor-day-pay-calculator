import 'package:flutter/material.dart';
import '../models/country_data.dart';
import 'storage_service.dart';

class AppState extends ChangeNotifier {
  final StorageService storage;

  late bool _isDark;
  late Locale _locale;
  late CountryCode _country;
  late double _taxRateHourly;
  late double _taxRateDaily;
  late double _insuranceRateHourly;
  late double _insuranceRateDaily;
  late double _incentiveHourly;
  late double _incentiveEffectHoursHourly;

  AppState({required this.storage}) {
    _isDark = storage.getDarkMode();
    _locale = Locale(storage.getLanguage());
    _country = CountryCode.kr;
    _taxRateHourly = storage.getTaxRateHourly();
    _taxRateDaily = storage.getTaxRateDaily();
    _insuranceRateHourly = storage.getInsuranceRateHourly();
    _insuranceRateDaily = storage.getInsuranceRateDaily();
    _incentiveHourly = storage.getIncentiveHourly();
    _incentiveEffectHoursHourly = storage.getIncentiveEffectHoursHourly();
    _autoDetect();
  }

  // Getters
  bool get isDark => _isDark;
  Locale get locale => _locale;
  CountryCode get country => _country;
  double get taxRateHourly => _taxRateHourly;
  double get taxRateDaily => _taxRateDaily;
  double get insuranceRateHourly => _insuranceRateHourly;
  double get insuranceRateDaily => _insuranceRateDaily;
  double get incentiveHourly => _incentiveHourly;
  double get incentiveEffectHoursHourly => _incentiveEffectHoursHourly;
  // Convenience: get rates by mode
  double taxRate(bool isLumpSum) => isLumpSum ? _taxRateDaily : _taxRateHourly;
  double insuranceRate(bool isLumpSum) => isLumpSum ? _insuranceRateDaily : _insuranceRateHourly;

  Future<void> _autoDetect() async {
    final lang = storage.getLanguage();
    if (lang == 'en') {
      final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final supported = ['en', 'ko'];
      if (supported.contains(deviceLocale.languageCode)) {
        await storage.setLanguage(deviceLocale.languageCode);
        _locale = Locale(deviceLocale.languageCode);
        notifyListeners();
      }
    }
  }

  void setDarkMode(bool dark) {
    _isDark = dark;
    storage.setDarkMode(dark);
    notifyListeners();
  }

  void setLocale(Locale locale) {
    _locale = locale;
    storage.setLanguage(locale.languageCode);
    notifyListeners();
  }

  void setCountry(CountryCode country) {
    _country = country;
    storage.setCountry(country);
    notifyListeners();
  }

  void setTaxRateHourly(double v) {
    _taxRateHourly = v;
    storage.setTaxRateHourly(v);
    notifyListeners();
  }

  void setTaxRateDaily(double v) {
    _taxRateDaily = v;
    storage.setTaxRateDaily(v);
    notifyListeners();
  }

  void setInsuranceRateHourly(double v) {
    _insuranceRateHourly = v;
    storage.setInsuranceRateHourly(v);
    notifyListeners();
  }

  void setInsuranceRateDaily(double v) {
    _insuranceRateDaily = v;
    storage.setInsuranceRateDaily(v);
    notifyListeners();
  }

  void setIncentiveHourly(double v) {
    _incentiveHourly = v;
    storage.setIncentiveHourly(v);
    notifyListeners();
  }

  void setIncentiveEffectHoursHourly(double v) {
    _incentiveEffectHoursHourly = v;
    storage.setIncentiveEffectHoursHourly(v);
    notifyListeners();
  }

  /// Call after rate changes to notify listeners (calendar, etc.)
  void refreshRates() {
    notifyListeners();
  }
}
