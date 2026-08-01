import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
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
    return Container(
      color: theme.scaffoldBackgroundColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          const Center(
            child: Icon(
              Icons.vpn_key_outlined,
              size: 72,
              color: PixellnetBrand.mocha,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Пробный период уже\nбыл использован',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'На это устройство мы уже выдавали бесплатные 7 дней. '
            'Чтобы продолжить — введите платный ключ.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PixellnetBrand.mocha,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
            },
            child: const Text(
              'Ввести ключ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: PixellnetBrand.mocha, width: 1.5),
              foregroundColor: PixellnetBrand.mocha,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => launchUrl(
              Uri.parse('https://pixellnet.com/pricing'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text(
              'Купить подписку',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                  children: const [
                    TextSpan(text: 'Нет ключа? Напишите '),
                    TextSpan(
                      text: '@pixellnet_bot',
                      style: TextStyle(
                        color: PixellnetBrand.olive,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: ' — поможем купить'),
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
