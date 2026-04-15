import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/pattern_service.dart';
import 'pattern_screen.dart';

/// App-lock screen shown on every launch when encryption is ON.
///
/// Methods are independent — the user can have all three enrolled
/// simultaneously (password is always available since it's the Firebase
/// account password). The default method shown on entry is inferred by
/// priority (biometric → pattern → password), but the "Try another method"
/// picker lets the user switch to any enrolled method.
///
/// Attempt limits: each method locks out after 10 failed attempts in the
/// same session. A locked method shows a reset option in the picker.
///
/// Reset options (all accessible via the picker):
///   * Password → email reset via Firebase
///   * 9-dot pattern → clear + re-enroll in Settings (requires password)
///   * Fingerprint → disable + re-enable in Settings (requires password)
///
/// The screen never signs the user out. It never returns to the sign-in
/// page. The Firebase account password is the root of trust for reset.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.patternEnrolled,
    required this.biometricEnabled,
    required this.onUnlocked,
  });

  final bool patternEnrolled;
  final bool biometricEnabled;
  final VoidCallback onUnlocked;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

enum _Method { password, pattern, fingerprint }

/// Per-method limit — after this many failed tries, the method is locked
/// for the rest of the session and can only be re-enabled via reset.
const int _kMaxAttempts = 10;

class _UnlockScreenState extends State<UnlockScreen> {
  bool _errorFlash = false;
  bool _busy = false;
  String? _status;
  final _passwordCtl = TextEditingController();
  bool _passwordVisible = false;

  /// Per-method failed-attempt counters. Each one is capped at
  /// [_kMaxAttempts]; past that the method is considered locked.
  int _passwordFails = 0;
  int _patternFails = 0;
  int _biometricFails = 0;

  /// Local enrollment flags — mirror widget props but can be flipped by
  /// the reset flows (pattern cleared, fingerprint disabled).
  late bool _patternEnrolled = widget.patternEnrolled;
  late bool _biometricEnabled = widget.biometricEnabled;

  /// When non-null, overrides the inferred default. Set by the "Try another
  /// method" picker so the user can manually switch method.
  _Method? _selectedMethod;

  _Method get _inferredMethod {
    if (_biometricEnabled && !_isLocked(_Method.fingerprint)) {
      return _Method.fingerprint;
    }
    if (_patternEnrolled && !_isLocked(_Method.pattern)) {
      return _Method.pattern;
    }
    return _Method.password;
  }

  _Method get _method => _selectedMethod ?? _inferredMethod;

  int _failsFor(_Method m) {
    switch (m) {
      case _Method.password:
        return _passwordFails;
      case _Method.pattern:
        return _patternFails;
      case _Method.fingerprint:
        return _biometricFails;
    }
  }

  bool _isLocked(_Method m) => _failsFor(m) >= _kMaxAttempts;

  bool _isEnrolled(_Method m) {
    switch (m) {
      case _Method.password:
        return true;
      case _Method.pattern:
        return _patternEnrolled;
      case _Method.fingerprint:
        return _biometricEnabled;
    }
  }

