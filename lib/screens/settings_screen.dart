import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/encryption_service.dart';
import '../services/pattern_service.dart';
import '../services/sync_service.dart';
import 'auth_screen.dart';
import 'pattern_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  // "Saved" snapshot — what was persisted before entering settings
  late String _savedLang;
  late bool _savedDark;

  final _unlockKey = GlobalKey<_UnlockMethodTileState>();

  bool _hasChanges = false;
  bool _initialized = false;

  // Pending state for sync & encryption (null = no change from saved)
  bool? _pendingSyncEnabled;
  bool? _pendingEncryptionEnabled;
  late bool _savedSyncEnabled;
  late bool _savedEncryptionEnabled;

  void _captureSnapshot(AppState app) {
    _savedLang = app.locale.languageCode;
    _savedDark = app.isDark;
    _savedSyncEnabled = context.read<SyncService>().enabled;
    _savedEncryptionEnabled = app.encryptionEnabled;
    _pendingSyncEnabled = null;
    _pendingEncryptionEnabled = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _captureSnapshot(context.read<AppState>());
      _initialized = true;
    }
  }

  bool _checkChanges(AppState app) {
    final syncChanged = _pendingSyncEnabled != null &&
        _pendingSyncEnabled != _savedSyncEnabled;
    final encChanged = _pendingEncryptionEnabled != null &&
        _pendingEncryptionEnabled != _savedEncryptionEnabled;
    final unlockChanged = _unlockKey.currentState?.hasChanges ?? false;
    return app.locale.languageCode != _savedLang ||
        app.isDark != _savedDark ||
        syncChanged ||
        encChanged ||
        unlockChanged;
  }

  /// Called from MainShell when user navigates away from settings tab.
  /// Reverts all unsaved changes.
  void revertIfNeeded() {
    if (!_hasChanges) return;
    final app = context.read<AppState>();
    app.setLocale(Locale(_savedLang));
    app.setDarkMode(_savedDark);
    _pendingSyncEnabled = null;
    _pendingEncryptionEnabled = null;
    _unlockKey.currentState?.revertChanges();
    if (mounted) setState(() => _hasChanges = false);
  }

  /// Called from MainShell when user navigates TO settings tab.
  /// Re-captures the current saved state as the baseline.
  void onEnter() {
    final app = context.read<AppState>();
    _captureSnapshot(app);
    _unlockKey.currentState?.saveSnapshot();
    if (mounted) setState(() => _hasChanges = false);
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);

    // Apply sync change
    if (_pendingSyncEnabled != null && _pendingSyncEnabled != _savedSyncEnabled) {
      final sync = context.read<SyncService>();
      sync.setEnabled(_pendingSyncEnabled!);
    }

    // Apply encryption change
    if (_pendingEncryptionEnabled != null &&
        _pendingEncryptionEnabled != _savedEncryptionEnabled) {
      final auth = context.read<AuthService>();
      await _applyEncryptionChange(_pendingEncryptionEnabled!, app, auth, l);
    }

    // Apply unlock method change
    await _unlockKey.currentState?.commitChanges();

    // Current AppState IS the desired state (already applied live for lang/theme).
    // Just update our snapshot so "revert" becomes a no-op.
    _captureSnapshot(app);
    setState(() => _hasChanges = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.get('saved')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF00B8A9),
        duration: const Duration(milliseconds: 1400),
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
      ),
    );
  }

  void _cancel() {
    revertIfNeeded();
  }

  /// Apply a change immediately to AppState (live preview).
  void _applyLive(AppState app, VoidCallback change) {
    change();
    setState(() => _hasChanges = _checkChanges(app));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);

    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.get('settings_title')),
        actions: [
          if (!auth.isSignedIn)
            TextButton.icon(
              icon: const Icon(Icons.person_outline, size: 18),
              label: Text(l.get('auth_signin_btn')),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              },
            ),
          if (auth.isSignedIn)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) => _onMenuAction(v, app, auth, l),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'email',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, size: 20),
                    title: Text(auth.email ?? '—',
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      auth.isVerified
                          ? l.get('security_verified')
                          : l.get('security_not_verified'),
                      style: TextStyle(
                        fontSize: 11,
                        color: auth.isVerified
                            ? const Color(0xFF00B8A9)
                            : Colors.orangeAccent,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!auth.isVerified)
                  PopupMenuItem(
                    value: 'resend',
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.mark_email_unread_outlined, size: 20),
                      title: Text(l.get('auth_verify_resend'),
                          style: const TextStyle(fontSize: 13)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: 'reset_password',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.lock_reset, size: 20),
                    title: Text(l.get('security_reset_password'),
                        style: const TextStyle(fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.logout, size: 20,
                        color: Colors.redAccent),
                    title: Text(l.get('auth_signout'),
                        style: const TextStyle(
                            fontSize: 13, color: Colors.redAccent)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Language
                _sectionTitle(l.get('language')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: DropdownButtonFormField<String>(
                      value: app.locale.languageCode,
                      isExpanded: true,
                      decoration: const InputDecoration(border: InputBorder.none),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'ko', child: Text('한국어')),
                        DropdownMenuItem(value: 'ja', child: Text('日本語')),
                      ],
                      onChanged: (v) => _applyLive(app, () => app.setLocale(Locale(v!))),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Theme
                _sectionTitle(l.get('theme')),
                Card(
                  child: SwitchListTile(
                    title: Text(app.isDark ? l.get('dark_mode') : l.get('light_mode')),
                    secondary: Icon(app.isDark ? Icons.dark_mode : Icons.light_mode),
                    value: app.isDark,
                    onChanged: (v) => _applyLive(app, () => app.setDarkMode(v)),
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Data
                _sectionTitle(l.get('data_title')),
                _buildDataCard(l),
                const SizedBox(height: 16),

                // 5. About
                _sectionTitle(l.get('about')),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Labor Day Pay Calculator'),
                    subtitle: Text('${l.get('version')} 1.0.0'),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // Save / Cancel bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _hasChanges ? _cancel : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l.get('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _hasChanges ? _save : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l.get('save')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Data card — split behaviour:
  //   * signed in     → full cloud-sync controls
  //   * not signed in → read-only "Saved on this device" with a sign-in nudge
  Widget _buildDataCard(AppLocalizations l) {
    final auth = context.watch<AuthService>();
    if (!auth.isSignedIn) {
      return Card(
        child: Column(
          children: [
            // Cloud sync — disabled, needs sign-in.
            SwitchListTile(
              secondary: const Icon(Icons.cloud_off_outlined),
              title: Text(l.get('sync_enable')),
              subtitle: Text(
                l.get('data_cloud_off_sub'),
                style: const TextStyle(fontSize: 12),
              ),
              value: false,
              onChanged: null,
            ),
            const Divider(height: 1),
            // App lock — disabled, needs sign-in.
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: Text(l.get('security_enable')),
              subtitle: Text(
                l.get('data_encryption_off_sub'),
                style: const TextStyle(fontSize: 12),
              ),
              value: false,
              onChanged: null,
            ),
          ],
        ),
      );
    }
    // Signed in — show the full cloud-sync card.
    return _buildSyncCard(l);
  }

  // Sync card = cloud-sync toggle + app-lock toggle.
  // Changes are pending until user presses Save.
  Widget _buildSyncCard(AppLocalizations l) {
    final sync = context.watch<SyncService>();
    final app = context.watch<AppState>();
    final effectiveSync = _pendingSyncEnabled ?? sync.enabled;
    final effectiveEnc = _pendingEncryptionEnabled ?? app.encryptionEnabled;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(effectiveSync
                ? Icons.cloud_sync_outlined
                : Icons.phone_android),
            title: Text(l.get('sync_enable')),
            subtitle: Text(
              effectiveSync ? l.get('sync_on_sub') : l.get('sync_off_sub'),
              style: const TextStyle(fontSize: 12),
            ),
            value: effectiveSync,
            onChanged: (v) {
              setState(() {
                _pendingSyncEnabled = v;
                _hasChanges = _checkChanges(app);
              });
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(l.get('security_enable')),
            subtitle: Text(
              effectiveEnc
                  ? l.get('security_on_sub')
                  : l.get('security_off_sub'),
              style: const TextStyle(fontSize: 12),
            ),
            value: effectiveEnc,
            onChanged: (v) {
              setState(() {
                _pendingEncryptionEnabled = v;
                _hasChanges = _checkChanges(app);
              });
            },
          ),
          // Unlock-method picker is only meaningful when app-lock is on.
          // Hide it entirely when encryption is (or will be, after Save)
          // disabled — there's nothing to unlock.
          if (effectiveEnc) ...[
            const Divider(height: 1),
            _UnlockMethodTile(
              key: _unlockKey,
              onChanged: () {
                final app = context.read<AppState>();
                setState(() => _hasChanges = _checkChanges(app));
              },
            ),
          ],
        ],
      ),
    );
  }


  /// Handle AppBar dropdown menu actions.
  Future<void> _onMenuAction(
      String action, AppState app, AuthService auth, AppLocalizations l) async {
    switch (action) {
      case 'email':
        // No-op — just shows the email info.
        break;
      case 'resend':
        await auth.resendVerificationEmail();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.get('auth_verification_resent'))),
          );
        }
        break;
      case 'reset_password':
        final email = auth.email;
        if (email == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.get('security_reset_password')),
            content: Text(
                l.getWith('security_reset_confirm', {'email': email})),
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
        if (ok != true) return;
        await auth.sendPasswordResetEmail(email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.get('auth_reset_sent'))),
          );
        }
        break;
      case 'logout':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.get('auth_signout')),
            content: Text(l.get('logout_confirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.get('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.get('auth_signout')),
              ),
            ],
          ),
        );
        if (ok != true) return;
        final uid = auth.currentUser?.uid;
        final enc = context.read<EncryptionService>();
        enc.clearCache();
        if (uid != null) {
          await app.storage.swapToLocal(uid);
        }
        app.storage.lock();
        await auth.signOut();
        app.refreshRates();
        if (mounted) setState(() {});
        break;
    }
  }

  /// Actually apply encryption on/off — called from [_save].
  Future<void> _applyEncryptionChange(
      bool enable, AppState app, AuthService auth, AppLocalizations l) async {
    if (enable) {
      // Enabling requires an authenticated, verified user.
      if (!auth.isSignedIn || !auth.isVerified) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.get('security_enable')),
            content: Text(l.get('security_enable_notice')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.get('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.get('continue_label')),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          // User cancelled — revert the pending toggle.
          _pendingEncryptionEnabled = null;
          return;
        }
      }
      await app.setEncryptionEnabled(true);
      if (auth.isSignedIn && auth.isVerified) {
        final enc = context.read<EncryptionService>();
        await enc.loadOrCreateKey(auth.currentUser!.uid);
        await app.storage.migrateToEncrypted();
        app.storageUnlockedChanged();
      }
    } else {
      if (auth.isSignedIn && app.storage.isUnlocked) {
        await app.storage.migrateToPlaintext();
      }
      await app.setEncryptionEnabled(false);
      app.storageUnlockedChanged();
    }
    if (mounted) setState(() {});
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF00B8A9),
        ),
      ),
    );
  }

}

