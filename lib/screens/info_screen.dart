import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'tax_rates_screen.dart';
import 'prices_screen.dart';


class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  static const _accent = Color(0xFF00B8A9);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isKo = l.locale.languageCode == 'ko';

    return Scaffold(
      appBar: AppBar(
        title: Text(isKo ? '정보' : 'Info'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          children: [
            _menuCard(
              context,
              icon: Icons.percent,
              iconColor: _accent,
              title: isKo ? '세율' : 'Tax Rates',
              subtitle: isKo ? '소득세, 보험' : 'Income tax, insurance',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TaxRatesScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _menuCard(
              context,
              icon: Icons.shopping_cart_outlined,
              iconColor: Colors.orange,
              title: isKo ? '물가' : 'Prices',
              subtitle: isKo ? '빅맥, 주거비, 재산세, 공과금' : 'Big Mac, housing, property tax, bills',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PricesScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: iconColor.withOpacity(0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 28, color: iconColor),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
