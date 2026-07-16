import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:share_plus/share_plus.dart';

/// Second-level sheet — превью + 3 кнопки (Отправить / QR / Скопировать).
class ShareActionSheet extends StatelessWidget {
  const ShareActionSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryLink,
    required this.qrPayload,
    required this.messengerPreamble,
    required this.profileName,
  });

  final String title;
  final String subtitle;
  final String primaryLink;
  final String qrPayload;
  final String messengerPreamble;
  final String profileName;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String primaryLink,
    required String qrPayload,
    required String messengerPreamble,
    required String profileName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShareActionSheet(
        title: title,
        subtitle: subtitle,
        primaryLink: primaryLink,
        qrPayload: qrPayload,
        messengerPreamble: messengerPreamble,
        profileName: profileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = primaryLink.length > 44 ? '${primaryLink.substring(0, 44)}…' : primaryLink;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 20),

            // Превью ссылки
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Primary — Отправить через мессенджер
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await Share.share(
                  '$messengerPreamble\n\n$primaryLink',
                  subject: profileName.isNotEmpty ? profileName : 'PIXELLNET VPN',
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: PixellnetBrand.mocha,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: const Text('Отправить через мессенджер', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),

            // Secondary — Показать QR
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(child: QrCodeDialog(qrPayload)),
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

            // Text button — Скопировать
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: primaryLink));
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ссылка скопирована'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Скопировать ссылку'),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Ссылка действует до окончания вашей подписки',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