enum _UnlockMethod { password, pattern, fingerprint }

/// Three-way unlock-method picker. Exactly one of {password only, 9-dot
/// pattern, fingerprint} is active at a time.
/// Changes are pending until the parent calls [commitChanges].
class _UnlockMethodTile extends StatefulWidget {
  final VoidCallback? onChanged;
  const _UnlockMethodTile({super.key, this.onChanged});

  @override
  State<_UnlockMethodTile> createState() => _UnlockMethodTileState();
}

class _UnlockMethodTileState extends State<_UnlockMethodTile> {
  bool _loading = true;
  bool _bioSupported = false;
  _UnlockMethod _savedMethod = _UnlockMethod.password;
  _UnlockMethod _method = _UnlockMethod.password;
  List<int>? _pendingPatternDots;

  /// Whether pending state differs from saved state.
  bool get hasChanges =>
      _method != _savedMethod || _pendingPatternDots != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final pat = context.read<PatternService>();
    final bio = context.read<BiometricService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final supported = await bio.isDeviceSupported();
    final hasPattern = await pat.hasPattern(uid);
    final bioOn = await bio.isEnabled(uid);
    if (!mounted) return;
    setState(() {
      _bioSupported = supported;
      if (bioOn) {
        _method = _UnlockMethod.fingerprint;
      } else if (hasPattern) {
        _method = _UnlockMethod.pattern;
      } else {
        _method = _UnlockMethod.password;
      }
      _savedMethod = _method;
      _loading = false;
    });
  }

  /// Record saved snapshot (called by parent on enter).
  void saveSnapshot() {
    _savedMethod = _method;
    _pendingPatternDots = null;
  }

  /// Revert to saved state (called by parent on cancel).
  void revertChanges() {
    setState(() {
      _method = _savedMethod;
      _pendingPatternDots = null;
    });
  }

  /// Persist pending changes (called by parent on save).
  Future<void> commitChanges() async {
    if (!hasChanges) return;
    final auth = context.read<AuthService>();
    final pat = context.read<PatternService>();
    final bio = context.read<BiometricService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    switch (_method) {
      case _UnlockMethod.password:
        await pat.clearPattern(uid);
        await bio.setEnabled(uid, false);
        break;
      case _UnlockMethod.pattern:
        if (_pendingPatternDots != null) {
          await pat.setPattern(uid, _pendingPatternDots!);
        }
        await bio.setEnabled(uid, false);
        break;
      case _UnlockMethod.fingerprint:
        await pat.clearPattern(uid);
        await bio.setEnabled(uid, true);
        break;
    }
    _savedMethod = _method;
    _pendingPatternDots = null;
  }

  Future<void> _select(_UnlockMethod m) async {
    final bio = context.read<BiometricService>();
    final l = AppLocalizations.of(context);

    switch (m) {
      case _UnlockMethod.password:
        if (mounted) setState(() => _method = _UnlockMethod.password);
        _pendingPatternDots = null;
        widget.onChanged?.call();
        break;

      case _UnlockMethod.pattern:
        List<int>? capturedDots;
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PatternSetupScreen(
              onConfirm: (dots) async {
                capturedDots = dots;
              },
            ),
          ),
        );
        if (ok == true && capturedDots != null) {
          _pendingPatternDots = capturedDots;
          if (mounted) setState(() => _method = _UnlockMethod.pattern);
          widget.onChanged?.call();
        }
        break;

      case _UnlockMethod.fingerprint:
        if (!_bioSupported) return;
        final ok = await bio.authenticate(l.get('biometric_prompt'));
        if (!ok) return;
        _pendingPatternDots = null;
        if (mounted) setState(() => _method = _UnlockMethod.fingerprint);
        widget.onChanged?.call();
        break;
    }
  }

  Future<void> _changePattern() async {
    List<int>? capturedDots;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PatternSetupScreen(
          onConfirm: (dots) async {
            capturedDots = dots;
          },
        ),
      ),
    );
    if (ok == true && capturedDots != null) {
      _pendingPatternDots = capturedDots;
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.vpn_key_outlined, size: 20),
              const SizedBox(width: 12),
              Text(l.get('unlock_method'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        RadioListTile<_UnlockMethod>(
          dense: true,
          value: _UnlockMethod.password,
          groupValue: _method,
          onChanged: (v) => _select(_UnlockMethod.password),
          title: Text(l.get('unlock_method_password'),
              style: const TextStyle(fontSize: 14)),
          subtitle: Text(l.get('unlock_method_password_sub'),
              style: const TextStyle(fontSize: 12)),
        ),
        RadioListTile<_UnlockMethod>(
          dense: true,
          value: _UnlockMethod.pattern,
          groupValue: _method,
          onChanged: (v) => _select(_UnlockMethod.pattern),
          title: Text(l.get('unlock_method_pattern'),
              style: const TextStyle(fontSize: 14)),
          subtitle: Text(l.get('unlock_method_pattern_sub'),
              style: const TextStyle(fontSize: 12)),
          secondary: _method == _UnlockMethod.pattern
              ? IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: l.get('change'),
                  onPressed: _changePattern,
                )
              : null,
        ),
        RadioListTile<_UnlockMethod>(
          dense: true,
          value: _UnlockMethod.fingerprint,
          groupValue: _method,
          onChanged: _bioSupported ? (v) => _select(_UnlockMethod.fingerprint) : null,
          title: Text(l.get('unlock_method_fingerprint'),
              style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            _bioSupported
                ? l.get('unlock_method_fingerprint_sub')
                : l.get('biometric_not_supported'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// [Legacy — kept for reference, no longer shown in UI]
class _PatternTile extends StatefulWidget {
  @override
  State<_PatternTile> createState() => _PatternTileState();
}

class _PatternTileState extends State<_PatternTile> {
  bool _loading = true;
  bool _hasPattern = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final pat = context.read<PatternService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final has = await pat.hasPattern(uid);
    if (mounted) {
      setState(() {
        _hasPattern = has;
        _loading = false;
      });
    }
  }

  Future<void> _setup() async {
    final auth = context.read<AuthService>();
    final pat = context.read<PatternService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PatternSetupScreen(
          onConfirm: (dots) => pat.setPattern(uid, dots),
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _hasPattern = true);
    }
  }

  Future<void> _remove() async {
    final auth = context.read<AuthService>();
    final pat = context.read<PatternService>();
    final l = AppLocalizations.of(context);
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.get('pattern_remove_title')),
        content: Text(l.get('pattern_remove_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.get('cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.get('continue_label'))),
        ],
      ),
    );
    if (confirmed == true) {
      await pat.clearPattern(uid);
      if (mounted) setState(() => _hasPattern = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.grid_3x3, size: 20),
        title: Text('…'),
      );
    }
    return ListTile(
      leading: const Icon(Icons.grid_3x3, size: 20),
      title: Text(l.get('pattern_lock'), style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        _hasPattern ? l.get('pattern_enabled') : l.get('pattern_disabled'),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: _hasPattern
          ? TextButton(
              onPressed: _remove,
              child: Text(l.get('remove'),
                  style: const TextStyle(color: Colors.redAccent)),
            )
          : FilledButton(onPressed: _setup, child: Text(l.get('setup'))),
    );
  }
}

