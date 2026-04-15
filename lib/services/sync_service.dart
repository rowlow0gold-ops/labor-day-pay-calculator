import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'storage_service.dart';

/// Auto-sync of the entire app state (prefs + work entries) to Firestore.
///
/// Firestore layout:
///   users/{uid}/state/snapshot  → the full state document
///
/// Flow:
///   * On sign-in (or when sync is enabled), pull the cloud snapshot.
///     - If local is empty → apply cloud silently.
///     - If cloud is empty → push local silently.
///     - If both non-empty and differ → emit a [SyncConflict] via
///       [conflictStream]; the UI shows a dialog and calls [resolveConflict].
///   * Afterwards, every local mutation goes through [scheduleUpload] which
///     debounces an upload to Firestore.
class SyncService extends ChangeNotifier {
  SyncService({required this.storage, required this.auth}) {
    auth.addListener(_onAuthChanged);
  }

  final StorageService storage;
  final AuthService auth;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Persisted keys.
  static const _prefsKeyEnabled = 'cloud_sync_enabled';
  static const _prefsKeyPrompted = 'cloud_sync_prompted';

  // Cloud sync is OPT-IN. Stays false until the user explicitly enables it
  // via the post-login dialog or the Settings toggle. This prevents the app
  // from touching the cloud before the user has made an informed choice.
  bool _enabled = false;
  bool _prompted = false;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  String? _lastSyncError;
  SyncConflict? _pendingConflict;
  Timer? _debounce;

  /// Per-session flag: true once we've performed the initial pull-or-push for
  /// the currently-signed-in user. Prevents subsequent [scheduleUpload] calls
  /// from racing with the initial reconciliation.
  String? _reconciledUid;

  bool get enabled => _enabled;
  bool get syncing => _syncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastSyncError => _lastSyncError;
  SyncConflict? get pendingConflict => _pendingConflict;

  /// True once the user has been asked about cloud sync (either accepted or
  /// declined). The auth gate uses this to decide whether to show the
  /// one-time opt-in dialog after login.
  bool get prompted => _prompted;

  final StreamController<SyncConflict> _conflictController =
      StreamController<SyncConflict>.broadcast();

  /// UI should listen to this and show a resolution dialog.
  Stream<SyncConflict> get conflictStream => _conflictController.stream;

