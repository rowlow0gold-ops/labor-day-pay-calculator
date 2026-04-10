import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../services/firestore_tax_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  // "Saved" snapshot — what was persisted before entering settings
  late String _savedLang;
  late bool _savedDark;

  bool _hasChanges = false;
  bool _initialized = false;

  void _captureSnapshot(AppState app) {
    _savedLang = app.locale.languageCode;
    _savedDark = app.isDark;
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
    return app.locale.languageCode != _savedLang ||
        app.isDark != _savedDark;
  }

  /// Called from MainShell when user navigates away from settings tab.
  /// Reverts all unsaved changes.
  void revertIfNeeded() {
    if (!_hasChanges) return;
    final app = context.read<AppState>();
    app.setLocale(Locale(_savedLang));
    app.setDarkMode(_savedDark);
    if (mounted) setState(() => _hasChanges = false);
  }

  /// Called from MainShell when user navigates TO settings tab.
  /// Re-captures the current saved state as the baseline.
  void onEnter() {
    final app = context.read<AppState>();
    _captureSnapshot(app);
    if (mounted) setState(() => _hasChanges = false);
  }

  void _save() {
    final app = context.read<AppState>();
    // Current AppState IS the desired state (already applied live).
    // Just update our snapshot so "revert" becomes a no-op.
    _captureSnapshot(app);
    setState(() => _hasChanges = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).get('save')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF00B8A9),
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
    final ts = context.read<FirestoreTaxService>();
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.get('settings_title'))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Language
                _sectionTitle(l.get('language')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: DropdownButtonFormField<String>(
                      value: app.locale.languageCode,
                      isExpanded: true,
                      decoration: const InputDecoration(border: InputBorder.none),
                      items: const [
                        DropdownMenuItem(value: 'ko', child: Text('한국어')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (v) => _applyLive(app, () => app.setLocale(Locale(v!))),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Theme
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

                // Tax Data Sync
                _sectionTitle('Tax Data'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.cloud_sync_outlined),
                        title: const Text('Sync Tax Rates'),
                        subtitle: Text(ts.lastUpdated != null
                            ? 'Updated: ${ts.lastUpdated!.toLocal().toString().substring(0, 16)}'
                            : 'Using local defaults'),
                        trailing: const Icon(Icons.refresh),
                        onTap: () async {
                          await ts.refresh();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Tax rates updated')),
                            );
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.upload_outlined),
                        title: const Text('Seed Firestore'),
                        subtitle: const Text('Upload default data (admin only)'),
                        onTap: () async {
                          await ts.seedFirestore();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Firestore seeded with default data')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // About
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
