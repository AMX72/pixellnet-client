import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:share_plus/share_plus.dart';

/// Реферальный share sheet — «Пригласить друга и получить бонус».
/// MVP: временный код-заглушка + ссылка pixellnet.com/i/{code}.
/// В v0.1.45+ подтягивать код из pixellnet-api /api/referral/my.
class ShareReferralSheet extends StatelessWidget {
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

  /// Временный ref-код — детерминированный из имени профиля.
  /// В v0.1.45 будет заменён на реальный код с pixellnet-api.
  String get _refCode {
    // 6 символов из хэша имени. Если профиль пустой — случайный.
    final base = profileName.isNotEmpty ? profileName : 'PIXELLNET';
    final hash = base.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0xFFFFFF);
    const chars = '0123456789ABCDEFGHJKMNPQRSTUVWXYZ'; // без I/L/O — читаемо
    var n = hash;
    final buf = StringBuffer();
    for (var i = 0; i < 5; i++) {
      buf.write(chars[n % chars.length]);
      n = n ~/ chars.length;
    }
    return buf.toString();
  }

  String get _refLink => 'https://pixellnet.com/i/$_refCode';

  String get _messengerText =>
      'Пользуюсь PIXELLNET — быстрый VPN без танцев с бубном. Держи 7 дней бесплатно: $_refLink';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            // Илюстрация — крупная иконка подарка
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: PixellnetBrand.olive.withOpacity(0.14),
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

            // Ref-код + ссылка (long-tap to copy code)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
                        _refCode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: PixellnetBrand.mocha,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _refLink,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Primary — отправить приглашение
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await Share.share(_messengerText, subject: 'PIXELLNET — 7 дней бесплатно');
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
                  builder: (_) => Dialog(child: QrCodeDialog(_refLink)),
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
                await Clipboard.setData(ClipboardData(text: _refLink));
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
