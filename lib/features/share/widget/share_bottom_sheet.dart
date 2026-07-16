import 'package:flutter/material.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/share/widget/share_action_sheet.dart';
import 'package:hiddify/features/share/widget/share_referral_sheet.dart';
import 'package:hiddify/utils/link_parsers.dart';

/// Bottom sheet «Что отправить?» — 3 плитки Warm Row (v0.1.44).
/// Show via: ShareBottomSheet.show(context, subUrl: url, profileName: name).
class ShareBottomSheet extends StatelessWidget {
  const ShareBottomSheet({
    super.key,
    required this.subUrl,
    required this.profileName,
  });

  final String subUrl;
  final String profileName;

  static Future<void> show(
    BuildContext context, {
    required String subUrl,
    required String profileName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShareBottomSheet(subUrl: subUrl, profileName: profileName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text('Что отправить?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Выберите, что нужно другу',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 20),
            _ShareRow(
              icon: Icons.vpn_key_rounded,
              iconColor: PixellnetBrand.mochaOnDark,
              iconBg: PixellnetBrand.mocha.withOpacity(0.12),
              title: 'Ключ для другого VPN-приложения',
              subtitle: 'Если у друга уже стоит Happ, V2rayNG — отправьте только ключ',
              onTap: () {
                Navigator.of(context).pop();
                _openShareForExternal(context);
              },
            ),
            const SizedBox(height: 8),
            _ShareRow(
              icon: Icons.shield_moon_rounded,
              iconColor: PixellnetBrand.mocha,
              iconBg: PixellnetBrand.mocha.withOpacity(0.16),
              title: 'Ключ для PIXELLNET',
              subtitle: 'Откроется прямо в приложении PIXELLNET у получателя',
              trailingBadge: const _RecommendedBadge(),
              onTap: () {
                Navigator.of(context).pop();
                _openShareForPixellnet(context);
              },
            ),
            const SizedBox(height: 8),
            _ShareRow(
              icon: Icons.card_giftcard_rounded,
              iconColor: PixellnetBrand.olive,
              iconBg: PixellnetBrand.olive.withOpacity(0.14),
              title: 'Пригласить друга и получить бонус',
              subtitle: 'За каждого друга — 7 дней бесплатно вам обоим',
              onTap: () {
                Navigator.of(context).pop();
                ShareReferralSheet.show(context, profileName: profileName);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openShareForExternal(BuildContext context) {
    // Плитка 1: универсальная ссылка (HTTPS). Happ автодетект по буферу.
    // Плюс поддерживаем deep-links для Hiddify/Karing/V2rayNG/Shadowrocket.
    ShareActionSheet.show(
      context,
      title: 'Ключ для другого VPN',
      subtitle: 'Получатель откроет ссылку в своём приложении',
      primaryLink: subUrl,
      qrPayload: subUrl,
      messengerPreamble:
          'Держи ключ для VPN — вставь ссылку в Happ / V2rayNG / любой Xray-клиент. Работает без блокировок:',
      profileName: profileName,
    );
  }

  void _openShareForPixellnet(BuildContext context) {
    // Плитка 2: deep-link pixellnet://import?url=...
    final deepLink = LinkParser.generatePixellnetDeepLink(subUrl, profileName);
    ShareActionSheet.show(
      context,
      title: 'Ключ для PIXELLNET',
      subtitle: 'Откроется прямо в приложении PIXELLNET',
      primaryLink: deepLink,
      qrPayload: deepLink,
      messengerPreamble:
          'Скачай PIXELLNET (pixellnet.com) и открой эту ссылку — все каналы подключатся автоматически:',
      profileName: profileName,
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingBadge,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 24, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (trailingBadge != null) ...[
                          const SizedBox(width: 6),
                          trailingBadge!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PixellnetBrand.olive.withOpacity(0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Советуем',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: PixellnetBrand.olive,
        ),
      ),
    );
  }
}
