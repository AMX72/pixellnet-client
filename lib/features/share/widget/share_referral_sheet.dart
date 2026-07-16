import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/share/data/referral_api_service.dart';
import 'package:share_plus/share_plus.dart';

/// Реферальный share sheet — «Пригласить друга и получить бонус».
/// v0.1.46+: тянет real ref-код из /api/referral/my через ReferralApiService.
/// Fallback: если API недоступен — детерминистичный код из имени профиля.
class ShareReferralSheet extends StatefulWidget {
  const ShareReferralSheet({
    super.key,
    required this.profileName,
  });

  final String profileName;

  static Future<void> show(BuildContext context, {required String profileName}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShareReferralSheet(profileName: profileName),
    );
  }

  @override
  State<ShareReferralSheet> createState() => _ShareReferralSheetState();
}

class _ShareReferralSheetState extends State<ShareReferralSheet> {
  ReferralProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final p = await ReferralApiService.instance.fetchMyProfile();
    if (!mounted) return;
    setState(() {
      _profile = p ?? _fallbackProfile(widget.profileName);
      _loading = false;
    });
  }

  ReferralProfile _fallbackProfile(String name) {
    // Fallback код — 5 симв из hash имени. Не для реального attribution,
    // только чтобы UI не показывал пусто когда API недоступен.
    final base = name.isNotEmpty ? name : 'PIXELLNET';
    final hash = base.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0xFFFFFF);
    const chars = '0123456789ABCDEFGHJKMNPQRSTUVWXYZ';
    var n = hash;
    final buf = StringBuffer();
    for (var i = 0; i < 5; i++) {
      buf.write(chars[n % chars.length]);
      n = n ~/ chars.length;
    }
    final code = buf.toString();
    final link = 'https://pixellnet.com/i/$code';
    return ReferralProfile(
      refCode: code,
      refLink: link,
      inviteText: 'Пользуюсь PIXELLNET — быстрый VPN. Держи 7 дней бесплатно: $link',
      referralsConfirmed: 0,
      referralsPending: 0,
      bonusDaysEarned: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile!;
    final hasBonus = profile.bonusDaysEarned > 0 || profile.referralsConfirmed > 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: PixellnetBrand.olive.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.card_giftcard_rounded, size: 40, color: PixellnetBrand.olive),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Дарите 7 дней — получайте 7 дней',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Друг переходит по вашей ссылке и получает 7 дней бесплатно. '
                'Как только он оплатит подписку — вы тоже получаете 7 дней бесплатно.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Ref-код + ссылка
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Ваш код:',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      SelectableText(
                        profile.refCode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: PixellnetBrand.mocha,
                          letterSpacing: 1,
                        ),
                      ),
                      if (hasBonus) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: PixellnetBrand.olive.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+${profile.bonusDaysEarned} дн',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: PixellnetBrand.olive,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    profile.refLink,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                  if (profile.referralsConfirmed > 0 || profile.referralsPending > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Подтверждено: ${profile.referralsConfirmed} · ждём оплату: ${profile.referralsPending}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Primary — отправить приглашение
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await Share.share(profile.inviteText, subject: 'PIXELLNET — 7 дней бесплатно');
              },
              style: FilledButton.styleFrom(
                backgroundColor: PixellnetBrand.olive,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: const Text('Отправить приглашение', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),

            // Secondary — QR
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(child: QrCodeDialog(profile.refLink)),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: theme.colorScheme.outline),
              ),
              icon: const Icon(Icons.qr_code_2_rounded, size: 20),
              label: const Text('Показать QR-код', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 4),

            // Copy
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: profile.refLink));
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ссылка приглашения скопирована'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Скопировать ссылку'),
            ),
          ],
        ),
      ),
    );
  }
}
