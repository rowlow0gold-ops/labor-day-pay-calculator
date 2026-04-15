import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around FirebaseAuth exposing the signup/login/verify/reset flow
/// needed by the encryption gate.
///
/// State flow:
///   signed out        → currentUser == null
///   signed in, not verified → requires emailVerified before the app unlocks
///   signed in + verified    → app unlocks
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  AuthService() {
    // Rebuild listeners when auth state changes (login, logout, token refresh).
    _auth.authStateChanges().listen((_) => notifyListeners());
    _auth.userChanges().listen((_) => notifyListeners());
  }

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => currentUser != null;
  bool get isVerified => currentUser?.emailVerified ?? false;
  String? get email => currentUser?.email;

  /// True when the current session was established via a federated provider
  /// (Google) whose email is already verified by the IdP — the email-link
  /// verification step should be skipped for these accounts.
  bool get isGoogleAccount =>
      currentUser?.providerData.any((p) => p.providerId == 'google.com') ??
      false;

  /// Create a new account and immediately dispatch the verification email.
  Future<void> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.sendEmailVerification();
  }

  /// Sign in with an existing email + password.
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Verify the password of the currently-signed-in user WITHOUT changing
  /// any auth state. Used by the "password only" unlock mode — the user has
  /// already signed in and we just want to confirm identity before opening
  /// the local cache. Returns true on success, false on a wrong password.
  /// Re-throws other errors (network, throttling, etc.).
  Future<bool> verifyPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) return false;
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-login-credentials') {
        return false;
      }
      rethrow;
    }
  }

  /// Pull the latest verification status from the server.
  Future<bool> reloadVerification() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    notifyListeners();
    return user.emailVerified;
  }

  /// Send another verification email if the first one expired or got lost.
  Future<void> resendVerificationEmail() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Trigger Firebase's hosted password-reset email flow.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    // Also sign out of Google so the next Google sign-in shows the account
    // picker rather than silently reusing the previous account.
    try {
      final gs = GoogleSignIn();
      if (await gs.isSignedIn()) {
        await gs.signOut();
      }
    } catch (_) {
      // Non-fatal — Firebase sign-out below is the source of truth.
    }
    await _auth.signOut();
  }

  /// Sign in with Google. On Android this uses the native account picker.
  /// Returns the signed-in [User], or null if the user cancelled.
  Future<User?> signInWithGoogle() async {
    final gs = GoogleSignIn();
    final account = await gs.signIn();
    if (account == null) return null; // user cancelled picker
    final gAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    return cred.user;
  }

  /// Update the currently signed-in user's password.
  /// Used by the two-step signup flow (temp password → real password after
  /// email verification).
  Future<void> updatePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
  }

  /// Delete the account permanently. Requires the user to have signed in
  /// recently, else Firebase throws `requires-recent-login`.
  Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
  }
}
