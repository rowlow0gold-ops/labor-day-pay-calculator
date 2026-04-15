import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/country_data.dart';

/// Resolves public holidays for a given (ISO country code, year) using a
/// 3-tier strategy:
///   1. Hardcoded list shipped with the app (KR / JP / US / AU / CA, 2025-2026).
///   2. Local cache populated from previous successful API fetches.
///   3. Live fetch from Nager.Date (https://date.nager.at) on demand.
///
/// Tiers 1 & 2 are synchronous and offline-safe so the calendar can render
/// without any network or async UI gymnastics. Tier 3 runs in the background
/// once per (iso, year) per app launch and re-saves the cache so the next
/// render gets fresh data even when the user is offline.
///
/// The public API is keyed by ISO 3166-1 alpha-2 country codes (e.g. 'KR',
/// 'DE', 'BR') rather than our [CountryCode] enum, so any country Nager.Date
/// supports works — not just the 5 we ship tax rules for.
class HolidayService {
  final SharedPreferences _prefs;
  HolidayService(this._prefs);

  static const _cachePrefix = 'holidays_cache_';
  static const _refreshLog = 'holidays_refreshed_'; // last refresh timestamp

  // Track in-flight refreshes so we never fire two requests for the same
  // (iso, year) in a single session.
  final Set<String> _inFlight = {};

  /// Synchronous lookup. Returns hardcoded data first, then cached data,
  /// then an empty list. Always safe to call from build() / sync code.
  List<Holiday> getHolidays(String iso, int year) {
    final upper = iso.toUpperCase();
    final hardcoded = _getHardcoded(upper, year);
    if (hardcoded.isNotEmpty) return hardcoded;
    return _getCached(upper, year);
  }

  /// Background fetch + cache. Idempotent within a session.
  /// Skips ISOs we already have hardcoded data for.
  Future<bool> refreshIfNeeded(String iso, int year) async {
    final upper = iso.toUpperCase();
    if (upper.isEmpty) return false;
    final hardcoded = _getHardcoded(upper, year);
    if (hardcoded.isNotEmpty) return false; // hardcoded wins, no fetch needed.

    final key = '${upper}_$year';
    if (_inFlight.contains(key)) return false;

    // Throttle: don't refetch an iso/year more than once per 30 days.
    final lastTs = _prefs.getInt('$_refreshLog$key') ?? 0;
    final ageDays = (DateTime.now().millisecondsSinceEpoch - lastTs) / 86400000;
    if (lastTs > 0 && ageDays < 30 && _getCached(upper, year).isNotEmpty) {
      return false;
    }

    _inFlight.add(key);
    try {
      final url = Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/$upper');
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return false;

      final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
      final holidays = data
          .map((j) {
            final date = DateTime.parse(j['date'] as String);
            // Prefer localized name when available, else fall back to English.
            final name = (j['localName'] as String?) ?? (j['name'] as String? ?? '');
            return Holiday(date, name);
          })
          .toList();

      await _saveCached(upper, year, holidays);
      await _prefs.setInt(
        '$_refreshLog$key',
        DateTime.now().millisecondsSinceEpoch,
      );
      return true;
    } catch (_) {
      // Silent failure — sync getHolidays() will still return cached or
      // hardcoded data so the calendar keeps working offline.
      return false;
    } finally {
      _inFlight.remove(key);
    }
  }

  // ─────────────────────── internal helpers ───────────────────────

  /// Map an ISO code to our hardcoded [CountryCode], or null if unsupported.
  CountryCode? _isoToCountry(String iso) {
    switch (iso) {
      case 'KR':
        return CountryCode.kr;
      case 'JP':
        return CountryCode.jp;
      case 'CA':
        return CountryCode.ca;
      case 'AU':
        return CountryCode.au;
      case 'US':
        return CountryCode.us;
      default:
        return null;
    }
  }

  List<Holiday> _getHardcoded(String iso, int year) {
    final country = _isoToCountry(iso);
    if (country == null) return const [];
    final cfg = countryConfigs[country];
    if (cfg == null) return const [];
    if (year == 2025) return cfg.holidays2025;
    if (year == 2026) return cfg.holidays2026;
    return const [];
  }

  List<Holiday> _getCached(String iso, int year) {
    final key = '$_cachePrefix${iso}_$year';
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final List<dynamic> data = jsonDecode(raw) as List<dynamic>;
      return data
          .map((j) => Holiday(
                DateTime.parse(j['date'] as String),
                j['name'] as String,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCached(
    String iso,
    int year,
    List<Holiday> holidays,
  ) async {
    final key = '$_cachePrefix${iso}_$year';
    final json = jsonEncode(holidays
        .map((h) => {
              'date': h.date.toIso8601String(),
              'name': h.nameKey,
            })
        .toList());
    await _prefs.setString(key, json);
  }

  /// Wipe every cached holiday list. Used when the user wipes app data.
  Future<void> clearAllCache() async {
    final keys = _prefs.getKeys()
        .where((k) => k.startsWith(_cachePrefix) || k.startsWith(_refreshLog))
        .toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }
}
