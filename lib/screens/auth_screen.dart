import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/app_state.dart';

/// Full-screen lock with a multi-step flow:
///   * signIn              → email + password
///   * signUpEnterEmail    → email only, then send verification link
///   * signUpVerifying     → "check your inbox" with Check / Resend / Back
///   * signUpSetPassword   → 2 password boxes, set final password
///   * verifyExisting      → an already-created account still not verified
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Step { signIn, signUpEnterEmail, signUpVerifying, signUpSetPassword }

class _AuthScreenState extends State<AuthScreen> {
  _Step _step = _Step.signIn;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pwd1Controller = TextEditingController();
  final _pwd2Controller = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  bool _obscurePwd = true;
  bool _obscurePwd1 = true;
  bool _obscurePwd2 = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pwd1Controller.dispose();
    _pwd2Controller.dispose();
    super.dispose();
  }

  String _mapError(Object e, AppLocalizations l) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return l.get('auth_err_invalid_email');
        case 'user-disabled':
          return l.get('auth_err_disabled');
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return l.get('auth_err_wrong_creds');
        case 'email-already-in-use':
          return l.get('auth_err_email_in_use');
        case 'weak-password':
          return l.get('auth_err_weak_password');
        case 'network-request-failed':
          return l.get('auth_err_network');
        case 'requires-recent-login':
          return l.get('auth_err_recent_login');
        default:
          return e.message ?? l.get('auth_err_generic');
      }
    }
    // Show real error for debugging
    return e.toString();
  }

  String _genTempPassword() {
    final r = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#\$%';
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // ── Sign in ───────────────────────────────────────────────────────────
  Future<void> _doSignIn() async {
    final auth = context.read<AuthService>();
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final canPop = nav.canPop();
    final email = _emailController.text.trim();
    final pwd = _passwordController.text;
    if (email.isEmpty || pwd.isEmpty) {
      setState(() => _error = l.get('auth_err_empty'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await auth.signIn(email, pwd);
      // Swap local data out, restore user data
      final uid = auth.currentUser?.uid;
      if (uid != null) {
        try { await app.storage.swapToUser(uid); } catch (_) {}
      }
      app.refreshRates();
      // If pushed from Settings, pop back after successful login.
      if (canPop) {
        nav.pop();
        return;
      }
    } catch (e) {
      if (mounted) setState(() => _error = _mapError(e, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Step 1: create temp account + send verification ───────────────────
  Future<void> _doStartSignUp() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = l.get('auth_err_enter_email'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      // Create the account with a random temporary password, then immediately
      // dispatch the verification email. The user will set their real password
      // in step 3 via updatePassword() once verified.
      await auth.signUp(email, _genTempPassword());
      if (mounted) {
        setState(() {
          _step = _Step.signUpVerifying;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _mapError(e, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Step 2: poll verification status ──────────────────────────────────
  Future<void> _doCheckVerified() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final ok = await auth.reloadVerification();
      if (!mounted) return;
      if (ok) {
        setState(() => _step = _Step.signUpSetPassword);
      } else {
        setState(() => _info = l.get('auth_not_yet_verified'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doResendVerification() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await auth.resendVerificationEmail();
      if (mounted) setState(() => _info = l.get('auth_verification_resent'));
    } catch (e) {
      if (mounted) setState(() => _error = _mapError(e, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Step 3: set real password ─────────────────────────────────────────
  Future<void> _doSetPassword() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final canPop = nav.canPop();
    final p1 = _pwd1Controller.text;
    final p2 = _pwd2Controller.text;
    if (p1.isEmpty || p2.isEmpty) {
      setState(() => _error = l.get('auth_err_empty'));
      return;
    }
    if (p1.length < 6) {
      setState(() => _error = l.get('auth_err_weak_password'));
      return;
    }
    if (p1 != p2) {
      setState(() => _error = l.get('auth_err_pwd_mismatch'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await auth.updatePassword(p1);
      // If pushed from Settings, pop back after finishing sign-up.
      if (canPop) {
        nav.pop();
        return;
      }
    } catch (e) {
      if (mounted) setState(() => _error = _mapError(e, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Google sign-in ────────────────────────────────────────────────────
  Future<void> _doGoogleSignIn() async {
    final auth = context.read<AuthService>();
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final canPop = nav.canPop();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final user = await auth.signInWithGoogle();
      if (user == null) {
        // User cancelled the Google picker
        if (mounted) setState(() => _busy = false);
        return;
      }
      try { await app.storage.swapToUser(user.uid); } catch (_) {}
      app.refreshRates();
      if (canPop) {
        nav.pop();
        return;
      }
    } catch (e) {
      if (mounted) setState(() => _error = _mapError(e, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Password reset ────────────────────────────────────────────────────
  Future<void> _forgotPassword() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = l.get('auth_err_enter_email'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await auth.sendPasswordResetEmail(email);
      if (mounted) setState(() => _info = l.get('auth_reset_sent'));
    } catch (e) {
      if (mounted) setState(() => _error = _mapError(e, l));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Back navigation ───────────────────────────────────────────────────
  Future<void> _goBack() async {
    final auth = context.read<AuthService>();
    switch (_step) {
      case _Step.signIn:
        // If pushed as a route (from Settings), just pop back.
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        // Otherwise AuthGate forced this screen — disable the lock.
        final app = context.read<AppState>();
        await app.setEncryptionEnabled(false);
        return;
      case _Step.signUpEnterEmail:
        setState(() {
          _step = _Step.signIn;
          _error = null;
          _info = null;
        });
        break;
      case _Step.signUpVerifying:
      case _Step.signUpSetPassword:
        // We created an unverified account; sign out so we're not stuck on
        // the verify screen next launch.
        try {
          await auth.signOut();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _step = _Step.signIn;
            _error = null;
            _info = null;
            _pwd1Controller.clear();
            _pwd2Controller.clear();
          });
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final l = AppLocalizations.of(context);

    // Existing account that's still unverified (user closed app mid-signup).
    // Show the dedicated verify screen.
    if (_step == _Step.signIn &&
        auth.isSignedIn &&
        !auth.isVerified) {
      return _VerifyExistingScreen(email: auth.email ?? '');
    }

    switch (_step) {
      case _Step.signIn:
        return _buildSignIn(l);
      case _Step.signUpEnterEmail:
        return _buildSignUpEmail(l);
      case _Step.signUpVerifying:
        return _buildSignUpVerifying(l, auth.email ?? _emailController.text);
      case _Step.signUpSetPassword:
        return _buildSignUpSetPassword(l);
    }
  }

  // ── UI builders ───────────────────────────────────────────────────────
  Widget _scaffold({
    required AppLocalizations l,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
    bool showBack = false,
  }) {
    return Scaffold(
      appBar: showBack
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy ? null : _goBack,
                tooltip: l.get('back'),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
            )
          : null,
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icon, size: 56, color: const Color(0xFF00B8A9)),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13)),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF00B8A9), fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignIn(AppLocalizations l) {
    return _scaffold(
      l: l,
      title: l.get('auth_signin_title'),
      subtitle: l.get('auth_subtitle'),
      icon: Icons.lock_outline,
      showBack: true,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            labelText: l.get('email'),
            prefixIcon: const Icon(Icons.email_outlined, size: 18),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePwd,
          decoration: InputDecoration(
            labelText: l.get('password'),
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscurePwd
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
            ),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _doSignIn,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l.get('auth_signin_btn')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Divider(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l.get('or'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5),
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _doGoogleSignIn,
          icon: const Icon(Icons.g_mobiledata, size: 28),
          label: Text(l.get('auth_google_signin')),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : _forgotPassword,
          child: Text(l.get('auth_forgot_password')),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = _Step.signUpEnterEmail;
                    _error = null;
                    _info = null;
                  }),
          child: Text(l.get('auth_no_account')),
        ),
      ],
    );
  }

  Widget _buildSignUpEmail(AppLocalizations l) {
    return _scaffold(
      l: l,
      title: l.get('auth_signup_title'),
      subtitle: l.get('auth_signup_email_sub'),
      icon: Icons.mail_outline,
      showBack: true,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            labelText: l.get('email'),
            prefixIcon: const Icon(Icons.email_outlined, size: 18),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _doStartSignUp,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l.get('auth_send_verification')),
        ),
      ],
    );
  }

  Widget _buildSignUpVerifying(AppLocalizations l, String email) {
    return _scaffold(
      l: l,
      title: l.get('auth_verify_title'),
      subtitle: l.getWith('auth_verify_body', {'email': email}),
      icon: Icons.mark_email_read_outlined,
      showBack: true,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _doCheckVerified,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l.get('auth_verify_check')),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _doResendVerification,
          child: Text(l.get('auth_verify_resend')),
        ),
      ],
    );
  }

  Widget _buildSignUpSetPassword(AppLocalizations l) {
    return _scaffold(
      l: l,
      title: l.get('auth_set_password_title'),
      subtitle: l.get('auth_set_password_sub'),
      icon: Icons.password,
      showBack: true,
      children: [
        TextField(
          controller: _pwd1Controller,
          obscureText: _obscurePwd1,
          decoration: InputDecoration(
            labelText: l.get('password'),
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscurePwd1
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePwd1 = !_obscurePwd1),
            ),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pwd2Controller,
          obscureText: _obscurePwd2,
          decoration: InputDecoration(
            labelText: l.get('password_confirm'),
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscurePwd2
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePwd2 = !_obscurePwd2),
            ),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _doSetPassword,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l.get('auth_finish')),
        ),
      ],
    );
  }
}

/// Shown when an already-created account is signed in but still not verified —
/// e.g. if the user closed the app mid-signup and reopened it.
class _VerifyExistingScreen extends StatefulWidget {
  const _VerifyExistingScreen({required this.email});
  final String email;

  @override
  State<_VerifyExistingScreen> createState() => _VerifyExistingScreenState();
}

class _VerifyExistingScreenState extends State<_VerifyExistingScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _check() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ok = await auth.reloadVerification();
      if (!ok && mounted) {
        setState(() => _message = l.get('auth_not_yet_verified'));
      }
      // If verified, AuthService notifies listeners → AuthScreen will rebuild
      // and the caller will route accordingly (next step is set-password? or
      // unlock). Since this path is reached when the user had a real password
      // already set, we go straight to unlock via AuthGate.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.resendVerificationEmail();
      if (mounted) setState(() => _message = l.get('auth_verification_resent'));
    } catch (_) {
      if (mounted) setState(() => _message = l.get('auth_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_read_outlined,
                      size: 56, color: Color(0xFF00B8A9)),
                  const SizedBox(height: 16),
                  Text(l.get('auth_verify_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    l.getWith('auth_verify_body', {'email': widget.email}),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6)),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF00B8A9), fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : _check,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(l.get('auth_verify_check')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : _resend,
                    child: Text(l.get('auth_verify_resend')),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : () => auth.signOut(),
                    child: Text(l.get('auth_signout')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
