import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/country_data.dart';
import 'encryption_service.dart';

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
  static const _keyDefaultLumpSumHours = 'default_lump_sum_hours';
  static const _keyIncentiveHourly = 'incentive_hourly';
  static const _keyIncentiveEffectHoursHourly = 'incentive_effect_hours_hourly';
  static const _keyDefaultMemoDaily = 'default_memo_daily';
  static const _keyDefaultMemoHourly = 'default_memo_hourly';
  static const _keyWorkEntries = 'work_entries';
  // Encryption feature flag — when true, work entry JSON is encrypted-at-rest.
  static const _keyEncryptionEnabled = 'encryption_enabled';
  // Envelope marker prepended to encrypted JSON so we can detect on read.
  static const _encMarker = 'ENC1:';

  /// Injected on init — null when encryption feature is disabled.
  EncryptionService? _encryption;

  void attachEncryption(EncryptionService service) {
    _encryption = service;
  }

  /// Fires after any synced mutation so [SyncService] can debounce an upload.
  /// Registered via [attachMutationListener]. Null = no sync attached.
  void Function()? _onMutated;
  void attachMutationListener(void Function() cb) {
    _onMutated = cb;
  }
  bool _suppressMutation = false;
  void _notifyMutation() {
    if (_suppressMutation) return;
    try {
      _onMutated?.call();
    } catch (_) {
      // Never let a sync hook break a local write.
    }
  }

  bool isEncryptionEnabled() => _prefs.getBool(_keyEncryptionEnabled) ?? false;
  Future<void> setEncryptionEnabled(bool v) async =>
      _prefs.setBool(_keyEncryptionEnabled, v);

  late SharedPreferences _prefs;
  // When encryption is unlocked, we eagerly decrypt every month's entries into
  // this cache so that the existing sync getters don't have to await.
  // Key format matches `_entryKey(year, month)`.
  final Map<String, List<WorkEntry>> _decryptedCache = {};
  bool _unlocked = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get isUnlocked => _unlocked;

  String _entryKey(int year, int month) => '${_keyWorkEntries}_${year}_$month';

  /// Called after login: iterate every stored month, decrypt into the cache so
  /// the sync `getWorkEntries` can serve from memory. Must be called before
  /// any read when encryption is enabled.
  Future<void> unlockAndLoad() async {
    if (_encryption == null) {
      throw StateError('StorageService.unlockAndLoad: EncryptionService not attached');
    }
    _decryptedCache.clear();
    final keys = _prefs.getKeys().where((k) => k.startsWith('${_keyWorkEntries}_'));
    for (final key in keys) {
      final raw = _prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final plain = raw.startsWith(_encMarker)
            ? await _encryption!.decryptString(raw.substring(_encMarker.length))
            : raw;
        final list = (jsonDecode(plain) as List)
            .map((e) => WorkEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        _decryptedCache[key] = list;
      } catch (_) {
        // Corrupt/unreadable — skip (don't crash the app).
      }
    }
    _unlocked = true;
  }

  /// Lock: wipe the decrypted cache from memory (on sign-out).
  void lock() {
    _decryptedCache.clear();
    _unlocked = false;
  }

  /// On login: back up current (anonymous) entries to a local prefix
  /// so they can be restored on logout. Don't remove them from main keys —
  /// cloud sync will handle merging.
  Future<void> swapToUser(String uid) async {
    final entryKeys = _prefs.getKeys()
        .where((k) => k.startsWith('${_keyWorkEntries}_') && !k.startsWith('${_keyWorkEntries}_user_') && !k.startsWith('${_keyWorkEntries}_local_'))
        .toList();
    // Back up local entries (copy only, don't remove)
    for (final key in entryKeys) {
      final raw = _prefs.getString(key);
      if (raw != null && raw.isNotEmpty && !raw.startsWith(_encMarker)) {
        await _prefs.setString(key.replaceFirst(_keyWorkEntries, '${_keyWorkEntries}_local'), raw);
      }
    }
  }

  /// On logout: save current (user) entries to a user-specific prefix,
  /// then restore the anonymous local entries.
  Future<void> swapToLocal(String uid) async {
    final entryKeys = _prefs.getKeys()
        .where((k) => k.startsWith('${_keyWorkEntries}_') && !k.startsWith('${_keyWorkEntries}_user_') && !k.startsWith('${_keyWorkEntries}_local_'))
        .toList();
    // Back up user entries
    for (final key in entryKeys) {
      final raw = _prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        await _prefs.setString(key.replaceFirst(_keyWorkEntries, '${_keyWorkEntries}_user_$uid'), raw);
      }
      await _prefs.remove(key);
    }
    // Restore local entries (skip encrypted ones — they can't be read without a key)
    final localKeys = _prefs.getKeys()
        .where((k) => k.startsWith('${_keyWorkEntries}_local_'))
        .toList();
    for (final key in localKeys) {
      final raw = _prefs.getString(key);
      if (raw != null && raw.isNotEmpty && !raw.startsWith(_encMarker)) {
        final mainKey = key.replaceFirst('${_keyWorkEntries}_local', _keyWorkEntries);
        await _prefs.setString(mainKey, raw);
      }
      await _prefs.remove(key);
    }
  }

  /// One-time migration: encrypt every existing plaintext month blob.
  /// Call this exactly once right after the user enables encryption.
  Future<void> migrateToEncrypted() async {
    if (_encryption == null) {
      throw StateError('StorageService.migrateToEncrypted: EncryptionService not attached');
    }
    final keys = _prefs.getKeys()
        .where((k) => k.startsWith('${_keyWorkEntries}_'))
        .toList();
    for (final key in keys) {
      final raw = _prefs.getString(key);
      if (raw == null || raw.isEmpty || raw.startsWith(_encMarker)) continue;
      final envelope = await _encryption!.encryptString(raw);
      await _prefs.setString(key, '$_encMarker$envelope');
    }
    await unlockAndLoad();
  }

  /// One-time reverse migration: decrypt everything back to plaintext when the
  /// user disables encryption.
  Future<void> migrateToPlaintext() async {
    if (_encryption == null) return;
    final keys = _prefs.getKeys()
        .where((k) => k.startsWith('${_keyWorkEntries}_'))
        .toList();
    for (final key in keys) {
      final raw = _prefs.getString(key);
      if (raw == null || raw.isEmpty || !raw.startsWith(_encMarker)) continue;
      final plain = await _encryption!.decryptString(raw.substring(_encMarker.length));
      await _prefs.setString(key, plain);
    }
    _decryptedCache.clear();
    _unlocked = false;
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
    _notifyMutation();
  }

  // Language
  String getLanguage() => _prefs.getString(_keyLanguage) ?? 'en';
  Future<void> setLanguage(String lang) async {
    await _prefs.setString(_keyLanguage, lang);
    _notifyMutation();
  }

  // Rates

  double getHourlyRate(CountryCode country) {
    return _prefs.getDouble('${_keyHourlyRate}_${country.name}') ??
        countryConfigs[country]!.defaultHourlyRate;
  }

  Future<void> setHourlyRate(CountryCode country, double rate) async {
    await _prefs.setDouble('${_keyHourlyRate}_${country.name}', rate);
    _notifyMutation();
  }

  // Tax rate % (per mode)
  double getTaxRateHourly() => _prefs.getDouble(_keyTaxRateHourly) ?? 0;
  Future<void> setTaxRateHourly(double v) async {
    await _prefs.setDouble(_keyTaxRateHourly, v);
    _notifyMutation();
  }
  double getTaxRateDaily() => _prefs.getDouble(_keyTaxRateDaily) ?? 0;
  Future<void> setTaxRateDaily(double v) async {
    await _prefs.setDouble(_keyTaxRateDaily, v);
    _notifyMutation();
  }

  // Insurance rate % (per mode)
  double getInsuranceRateHourly() => _prefs.getDouble(_keyInsuranceRateHourly) ?? 0;
  Future<void> setInsuranceRateHourly(double v) async {
    await _prefs.setDouble(_keyInsuranceRateHourly, v);
    _notifyMutation();
  }
  double getInsuranceRateDaily() => _prefs.getDouble(_keyInsuranceRateDaily) ?? 0;
  Future<void> setInsuranceRateDaily(double v) async {
    await _prefs.setDouble(_keyInsuranceRateDaily, v);
    _notifyMutation();
  }

  // Default hours
  double getDefaultHours() => _prefs.getDouble(_keyDefaultHours) ?? 8.0;
  Future<void> setDefaultHours(double hours) async {
    await _prefs.setDouble(_keyDefaultHours, hours);
    _notifyMutation();
  }

  // Default workplace alias (per mode)
  String getDefaultWorkplaceHourly() => _prefs.getString(_keyDefaultWorkplaceHourly) ?? '';
  Future<void> setDefaultWorkplaceHourly(String v) async {
    await _prefs.setString(_keyDefaultWorkplaceHourly, v);
    _notifyMutation();
  }
  String getDefaultWorkplaceDaily() => _prefs.getString(_keyDefaultWorkplaceDaily) ?? '';
  Future<void> setDefaultWorkplaceDaily(String v) async {
    await _prefs.setString(_keyDefaultWorkplaceDaily, v);
    _notifyMutation();
  }

  // Default lump sum mode (단건/단가)
  bool getDefaultLumpSum() => _prefs.getBool(_keyDefaultLumpSum) ?? false;
  Future<void> setDefaultLumpSum(bool lumpSum) async {
    await _prefs.setBool(_keyDefaultLumpSum, lumpSum);
    _notifyMutation();
  }

  // Default payment (단건 mode)
  double getDefaultPayment() => _prefs.getDouble(_keyDefaultPayment) ?? 150000;
  Future<void> setDefaultPayment(double amount) async {
    await _prefs.setDouble(_keyDefaultPayment, amount);
    _notifyMutation();
  }

  // Default optional hours for a lump sum entry. Zero = no hours; the calendar
  // cell falls back to the money icon. Non-zero = show "Xh" like an hourly
  // entry so users can still track time for fixed-fee jobs.
  double getDefaultLumpSumHours() => _prefs.getDouble(_keyDefaultLumpSumHours) ?? 0;
  Future<void> setDefaultLumpSumHours(double hours) async {
    await _prefs.setDouble(_keyDefaultLumpSumHours, hours);
    _notifyMutation();
  }

  // Default memo (일시금 mode only) — pre-filled when creating a new lump sum entry
  String getDefaultMemoDaily() => _prefs.getString(_keyDefaultMemoDaily) ?? '';
  Future<void> setDefaultMemoDaily(String v) async {
    await _prefs.setString(_keyDefaultMemoDaily, v);
    _notifyMutation();
  }

  String getDefaultMemoHourly() => _prefs.getString(_keyDefaultMemoHourly) ?? '';
  Future<void> setDefaultMemoHourly(String v) async {
    await _prefs.setString(_keyDefaultMemoHourly, v);
    _notifyMutation();
  }

  // Default incentive % (hourly mode only) — percentage added on top of the rate
  double getIncentiveHourly() => _prefs.getDouble(_keyIncentiveHourly) ?? 0;
  Future<void> setIncentiveHourly(double v) async {
    await _prefs.setDouble(_keyIncentiveHourly, v);
    _notifyMutation();
  }
  // How many hours the incentive percentage applies to (hourly mode only)
  double getIncentiveEffectHoursHourly() => _prefs.getDouble(_keyIncentiveEffectHoursHourly) ?? 0;
  Future<void> setIncentiveEffectHoursHourly(double v) async {
    await _prefs.setDouble(_keyIncentiveEffectHoursHourly, v);
    _notifyMutation();
  }

  // Theme
  bool getDarkMode() => _prefs.getBool(_keyDarkMode) ?? false;
  Future<void> setDarkMode(bool dark) async {
    await _prefs.setBool(_keyDarkMode, dark);
    _notifyMutation();
  }

  // Work entries — stored per month as JSON (optionally encrypted)
  List<WorkEntry> getWorkEntries(int year, int month) {
    final key = _entryKey(year, month);
    if (isEncryptionEnabled()) {
      // Serve from decrypted cache. If the cache hasn't been loaded yet
      // (e.g. called before unlockAndLoad), return empty rather than crash.
      return List<WorkEntry>.from(_decryptedCache[key] ?? const <WorkEntry>[]);
    }
    final json = _prefs.getString(key);
    if (json == null || json.isEmpty || json.startsWith(_encMarker)) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => WorkEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setWorkEntries(int year, int month, List<WorkEntry> entries) async {
    final key = _entryKey(year, month);
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    if (isEncryptionEnabled() && _encryption != null) {
      _decryptedCache[key] = List<WorkEntry>.from(entries);
      final envelope = await _encryption!.encryptString(json);
      await _prefs.setString(key, '$_encMarker$envelope');
    } else {
      await _prefs.setString(key, json);
    }
    _notifyMutation();
  }

  /// Get all work entries for a given year (for yearly summary)
  List<WorkEntry> getYearEntries(int year) {
    final all = <WorkEntry>[];
    for (int m = 1; m <= 12; m++) {
      all.addAll(getWorkEntries(year, m));
    }
    return all;
  }

  /// List every year that has at least one stored work entry, sorted ascending.
  List<int> getYearsWithEntries() {
    final years = <int>{};
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith('${_keyWorkEntries}_')) continue;
      // key format: work_entries_<year>_<month>
      final parts = key.substring('${_keyWorkEntries}_'.length).split('_');
      if (parts.length != 2) continue;
      final year = int.tryParse(parts[0]);
      if (year == null) continue;
      final raw = _prefs.getString(key);
      if (raw == null || raw.isEmpty || raw == '[]') continue;
      years.add(year);
    }
    final sorted = years.toList()..sort();
    return sorted;
  }

  /// Remove every work entry stored for the given year (all 12 months).
  Future<void> clearYear(int year) async {
    for (int m = 1; m <= 12; m++) {
      final key = _entryKey(year, m);
      await _prefs.remove(key);
      _decryptedCache.remove(key);
    }
    _notifyMutation();
  }

  /// Remove every work entry for every year/month.
  Future<void> clearAllWorkEntries() async {
    final keys = _prefs.getKeys()
        .where((k) =>
            k.startsWith('${_keyWorkEntries}_') &&
            !k.startsWith('${_keyWorkEntries}_user_') &&
            !k.startsWith('${_keyWorkEntries}_local_'))
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
    _decryptedCache.clear();
    _notifyMutation();
  }

  // ── Snapshot (for cloud sync) ─────────────────────────────────────────
  //
  // Format:
  //   {
  //     "v": 1,
  //     "prefs": { "<key>": <value>, ... },            // all settings + per-country rates
  //     "entries": { "<year>_<month>": [WorkEntry...], ... }  // all work entries (plaintext)
  //   }
  //
  // The entries map is always plaintext — we decrypt locally before uploading
  // and re-encrypt locally after downloading. Firestore never stores ciphertext.

  // Every pref key we sync. Keep in sync with the constants above.
  // NOTE: hourly rate is stored per-country as 'hourly_rate_<country>', so it
  // can't be enumerated statically — we detect it below by prefix.
  static const List<String> _syncedScalarKeys = [
    _keyCountry,
    _keyLanguage,
    _keyDarkMode,
    _keyTaxRateHourly,
    _keyTaxRateDaily,
    _keyInsuranceRateHourly,
    _keyInsuranceRateDaily,
    _keyDefaultWorkplaceHourly,
    _keyDefaultWorkplaceDaily,
    _keyDefaultHours,
    _keyDefaultLumpSum,
    _keyDefaultPayment,
    _keyDefaultLumpSumHours,
    _keyIncentiveHourly,
    _keyIncentiveEffectHoursHourly,
    _keyDefaultMemoDaily,
    _keyDefaultMemoHourly,
    // Intentionally NOT synced:
    //   _keyEncryptionEnabled — this is a per-device flag
  ];

  bool _isSyncedKey(String key) {
    if (_syncedScalarKeys.contains(key)) return true;
    if (key.startsWith('${_keyHourlyRate}_')) return true;
    return false;
  }

  /// Build a plaintext snapshot of every synced preference + work entry.
  /// Safe to call regardless of encryption state — entries are always returned
  /// in plaintext. When encryption is on we source entries from the decrypted
  /// cache; when it's off we parse the raw JSON.
  Future<Map<String, dynamic>> exportSnapshot() async {
    final prefs = <String, dynamic>{};
    for (final key in _prefs.getKeys()) {
      if (!_isSyncedKey(key)) continue;
      final v = _prefs.get(key);
      if (v == null) continue;
      prefs[key] = v;
    }

    final entries = <String, dynamic>{};
    final entryKeys = _prefs.getKeys().where((k) =>
        k.startsWith('${_keyWorkEntries}_') &&
        !k.startsWith('${_keyWorkEntries}_user_') &&
        !k.startsWith('${_keyWorkEntries}_local_'));
    for (final key in entryKeys) {
      List<WorkEntry> list;
      if (isEncryptionEnabled()) {
        list = _decryptedCache[key] ?? const [];
        // If cache not populated yet and encryption is on, try decrypt-on-read.
        if (list.isEmpty && _encryption != null) {
          final raw = _prefs.getString(key);
          if (raw != null && raw.isNotEmpty) {
            try {
              final plain = raw.startsWith(_encMarker)
                  ? await _encryption!.decryptString(raw.substring(_encMarker.length))
                  : raw;
              list = (jsonDecode(plain) as List)
                  .map((e) => WorkEntry.fromJson(e as Map<String, dynamic>))
                  .toList();
            } catch (_) {
              list = const [];
            }
          }
        }
      } else {
        final raw = _prefs.getString(key);
        if (raw == null || raw.isEmpty || raw.startsWith(_encMarker)) {
          list = const [];
        } else {
          try {
            list = (jsonDecode(raw) as List)
                .map((e) => WorkEntry.fromJson(e as Map<String, dynamic>))
                .toList();
          } catch (_) {
            list = const [];
          }
        }
      }
      // Strip leading prefix so the map key is just "<year>_<month>".
      final shortKey = key.substring('${_keyWorkEntries}_'.length);
      entries[shortKey] = list.map((e) => e.toJson()).toList();
    }

    return {
      'v': 1,
      'prefs': prefs,
      'entries': entries,
    };
  }

  /// Replace local state with the given snapshot. Overwrites all synced
  /// preferences and all work entries. Re-encrypts entries if encryption is on.
  ///
  /// Suppresses the mutation listener during the import so SyncService won't
  /// immediately schedule a re-upload of what it just downloaded.
  Future<void> importSnapshot(Map<String, dynamic> snapshot) async {
    _suppressMutation = true;
    try {
      await _importSnapshotInner(snapshot);
    } finally {
      _suppressMutation = false;
    }
  }

  Future<void> _importSnapshotInner(Map<String, dynamic> snapshot) async {
    final prefs = (snapshot['prefs'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = (snapshot['entries'] as Map?)?.cast<String, dynamic>() ?? {};

    // Wipe old synced prefs to avoid stale keys.
    for (final key in _prefs.getKeys().toList()) {
      if (_isSyncedKey(key)) {
        await _prefs.remove(key);
      }
    }
    for (final e in prefs.entries) {
      final v = e.value;
      if (v is bool) {
        await _prefs.setBool(e.key, v);
      } else if (v is int) {
        // SharedPreferences distinguishes int/double. Doubles serialize as
        // num in JSON so they may arrive as int when integral. Probe first.
        if (e.key == _keyDefaultHours ||
            e.key.startsWith('${_keyHourlyRate}_') ||
            e.key == _keyTaxRateHourly ||
            e.key == _keyTaxRateDaily ||
            e.key == _keyInsuranceRateHourly ||
            e.key == _keyInsuranceRateDaily ||
            e.key == _keyDefaultPayment ||
            e.key == _keyDefaultLumpSumHours ||
            e.key == _keyIncentiveHourly ||
            e.key == _keyIncentiveEffectHoursHourly) {
          await _prefs.setDouble(e.key, v.toDouble());
        } else {
          await _prefs.setInt(e.key, v);
        }
      } else if (v is double) {
        await _prefs.setDouble(e.key, v);
      } else if (v is String) {
        await _prefs.setString(e.key, v);
      }
    }

    // Wipe old entries and rewrite from snapshot.
    await clearAllWorkEntries();
    for (final e in entries.entries) {
      final shortKey = e.key; // "<year>_<month>"
      final parts = shortKey.split('_');
      if (parts.length != 2) continue;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year == null || month == null) continue;
      final list = (e.value as List)
          .map((m) => WorkEntry.fromJson((m as Map).cast<String, dynamic>()))
          .toList();
      await setWorkEntries(year, month, list);
    }
  }

  /// Computes a stable hash of the snapshot (excluding volatile fields) so we
  /// can cheaply detect when local state differs from cloud state.
  String snapshotFingerprint(Map<String, dynamic> snapshot) {
    // Normalize by sorting keys so equal snapshots produce equal fingerprints.
    String stringify(dynamic v) {
      if (v is Map) {
        final keys = v.keys.map((k) => k.toString()).toList()..sort();
        final parts = keys.map((k) => '"$k":${stringify(v[k])}');
        return '{${parts.join(',')}}';
      }
      if (v is List) {
        return '[${v.map(stringify).join(',')}]';
      }
      return jsonEncode(v);
    }
    return stringify(snapshot);
  }
}