  /// Load persisted user choice from SharedPreferences. Called once at app
  /// startup from main(). Must be awaited before the UI starts listening to
  /// auth changes, so a signed-in user's saved preference is respected on
  /// the very first frame.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKeyEnabled) ?? false;
    _prompted = prefs.getBool(_prefsKeyPrompted) ?? false;
    notifyListeners();
  }

  /// Mark that the user has seen the opt-in dialog (whether they accepted or
  /// declined). Prevents the dialog from showing again on every login.
  Future<void> markPrompted() async {
    _prompted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyPrompted, true);
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, v);
    // Any explicit toggle also counts as "prompted" — no need to nag again.
    if (!_prompted) {
      _prompted = true;
      await prefs.setBool(_prefsKeyPrompted, true);
    }
    notifyListeners();
    if (v) {
      await reconcile();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    auth.removeListener(_onAuthChanged);
    _conflictController.close();
    super.dispose();
  }

  void _onAuthChanged() {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      _reconciledUid = null;
      return;
    }
    // When a new user signs in, force a reconcile.
    if (_reconciledUid != uid && _enabled) {
      unawaited(reconcile());
    }
  }

  DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = auth.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('state').doc('snapshot');
  }

  /// Initial pull-or-push after login. Emits a conflict if both sides differ.
  Future<void> reconcile() async {
    if (!_enabled) return;
    final ref = _docRef();
    if (ref == null) return;
    final uid = auth.currentUser!.uid;

    _syncing = true;
    _lastSyncError = null;
    notifyListeners();
    try {
      final snap = await ref.get();
      final cloudExists = snap.exists && (snap.data()?['snapshot'] != null);
      final local = await storage.exportSnapshot();
      final localEmpty = _isSnapshotEmpty(local);

      if (!cloudExists && localEmpty) {
        // Nothing on either side. Nothing to do.
        _reconciledUid = uid;
        _lastSyncAt = DateTime.now();
        return;
      }

      if (!cloudExists && !localEmpty) {
        // Fresh cloud → upload local.
        await _uploadNow(local);
        _reconciledUid = uid;
        _lastSyncAt = DateTime.now();
        return;
      }

      final cloud = _decodeCloud(snap.data()!);
      if (localEmpty) {
        // Local blank → adopt cloud.
        await storage.importSnapshot(cloud);
        _reconciledUid = uid;
        _lastSyncAt = DateTime.now();
        notifyListeners();
        return;
      }

      final localFp = storage.snapshotFingerprint(local);
      final cloudFp = storage.snapshotFingerprint(cloud);
      if (localFp == cloudFp) {
        _reconciledUid = uid;
        _lastSyncAt = DateTime.now();
        return;
      }

      // Real conflict → surface to the UI, wait for resolution.
      final conflict = SyncConflict(
        local: local,
        cloud: cloud,
        cloudUpdatedAt: (snap.data()?['updatedAt'] as Timestamp?)?.toDate(),
      );
      _pendingConflict = conflict;
      notifyListeners();
      _conflictController.add(conflict);
    } catch (e) {
      _lastSyncError = e.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Called by the UI after the user picks a side in the conflict dialog.
  /// [useCloud] true = overwrite local with cloud.
  /// [useCloud] false = overwrite cloud with local.
  Future<void> resolveConflict({required bool useCloud}) async {
    final conflict = _pendingConflict;
    if (conflict == null) return;
    _pendingConflict = null;
    _syncing = true;
    notifyListeners();
    try {
      if (useCloud) {
        await storage.importSnapshot(conflict.cloud);
      } else {
        await _uploadNow(conflict.local);
      }
      _reconciledUid = auth.currentUser?.uid;
      _lastSyncAt = DateTime.now();
    } catch (e) {
      _lastSyncError = e.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Debounced upload. Call this after any local mutation.
  void scheduleUpload() {
    if (!_enabled) return;
    if (auth.currentUser == null) return;
    // Don't push until we've reconciled at least once this session.
    if (_reconciledUid != auth.currentUser!.uid) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      try {
        final snap = await storage.exportSnapshot();
        await _uploadNow(snap);
      } catch (e) {
        _lastSyncError = e.toString();
        notifyListeners();
      }
    });
  }

  Future<void> _uploadNow(Map<String, dynamic> snapshot) async {
    final ref = _docRef();
    if (ref == null) return;
    _syncing = true;
    notifyListeners();
    try {
      // Firestore has a 1MB per-document limit. We serialize the snapshot as a
      // JSON string to keep the structure simple (deeply-nested maps are
      // allowed but arrays of maps exceed Firestore's nesting limits fast).
      await ref.set({
        'snapshot': jsonEncode(snapshot),
        'updatedAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      }, SetOptions(merge: false));
      _lastSyncAt = DateTime.now();
      _lastSyncError = null;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _decodeCloud(Map<String, dynamic> doc) {
    final raw = doc['snapshot'];
    if (raw is String) {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    }
    // Older / direct-map format.
    return (raw as Map).cast<String, dynamic>();
  }

  bool _isSnapshotEmpty(Map<String, dynamic> snap) {
    final prefs = (snap['prefs'] as Map?) ?? {};
    final entries = (snap['entries'] as Map?) ?? {};
    if (entries.isEmpty) {
      // Consider empty if there are no work entries and no meaningful prefs.
      // A fresh install stores a few prefs (defaults), so we only look at
      // entries for "empty" detection.
      return true;
    }
    // Any month with at least one entry counts as non-empty.
    for (final v in entries.values) {
      if (v is List && v.isNotEmpty) return false;
    }
    return true;
  }
}

class SyncConflict {
  SyncConflict({
    required this.local,
    required this.cloud,
    this.cloudUpdatedAt,
  });
  final Map<String, dynamic> local;
  final Map<String, dynamic> cloud;
  final DateTime? cloudUpdatedAt;

  int get localEntryCount => _countEntries(local);
  int get cloudEntryCount => _countEntries(cloud);

  static int _countEntries(Map<String, dynamic> snap) {
    final entries = (snap['entries'] as Map?) ?? {};
    int n = 0;
    for (final v in entries.values) {
      if (v is List) n += v.length;
    }
    return n;
  }
}
