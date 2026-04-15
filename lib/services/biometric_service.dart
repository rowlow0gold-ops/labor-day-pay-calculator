import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric / fingerprint unlock powered by `local_auth`.
///
/// Like the pattern lock, biometrics are an on-device convenience layer on top
/// of Firebase's persistent session — authenticating successfully allows us
/// to proceed to StorageService.unlockAndLoad without re-prompting for the
/// password.
class BiometricService extends ChangeNotifier {
  static const _kPrefix = 'biometric_enabled_';

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final Map<String, bool> _enabledCache = {};

  String _key(String uid) => '$_kPrefix$uid';

  Future<bool> isDeviceSupported() async {
    // local_auth doesn't support web — never report supported there.
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final can = await _auth.canCheckBiometrics;
      return can;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    if (kIsWeb) return const [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isEnabled(String uid) async {
    if (_enabledCache.containsKey(uid)) return _enabledCache[uid]!;
    final v = await _storage.read(key: _key(uid));
    final on = v == '1';
    _enabledCache[uid] = on;
    return on;
  }

  Future<void> setEnabled(String uid, bool enabled) async {
    if (enabled) {
      await _storage.write(key: _key(uid), value: '1');
    } else {
      await _storage.delete(key: _key(uid));
    }
    _enabledCache[uid] = enabled;
    notifyListeners();
  }

  /// Prompt the OS biometric dialog. Returns true on success.
  Future<bool> authenticate(String reason) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // also allow device PIN/passcode as fallback
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
