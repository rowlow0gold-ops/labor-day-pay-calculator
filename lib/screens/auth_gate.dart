import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/encryption_service.dart';
import '../services/pattern_service.dart';
import 'auth_screen.dart';
import 'unlock_screen.dart';

/// Wraps the app. When encryption is disabled, it's a no-op — the child is
/// rendered directly. When encryption is enabled:
///   * Signed out            → AuthScreen (login/signup)
///   * Signed in, unverified → verify screen
///   * Signed in + verified, not yet unlocked this session → UnlockScreen
///     (method inferred: biometric → pattern → password)
///   * Signed in + verified + locally unlocked → child
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _unlocking = false;
  String? _unlockedUid;

  // Tracks whether the user has satisfied the local (pattern/biometric)
  // unlock challenge this session. Resets when the signed-in user changes
  // or when the session is explicitly locked.
  bool _localUnlocked = false;

  // Enrollment status, loaded asynchronously for the current user.
  bool? _patternEnrolled;
  bool? _biometricEnabled;
  String? _enrollmentUid;

  Future<void> _loadEnrollment(
      BuildContext context, AuthService auth) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    if (_enrollmentUid == uid &&
        _patternEnrolled != null &&
        _biometricEnabled != null) {
      return;
    }
    final pat = context.read<PatternService>();
    final bio = context.read<BiometricService>();
    final hasPattern = await pat.hasPattern(uid);
    final bioOn = await bio.isEnabled(uid);
    if (!mounted) return;
    setState(() {
      _patternEnrolled = hasPattern;
      _biometricEnabled = bioOn;
      _enrollmentUid = uid;
    });
  }

  Future<void> _ensureUnlocked(
      BuildContext context, AuthService auth, AppState app) async {
    if (_unlocking) return;
    final user = auth.currentUser;
    if (user == null || !user.emailVerified) return;
    if (_unlockedUid == user.uid && app.storage.isUnlocked) return;

    setState(() => _unlocking = true);
    try {
      final enc = context.read<EncryptionService>();
      await enc.loadOrCreateKey(user.uid);
      await app.storage.unlockAndLoad();
      _unlockedUid = user.uid;
      app.storageUnlockedChanged();
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final app = context.watch<AppState>();
    final encryptionOn = app.encryptionEnabled;

    if (!encryptionOn) {
      return widget.child;
    }

    // Google accounts skip the email-link verification step — their email is
    // already verified by Google.
    final needsVerification = !auth.isGoogleAccount && !auth.isVerified;
    if (!auth.isSignedIn || needsVerification) {
      // Clear session-bound local-unlock state.
      if (_localUnlocked || _enrollmentUid != null) {
        _localUnlocked = false;
        _enrollmentUid = null;
        _patternEnrolled = null;
        _biometricEnabled = null;
      }
      return const AuthScreen();
    }

    // Load pattern/biometric enrollment for this user.
    final uid = auth.currentUser!.uid;
    if (_enrollmentUid != uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadEnrollment(context, auth);
      });
      return const _UnlockingScreen();
    }

    // When encryption is ON, always show the UnlockScreen on every launch —
    // even when neither pattern nor biometric is enrolled (password-only
    // mode). UnlockScreen infers the method from what's enrolled:
    //   biometric enabled → fingerprint
    //   pattern enrolled  → 9-dot pattern
    //   neither           → password (account password re-entry)
    if (!_localUnlocked) {
      return UnlockScreen(
        patternEnrolled: _patternEnrolled ?? false,
        biometricEnabled: _biometricEnabled ?? false,
        onUnlocked: () {
          setState(() => _localUnlocked = true);
        },
      );
    }

    // Logged in + verified + local lock passed (or none). Ensure the data
    // cache is unlocked.
    if (!app.storage.isUnlocked || _unlockedUid != uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureUnlocked(context, auth, app);
      });
      return const _UnlockingScreen();
    }

    return widget.child;
  }
}

class _UnlockingScreen extends StatelessWidget {
  const _UnlockingScreen();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.get('unlocking')),
          ],
        ),
      ),
    );
  }
}
