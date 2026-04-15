import 'package:flutter/material.dart';
import '../models/country_data.dart';
import 'holiday_service.dart';
import 'storage_service.dart';

class AppState extends ChangeNotifier {
  final StorageService storage;
  final HolidayService holidays;

  late bool _isDark;
  late Locale _locale;
  late CountryCode _country;
  late double _taxRateHourly;
  late double _taxRateDaily;
  late double _insuranceRateHourly;
  late double _insuranceRateDaily;
  late double _incentiveHourly;
  late double _incentiveEffectHoursHourly;
  late bool _encryptionEnabled;

  AppState({required this.storage, required this.holidays}) {
    _isDark = storage.getDarkMode();
    _locale = Locale(storage.getLanguage());
    _country = storage.getCountry();
    _taxRateHourly = storage.getTaxRateHourly();
    _taxRateDaily = storage.getTaxRateDaily();
    _insuranceRateHourly = storage.getInsuranceRateHourly();
    _insuranceRateDaily = storage.getInsuranceRateDaily();
    _incentiveHourly = storage.getIncentiveHourly();
    _incentiveEffectHoursHourly = storage.getIncentiveEffectHoursHourly();
    _encryptionEnabled = storage.isEncryptionEnabled();
    _autoDetect().then((_) => _refreshHolidayCache());
  }

  /// The ISO 3166-1 alpha-2 code used for holiday lookups. Normally this is
  /// the stored country's ISO (KR/JP/CA/AU/US), but when the device region
  /// reports something we don't have tax/currency rules for (e.g. 'DE',
  /// 'BR', 'GB'), [_autoDetect] overrides it so the calendar still shows
  /// the user's real public holidays via the Nager.Date API.
  String? _holidayIsoOverride;
  String get holidayIso =>
      _holidayIsoOverride ?? _country.name.toUpperCase();

  /// Kicks off background refresh for the current and next year so the cache
  /// always has fresh data ready for offline use. Skips countries whose
  /// holidays we already ship hardcoded.
  void _refreshHolidayCache() {
    final now = DateTime.now();
    holidays.refreshIfNeeded(holidayIso, now.year);
    holidays.refreshIfNeeded(holidayIso, now.year + 1);
  }

  bool get encryptionEnabled => _encryptionEnabled;

  Future<void> setEncryptionEnabled(bool v) async {
    _encryptionEnabled = v;
    await storage.setEncryptionEnabled(v);
    notifyListeners();
  }

