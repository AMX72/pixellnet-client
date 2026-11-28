import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Показывается когда /api/trial вернул 410 Gone — пробный период уже был.
/// Дружественный UX вместо generic error (v0.1.48).
class TrialExpiredPage extends ConsumerWidget {
  const TrialExpiredPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    return Container(
      color: PixellnetBrand.bgScaffold,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: PixellnetBrand.accentBg,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.vpn_key_outlined,
                size: 40,
                color: PixellnetBrand.accent,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            t.ui.trial.expiredTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: PixellnetBrand.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t.ui.trial.expiredText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: PixellnetBrand.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 36),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PixellnetBrand.accent,
              foregroundColor: const Color(0xFF131314),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            onPressed: () {
              ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
            },
            child: Text(
              t.ui.trial.enterKey,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: PixellnetBrand.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              backgroundColor: PixellnetBrand.bgSurface,
            ),
            onPressed: () => launchUrl(
              Uri.parse('https://t.me/pixellnet_bot?start=renew'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              t.ui.trial.renew,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://t.me/pixellnet_bot'),
                mode: LaunchMode.externalApplication,
              ),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(color: PixellnetBrand.textMuted, fontSize: 13),
                  children: [
                    TextSpan(text: t.ui.trial.noKey),
                    const TextSpan(
                      text: '@pixellnet_bot',
                      style: TextStyle(
                        color: PixellnetBrand.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