  @override
  void initState() {
    super.initState();
    // Auto-trigger biometric prompt on mount if the inferred starting
    // method is fingerprint.
    if (_method == _Method.fingerprint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  @override
  void dispose() {
    _passwordCtl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Try-a-method handlers
  // ---------------------------------------------------------------------

  Future<void> _tryBiometric() async {
    if (_busy || !mounted) return;
    if (_isLocked(_Method.fingerprint)) return;
    final bio = context.read<BiometricService>();
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final ok = await bio.authenticate(l.get('biometric_prompt'));
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        _biometricFails += 1;
        setState(() => _status = _statusForFailure(_Method.fingerprint, l));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPatternDrawn(List<int> dots) async {
    if (_isLocked(_Method.pattern)) return;
    final auth = context.read<AuthService>();
    final pat = context.read<PatternService>();
    final l = AppLocalizations.of(context);
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final ok = await pat.checkPattern(uid, dots);
    if (ok) {
      widget.onUnlocked();
    } else {
      _patternFails += 1;
      if (mounted) {
        setState(() {
          _errorFlash = true;
          _status = _statusForFailure(_Method.pattern, l);
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) setState(() => _errorFlash = false);
      }
    }
  }

  Future<void> _tryPassword() async {
    if (_busy) return;
    if (_isLocked(_Method.password)) return;
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    final pw = _passwordCtl.text;
    if (pw.isEmpty) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final ok = await auth.verifyPassword(pw);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        _passwordFails += 1;
        setState(() => _status = _statusForFailure(_Method.password, l));
      }
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Build a per-method status line that also shows remaining tries or a
  /// locked message so the user sees exactly where they stand.
  String _statusForFailure(_Method m, AppLocalizations l) {
    final remaining = _kMaxAttempts - _failsFor(m);
    if (remaining <= 0) {
      return l.get('unlock_method_locked');
    }
    final base = switch (m) {
      _Method.password => l.get('unlock_wrong_password'),
      _Method.pattern => l.getWith('pattern_wrong', {'n': '$_patternFails'}),
      _Method.fingerprint => l.get('biometric_failed'),
    };
    return '$base  ·  ${l.getWith('unlock_attempts_remaining', {
          'n': '$remaining'
        })}';
  }

  // ---------------------------------------------------------------------
  // Reset flows (all require Firebase password re-authentication as the
  // root-of-trust, except the password reset itself which goes via email).
  // ---------------------------------------------------------------------

  Future<void> _resetPasswordByEmail() async {
    final auth = context.read<AuthService>();
    final l = AppLocalizations.of(context);
    final email = auth.email;
    if (email == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.get('unlock_reset_password')),
        content:
            Text(l.getWith('security_reset_confirm', {'email': email})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.get('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await auth.sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.get('unlock_reset_sent'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  /// Disable fingerprint unlock after verifying the Firebase password.
  Future<void> _resetFingerprint() async {
    final l = AppLocalizations.of(context);
    final ok = await _promptPasswordForReset(
      l.get('unlock_reset_fingerprint_title'),
      l.get('unlock_reset_fingerprint_body'),
    );
    if (!ok) return;
    final auth = context.read<AuthService>();
    final bio = context.read<BiometricService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    await bio.setEnabled(uid, false);
    if (!mounted) return;
    setState(() {
      _biometricEnabled = false;
      _biometricFails = 0;
      if (_selectedMethod == _Method.fingerprint) _selectedMethod = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.get('unlock_fingerprint_disabled'))),
    );
  }

  /// Inline password prompt used by the pattern/fingerprint reset flows.
  /// Returns true on successful password verification. Does NOT consume
  /// a password-attempt slot — this is a separate reset gate, not a
  /// sign-in attempt, so it can't accidentally lock the password method.
  Future<bool> _promptPasswordForReset(String title, String body) async {
    final l = AppLocalizations.of(context);
    final ctl = TextEditingController();
    var visible = false;
    var verifying = false;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(body, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                obscureText: !visible,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.get('unlock_password_hint'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(visible
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setLocal(() => visible = !visible),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  verifying ? null : () => Navigator.pop(ctx, false),
              child: Text(l.get('cancel')),
            ),
            FilledButton(
              onPressed: verifying
                  ? null
                  : () async {
                      final pw = ctl.text;
                      if (pw.isEmpty) return;
                      setLocal(() {
                        verifying = true;
                        error = null;
                      });
                      final auth = context.read<AuthService>();
                      try {
                        final good = await auth.verifyPassword(pw);
                        if (!ctx.mounted) return;
                        if (good) {
                          Navigator.pop(ctx, true);
                        } else {
                          setLocal(() {
                            verifying = false;
                            error = l.get('unlock_wrong_password');
                          });
                        }
                      } catch (e) {
                        setLocal(() {
                          verifying = false;
                          error = e.toString();
                        });
                      }
                    },
              child: Text(l.get('confirm')),
            ),
          ],
        ),
      ),
    );
    ctl.dispose();
    return ok == true;
  }

  // ---------------------------------------------------------------------
  // Method picker
  // ---------------------------------------------------------------------

  /// Bottom-sheet picker. Top section: switch active method (only shows
  /// enrolled + unlocked methods as enabled). Bottom section: reset flows
  /// for password / pattern / fingerprint. The user never signs out.
  Future<void> _showMethodPicker() async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l.get('unlock_pick_method'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPickerTile(
                  ctx: ctx,
                  method: _Method.password,
                  icon: Icons.lock_outline,
                  label: l.get('unlock_method_password'),
                  l: l,
                ),
                _buildPickerTile(
                  ctx: ctx,
                  method: _Method.pattern,
                  icon: Icons.grid_3x3,
                  label: l.get('unlock_method_pattern'),
                  l: l,
                ),
                _buildPickerTile(
                  ctx: ctx,
                  method: _Method.fingerprint,
                  icon: Icons.fingerprint,
                  label: l.get('unlock_method_fingerprint'),
                  l: l,
                ),
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: Text(
                    l.get('unlock_reset_section'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                ),
                // Password reset via email — always available.
                ListTile(
                  leading: const Icon(Icons.mark_email_read_outlined),
                  title: Text(l.get('unlock_method_reset_email')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _resetPasswordByEmail();
                  },
                ),
                // Disable fingerprint — only if it's enabled.
                if (_biometricEnabled)
                  ListTile(
                    leading: const Icon(Icons.fingerprint_outlined),
                    title: Text(l.get('unlock_method_reset_fingerprint')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _resetFingerprint();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPickerTile({
    required BuildContext ctx,
    required _Method method,
    required IconData icon,
    required String label,
    required AppLocalizations l,
  }) {
    final enrolled = _isEnrolled(method);
    final locked = _isLocked(method);
    final enabled = enrolled && !locked;
    final remaining = _kMaxAttempts - _failsFor(method);
    String? subtitle;
    if (!enrolled) {
      subtitle = l.get('unlock_method_unavailable');
    } else if (locked) {
      subtitle = l.get('unlock_method_locked');
    } else if (_failsFor(method) > 0) {
      subtitle = l.getWith('unlock_attempts_remaining', {'n': '$remaining'});
    }
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: enabled,
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: enabled
          ? () {
              Navigator.pop(ctx);
              _switchTo(method);
            }
          : null,
    );
  }

  /// Switch the active unlock method without signing out. For fingerprint
  /// we also re-trigger the system prompt so the user doesn't have to tap
  /// a second button.
  void _switchTo(_Method m) {
    setState(() {
      _selectedMethod = m;
      _status = null;
      _passwordCtl.clear();
      _passwordVisible = false;
    });
    if (m == _Method.fingerprint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final email = context.watch<AuthService>().email ?? '';
    final locked = _isLocked(_method);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.lock_outline,
                  size: 48, color: Color(0xFF00B8A9)),
              const SizedBox(height: 12),
              Text(
                l.get('unlock_title'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              // Fixed email — shown as read-only, no input required.
              Text(
                email,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _subtitleFor(_method, l),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6)),
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(
                  _status!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: locked
                    ? _buildLockedBody(l)
                    : _buildBody(l),
              ),
              const SizedBox(height: 8),
              // Only escape hatch. No plain sign-out, no return to the
              // sign-in page. Opens a picker with all methods + resets.
              TextButton(
                onPressed: _busy ? null : _showMethodPicker,
                child: Text(l.get('unlock_try_another')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(_Method m, AppLocalizations l) {
    switch (m) {
      case _Method.password:
        return l.get('unlock_sub_password');
      case _Method.pattern:
        return l.get('unlock_sub_pattern');
      case _Method.fingerprint:
        return l.get('unlock_sub_biometric');
    }
  }

  /// Shown when the current method is locked out — nudges the user toward
  /// the picker rather than letting them keep failing.
  Widget _buildLockedBody(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_clock, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(
            l.get('unlock_method_locked'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _showMethodPicker,
            icon: const Icon(Icons.tune),
            label: Text(l.get('unlock_try_another')),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    switch (_method) {
      case _Method.password:
        return _buildPasswordBody(l);
      case _Method.pattern:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: PatternPad(
              errorFlash: _errorFlash,
              disabled: _busy,
              onComplete: _onPatternDrawn,
            ),
          ),
        );
      case _Method.fingerprint:
        return Center(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _tryBiometric,
            icon: const Icon(Icons.fingerprint),
            label: Text(l.get('use_biometric')),
          ),
        );
    }
  }

  Widget _buildPasswordBody(AppLocalizations l) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _passwordCtl,
            obscureText: !_passwordVisible,
            autofocus: true,
            onSubmitted: (_) => _tryPassword(),
            decoration: InputDecoration(
              hintText: l.get('unlock_password_hint'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_passwordVisible
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _tryPassword,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(l.get('unlock_btn')),
          ),
        ],
      ),
    );
  }
}