  /// Call after storage unlock/lock state changes so AuthGate rebuilds.
  void storageUnlockedChanged() {
    notifyListeners();
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

  /// Best-effort country hint from the device timezone. No permission, no
  /// network, no GPS — the OS already exposes this and it's the strongest
  /// "where is the user physically" signal we can use without violating the
  /// privacy policy's "no location tracking" promise.
  ///
  /// Handles both IANA names ("Asia/Seoul") and short abbreviations ("KST")
  /// since Android/iOS platforms differ. Returns null if we can't map it to
  /// one of our 5 supported countries.
  String? _countryFromTimezone() {
    final name = DateTime.now().timeZoneName.toLowerCase();
    final offset = DateTime.now().timeZoneOffset;

    // IANA-style region names (Android typically exposes these)
    if (name.contains('seoul') || name.contains('korea')) return 'KR';
    if (name.contains('tokyo') || name.contains('japan')) return 'JP';
    if (name.contains('sydney') ||
        name.contains('melbourne') ||
        name.contains('brisbane') ||
        name.contains('perth') ||
        name.contains('adelaide') ||
        name.contains('hobart') ||
        name.contains('darwin') ||
        name.contains('/australia/')) return 'AU';
    if (name.contains('toronto') ||
        name.contains('vancouver') ||
        name.contains('montreal') ||
        name.contains('edmonton') ||
        name.contains('winnipeg') ||
        name.contains('halifax') ||
        name.contains('st_johns') ||
        name.contains('/canada/')) return 'CA';
    if (name.contains('new_york') ||
        name.contains('chicago') ||
        name.contains('denver') ||
        name.contains('los_angeles') ||
        name.contains('phoenix') ||
        name.contains('anchorage') ||
        name.contains('honolulu') ||
        name.contains('detroit') ||
        name.contains('/us/')) return 'US';

    // Short abbreviation fallback (iOS, older Android)
    const shortToCountry = {
      'kst': 'KR',
      'jst': 'JP',
      'aest': 'AU', 'aedt': 'AU', 'acst': 'AU', 'acdt': 'AU',
      'awst': 'AU', 'awdt': 'AU',
      'est': 'US', 'edt': 'US',
      'cst': 'US', 'cdt': 'US',
      'mst': 'US', 'mdt': 'US',
      'pst': 'US', 'pdt': 'US',
      'akst': 'US', 'akdt': 'US',
      'hst': 'US', 'hadt': 'US',
    };
    if (shortToCountry.containsKey(name)) return shortToCountry[name];

    // Last-resort: raw UTC offset. Ambiguous in some cases (UTC+9 matches
    // both KR and JP) — we lean towards KR because a Japanese user's device
    // almost always reports regionCode=JP, whereas Korean users often have
    // English-US language set which masks the region.
    final hours = offset.inMinutes ~/ 60;
    switch (hours) {
      case 9:
        return 'KR';
      case 10:
      case 11:
        return 'AU';
    }
    return null;
  }

  /// Detect country from the **device's regional setting** on every launch
  /// so each user automatically sees their own country's holidays, currency
  /// and tax rules without having to pick anything.
  ///
  /// Detection priority:
  ///   1. Device timezone (strongest "where am I now" signal, privacy-safe)
  ///   2. Device region code from locale (fallback)
  ///
  /// Language is only auto-picked once (on first launch while still on 'en')
  /// so we don't override a user's explicit language choice in settings.
  Future<void> _autoDetect() async {
    // Scan ALL device locales (not just the primary one) — Android sometimes
    // exposes language in locale[0] and region only in later entries, and some
    // simulators omit the region from the primary locale entirely.
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final primary = dispatcher.locale;
    final langCode = primary.languageCode.toLowerCase();

    String regionCode = (primary.countryCode ?? '').toUpperCase();
    if (regionCode.isEmpty) {
      for (final loc in dispatcher.locales) {
        final c = (loc.countryCode ?? '').toUpperCase();
        if (c.isNotEmpty) {
          regionCode = c;
          break;
        }
      }
    }

    // Timezone is the strongest physical-location signal we have without GPS.
    // A Korean user with phone set to English-US will still have
    // tz=Asia/Seoul, so this catches the case that locale-only detection
    // misses.
    final tzCountry = _countryFromTimezone();

    // Diagnostic: helps confirm what the OS is actually reporting when a user
    // says "holidays show the wrong country". Safe to leave in release builds.
    // ignore: avoid_print
    print('[autoDetect] primary=${primary.toLanguageTag()} '
        'langCode=$langCode regionCode=$regionCode '
        'tzName=${DateTime.now().timeZoneName} '
        'tzOffset=${DateTime.now().timeZoneOffset.inHours}h '
        'tzCountry=$tzCountry '
        'allLocales=${dispatcher.locales.map((l) => l.toLanguageTag()).toList()}');

    // ── Country selection: timezone first, then device region ──
    // Priority: timezone (where the user physically is right now) beats
    // locale region (which often reflects Apple/Google account region, not
    // current location). Falls back to locale only if timezone couldn't map
    // to one of our 5 supported countries.
    //
    // If neither timezone nor locale is one of our 5 supported countries
    // (KR/JP/CA/AU/US), leave the stored country untouched — we don't have
    // tax or currency rules for, say, Germany — but remember the real region
    // ISO so holiday lookups still return the user's actual public holidays
    // (via Nager.Date API + local cache).
    final effectiveRegion = tzCountry ?? regionCode;
    CountryCode? pickedCountry;
    switch (effectiveRegion) {
      case 'KR':
        pickedCountry = CountryCode.kr;
        _holidayIsoOverride = null;
        break;
      case 'JP':
        pickedCountry = CountryCode.jp;
        _holidayIsoOverride = null;
        break;
      case 'CA':
        pickedCountry = CountryCode.ca;
        _holidayIsoOverride = null;
        break;
      case 'AU':
        pickedCountry = CountryCode.au;
        _holidayIsoOverride = null;
        break;
      case 'US':
        pickedCountry = CountryCode.us;
        _holidayIsoOverride = null;
        break;
      default:
        // Unsupported region (DE, BR, GB, …) — keep the stored country
        // for tax/currency purposes but fetch holidays for the real region.
        // Prefer the locale region ISO here because that's what Nager.Date
        // expects; timezone strings like "CET" don't map cleanly.
        final override = regionCode.isNotEmpty ? regionCode : effectiveRegion;
        if (override.isNotEmpty && override.length == 2) {
          _holidayIsoOverride = override;
        }
    }

    // ── Language: only set on first launch (while still default 'en') ──
    final currentLang = storage.getLanguage();
    var changed = false;
    if (currentLang == 'en') {
      const supportedLangs = ['en', 'ko', 'ja'];
      final pickedLang = supportedLangs.contains(langCode) ? langCode : 'en';
      if (pickedLang != currentLang) {
        await storage.setLanguage(pickedLang);
        _locale = Locale(pickedLang);
        changed = true;
      }
    }

    if (pickedCountry != null && pickedCountry != _country) {
      await storage.setCountry(pickedCountry);
      _country = pickedCountry;
      changed = true;
    }
    // ignore: avoid_print
    print('[autoDetect] pickedCountry=${pickedCountry?.name ?? "(none)"} '
        'storedCountry=${_country.name} '
        'holidayIso=$holidayIso changed=$changed');
    if (changed) notifyListeners();
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
    _refreshHolidayCache();
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
