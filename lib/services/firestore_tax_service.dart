import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/country_data.dart';

/// Fetches tax rate data from Firestore with local fallback.
/// Firestore structure:
///   tax_rates/{countryCode} → { insurance, brackets, minimumWage, overtime, lastUpdated }
///
/// The app loads from Firestore on startup and caches locally.
/// If offline, falls back to hardcoded defaults in country_data.dart.
class FirestoreTaxService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Cached data from Firestore (overrides local defaults)
  final Map<CountryCode, InsuranceRates> _insuranceOverrides = {};
  final Map<CountryCode, List<TaxBracket>> _bracketOverrides = {};
  final Map<CountryCode, MinimumWage> _wageOverrides = {};
  final Map<CountryCode, OvertimeRule> _overtimeOverrides = {};
  final Map<CountryCode, double> _flatTaxOverrides = {};

  DateTime? lastUpdated;

  Future<void> init() async {
    try {
      await _loadAllCountries();
    } catch (e) {
      // Offline or Firestore not set up yet — use local defaults
      print('FirestoreTaxService: Using local defaults ($e)');
    }
  }

  Future<void> _loadAllCountries() async {
    final snapshot = await _db
        .collection('tax_rates')
        .get(const GetOptions(source: Source.serverAndCache));

    for (final doc in snapshot.docs) {
      final code = _parseCountryCode(doc.id);
      if (code == null) continue;

      final data = doc.data();
      _parseInsurance(code, data);
      _parseBrackets(code, data);
      _parseMinimumWage(code, data);
      _parseOvertime(code, data);
      _parseFlatTax(code, data);

      if (data['lastUpdated'] != null) {
        lastUpdated = (data['lastUpdated'] as Timestamp).toDate();
      }
    }
  }

  /// Force refresh from server
  Future<void> refresh() async {
    try {
      final snapshot = await _db
          .collection('tax_rates')
          .get(const GetOptions(source: Source.server));

      _insuranceOverrides.clear();
      _bracketOverrides.clear();
      _wageOverrides.clear();
      _overtimeOverrides.clear();
      _flatTaxOverrides.clear();

      for (final doc in snapshot.docs) {
        final code = _parseCountryCode(doc.id);
        if (code == null) continue;

        final data = doc.data();
        _parseInsurance(code, data);
        _parseBrackets(code, data);
        _parseMinimumWage(code, data);
        _parseOvertime(code, data);
        _parseFlatTax(code, data);

        if (data['lastUpdated'] != null) {
          lastUpdated = (data['lastUpdated'] as Timestamp).toDate();
        }
      }
    } catch (e) {
      print('FirestoreTaxService: Refresh failed ($e)');
    }
  }

  // ── Getters (Firestore override → local default fallback) ──

  InsuranceRates? getInsurance(CountryCode code) {
    return _insuranceOverrides[code] ?? countryConfigs[code]?.insurance;
  }

  List<TaxBracket> getBrackets(CountryCode code) {
    return _bracketOverrides[code] ?? countryConfigs[code]?.incomeTaxBrackets ?? [];
  }

  MinimumWage getMinimumWage(CountryCode code) {
    return _wageOverrides[code] ?? countryConfigs[code]!.minimumWage;
  }

  OvertimeRule getOvertime(CountryCode code) {
    return _overtimeOverrides[code] ?? countryConfigs[code]!.overtimeRule;
  }

  double getFlatTax(CountryCode code) {
    return _flatTaxOverrides[code] ?? countryConfigs[code]!.dailyWorkerFlatTax;
  }

  // ── Parsers ──

  CountryCode? _parseCountryCode(String id) {
    try {
      return CountryCode.values.firstWhere((c) => c.name == id);
    } catch (_) {
      return null;
    }
  }

  void _parseInsurance(CountryCode code, Map<String, dynamic> data) {
    final ins = data['insurance'] as Map<String, dynamic>?;
    if (ins == null) return;
    _insuranceOverrides[code] = InsuranceRates(
      nationalPension: (ins['nationalPension'] as num?)?.toDouble() ?? 0,
      healthInsurance: (ins['healthInsurance'] as num?)?.toDouble() ?? 0,
      longTermCare: (ins['longTermCare'] as num?)?.toDouble() ?? 0,
      employmentInsurance: (ins['employmentInsurance'] as num?)?.toDouble() ?? 0,
    );
  }

  void _parseBrackets(CountryCode code, Map<String, dynamic> data) {
    final list = data['incomeTaxBrackets'] as List<dynamic>?;
    if (list == null) return;
    _bracketOverrides[code] = list.map((b) {
      final m = b as Map<String, dynamic>;
      return TaxBracket(
        (m['min'] as num).toDouble(),
        m['max'] == null ? double.infinity : (m['max'] as num).toDouble(),
        (m['rate'] as num).toDouble(),
      );
    }).toList();
  }

  void _parseMinimumWage(CountryCode code, Map<String, dynamic> data) {
    final w = data['minimumWage'] as Map<String, dynamic>?;
    if (w == null) return;
    _wageOverrides[code] = MinimumWage(
      hourly2025: (w['hourly2025'] as num?)?.toDouble() ?? 0,
      hourly2026: (w['hourly2026'] as num?)?.toDouble() ?? 0,
      daily2025: (w['daily2025'] as num?)?.toDouble(),
      daily2026: (w['daily2026'] as num?)?.toDouble(),
    );
  }

  void _parseOvertime(CountryCode code, Map<String, dynamic> data) {
    final o = data['overtime'] as Map<String, dynamic>?;
    if (o == null) return;
    _overtimeOverrides[code] = OvertimeRule(
      multiplier: (o['multiplier'] as num?)?.toDouble() ?? 1.5,
      holidayMultiplier: (o['holidayMultiplier'] as num?)?.toDouble() ?? 1.5,
      nightShiftMultiplier: (o['nightShiftMultiplier'] as num?)?.toDouble() ?? 1.5,
      description: o['description'] as String? ?? '',
    );
  }

  void _parseFlatTax(CountryCode code, Map<String, dynamic> data) {
    final flat = data['dailyWorkerFlatTax'] as num?;
    if (flat != null) {
      _flatTaxOverrides[code] = flat.toDouble();
    }
  }

  /// Upload default data to Firestore (run once to seed the database)
  Future<void> seedFirestore() async {
    for (final entry in countryConfigs.entries) {
      final code = entry.key;
      final config = entry.value;

      final data = <String, dynamic>{
        'lastUpdated': FieldValue.serverTimestamp(),
        'dailyWorkerFlatTax': config.dailyWorkerFlatTax,
      };

      if (config.insurance != null) {
        data['insurance'] = {
          'nationalPension': config.insurance!.nationalPension,
          'healthInsurance': config.insurance!.healthInsurance,
          'longTermCare': config.insurance!.longTermCare,
          'employmentInsurance': config.insurance!.employmentInsurance,
        };
      }

      data['incomeTaxBrackets'] = config.incomeTaxBrackets.map((b) => {
            'min': b.minIncome,
            'max': b.maxIncome == double.infinity ? null : b.maxIncome,
            'rate': b.rate,
          }).toList();

      data['minimumWage'] = {
        'hourly2025': config.minimumWage.hourly2025,
        'hourly2026': config.minimumWage.hourly2026,
        if (config.minimumWage.daily2025 != null)
          'daily2025': config.minimumWage.daily2025,
        if (config.minimumWage.daily2026 != null)
          'daily2026': config.minimumWage.daily2026,
      };

      data['overtime'] = {
        'multiplier': config.overtimeRule.multiplier,
        'holidayMultiplier': config.overtimeRule.holidayMultiplier,
        'nightShiftMultiplier': config.overtimeRule.nightShiftMultiplier,
        'description': config.overtimeRule.description,
      };

      await _db.collection('tax_rates').doc(code.name).set(data);
    }
    print('FirestoreTaxService: Seeded Firestore with default data');
  }
}
