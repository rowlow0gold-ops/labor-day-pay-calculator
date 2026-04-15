import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores a hash of the user's 9-dot unlock pattern in the Keychain / Keystore.
/// The pattern never leaves the device — it's an extra local unlock shortcut
/// on top of Firebase's persistent session.
class PatternService extends ChangeNotifier {
  static const _kPrefix = 'pattern_hash_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final Map<String, bool> _cachedHasPattern = {};

  String _key(String uid) => '$_kPrefix$uid';

  String _hashDots(List<int> dots) {
    final salt = 'ldpc-pattern-v1';
    final payload = utf8.encode('$salt:${dots.join(",")}');
    return sha256.convert(payload).toString();
  }

  /// Persist a pattern for [uid]. Pattern must have at least 4 dots.
  Future<void> setPattern(String uid, List<int> dots) async {
    if (dots.length < 4) {
      throw ArgumentError('Pattern must connect at least 4 dots');
    }
    final hash = _hashDots(dots);
    await _storage.write(key: _key(uid), value: hash);
    _cachedHasPattern[uid] = true;
    notifyListeners();
  }

  /// Returns true if [dots] matches the stored pattern for [uid].
  Future<bool> checkPattern(String uid, List<int> dots) async {
    final stored = await _storage.read(key: _key(uid));
    if (stored == null) return false;
    return stored == _hashDots(dots);
  }

  Future<bool> hasPattern(String uid) async {
    if (_cachedHasPattern.containsKey(uid)) return _cachedHasPattern[uid]!;
    final stored = await _storage.read(key: _key(uid));
    final exists = stored != null;
    _cachedHasPattern[uid] = exists;
    return exists;
  }

  Future<void> clearPattern(String uid) async {
    await _storage.delete(key: _key(uid));
    _cachedHasPattern[uid] = false;
    notifyListeners();
  }
}