/// Biometric (fingerprint / face) enable toggle.
class _BiometricTile extends StatefulWidget {
  @override
  State<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends State<_BiometricTile> {
  bool _loading = true;
  bool _supported = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final bio = context.read<BiometricService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final supported = await bio.isDeviceSupported();
    final on = await bio.isEnabled(uid);
    if (mounted) {
      setState(() {
        _supported = supported;
        _enabled = on;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool v) async {
    final auth = context.read<AuthService>();
    final bio = context.read<BiometricService>();
    final l = AppLocalizations.of(context);
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    if (v) {
      // Prompt once to confirm the user can authenticate before flipping on.
      final ok = await bio.authenticate(l.get('biometric_prompt'));
      if (!ok) return;
    }
    await bio.setEnabled(uid, v);
    if (mounted) setState(() => _enabled = v);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.fingerprint, size: 20),
        title: Text('…'),
      );
    }
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: Text(l.get('biometric_unlock'),
          style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        _supported
            ? (_enabled
                ? l.get('biometric_enabled')
                : l.get('biometric_tap_to_enable'))
            : l.get('biometric_not_supported'),
        style: const TextStyle(fontSize: 12),
      ),
      value: _supported && _enabled,
      onChanged: _supported ? _toggle : null,
    );
  }
}
