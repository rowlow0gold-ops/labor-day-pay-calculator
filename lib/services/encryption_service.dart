import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages a per-user 32-byte AES-GCM key used to encrypt/decrypt local data.
///
/// Storage strategy:
///   * Local: flutter_secure_storage (Keychain on iOS, Keystore on Android)
///     keyed by the user's uid so multiple accounts on the same device don't
///     clash.
///   * Cloud backup: the same raw key is stored at
///     `users/{uid}/security/key` in Firestore so that on another device,
///     after signing in, the key can be downloaded and the user's encrypted
///     entries (synced elsewhere) can be decrypted.
///
/// The key is NOT derived from the user's password — Firebase password
/// reset would otherwise destroy the decryption path. The trade-off is that
/// this design is NOT end-to-end (Firebase/server holds the key); it is
/// "encrypted-at-rest on device" plus "recoverable cloud backup".
class EncryptionService {
  EncryptionService({FirebaseFirestore? firestore, FlutterSecureStorage? secure})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _secure = secure ?? const FlutterSecureStorage();

  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _secure;
  final _algorithm = AesGcm.with256bits();

  SecretKey? _cachedKey;
  String? _cachedUid;

  String _localKeyName(String uid) => 'enc_key_$uid';

  /// Is a key currently loaded in memory?
  bool get hasKey => _cachedKey != null;

  /// Clear any cached key (call on sign-out).
  void clearCache() {
    _cachedKey = null;
    _cachedUid = null;
  }

  /// Load the user's key. Preference order:
  ///   1. In-memory cache
  ///   2. Local secure storage
  ///   3. Firestore backup (downloaded and cached locally for next time)
  ///   4. Generate a brand-new key and persist in both places
  Future<SecretKey> loadOrCreateKey(String uid) async {
    if (_cachedKey != null && _cachedUid == uid) return _cachedKey!;

    // Try local secure storage
    final localRaw = await _secure.read(key: _localKeyName(uid));
    if (localRaw != null && localRaw.isNotEmpty) {
      final key = SecretKey(base64Decode(localRaw));
      _cachedKey = key;
      _cachedUid = uid;
      return key;
    }

    // Try cloud backup
    final doc =
        await _firestore.collection('users').doc(uid).collection('security').doc('key').get();
    if (doc.exists) {
      final data = doc.data();
      final remoteRaw = data != null ? data['key'] as String? : null;
      if (remoteRaw != null && remoteRaw.isNotEmpty) {
        await _secure.write(key: _localKeyName(uid), value: remoteRaw);
        final key = SecretKey(base64Decode(remoteRaw));
        _cachedKey = key;
        _cachedUid = uid;
        return key;
      }
    }

    // Generate fresh
    final bytes = _randomBytes(32);
    final raw = base64Encode(bytes);
    await _secure.write(key: _localKeyName(uid), value: raw);
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('security')
        .doc('key')
        .set({
      'key': raw,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final key = SecretKey(bytes);
    _cachedKey = key;
    _cachedUid = uid;
    return key;
  }

  /// Wipe the user's key on this device (does NOT delete the cloud backup).
  Future<void> forgetLocalKey(String uid) async {
    await _secure.delete(key: _localKeyName(uid));
    clearCache();
  }

  /// Encrypt a UTF-8 string, returning a compact base64 envelope
  /// `<nonce_b64>.<ciphertext_b64>.<mac_b64>` suitable for storing inside
  /// JSON strings or SharedPreferences.
  Future<String> encryptString(String plaintext) async {
    final key = _requireKey();
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return '${base64Encode(secretBox.nonce)}.'
        '${base64Encode(secretBox.cipherText)}.'
        '${base64Encode(secretBox.mac.bytes)}';
  }

  Future<String> decryptString(String envelope) async {
    final key = _requireKey();
    final parts = envelope.split('.');
    if (parts.length != 3) {
      throw const FormatException('Invalid encrypted envelope');
    }
    final secretBox = SecretBox(
      base64Decode(parts[1]),
      nonce: base64Decode(parts[0]),
      mac: Mac(base64Decode(parts[2])),
    );
    final clear = await _algorithm.decrypt(secretBox, secretKey: key);
    return utf8.decode(clear);
  }

  SecretKey _requireKey() {
    final k = _cachedKey;
    if (k == null) {
      throw StateError('EncryptionService: key not loaded. Call loadOrCreateKey() first.');
    }
    return k;
  }

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    final out = Uint8List(length);
    for (int i = 0; i < length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }
}
