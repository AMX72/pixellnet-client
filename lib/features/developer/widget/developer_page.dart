import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/features/diagnostics/diagnostics_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Developer / Advanced screen — diagnostics, logs, config export, device info.
/// Reached from home → «Для разработчика».
class DeveloperPage extends ConsumerStatefulWidget {
  const DeveloperPage({super.key});

  @override
  ConsumerState<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends ConsumerState<DeveloperPage> {
  bool _collectingDiag = false;

  Future<void> _copyDiagnostics() async {
    setState(() => _collectingDiag = true);
    try {
      final snapshot = await DiagnosticsService.instance.collect();
      final md = DiagnosticsService.instance.formatAsMarkdown(snapshot);
      await Clipboard.setData(ClipboardData(text: md));
      if (!mounted) return;
      _toast('Отчёт скопирован — вставьте в чат поддержки');
    } catch (e) {
      if (!mounted) return;
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _collectingDiag = false);
    }
  }

  Future<void> _shareDiagnostics() async {
    setState(() => _collectingDiag = true);
    try {
      final snapshot = await DiagnosticsService.instance.collect();
      final md = DiagnosticsService.instance.formatAsMarkdown(snapshot);
      await Share.share(md, subject: 'PIXELLNET diagnostics');
    } catch (e) {
      if (!mounted) return;
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _collectingDiag = false);
    }
  }

  Future<void> _copyDeviceId() async {
    try {
      final snap = await DiagnosticsService.instance.collect(includeIpLookup: false);
      final device = snap['device'] as Map<String, dynamic>? ?? {};
      final id = '${device['os']} ${device['model'] ?? device['product_name'] ?? ''} '
          '${device['os_version'] ?? device['release'] ?? ''}';
      await Clipboard.setData(ClipboardData(text: id.trim()));
      if (!mounted) return;
      _toast('Устройство скопировано');
    } catch (_) {}
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appInfo = ref.watch(appInfoProvider).valueOrNull;
    final version = appInfo?.presentVersion ?? '—';

    return Scaffold(
      backgroundColor: PixellnetBrand.bgScaffold,
      appBar: AppBar(
        backgroundColor: PixellnetBrand.bgScaffold,
        elevation: 0,
        title: const Text('Для разработчика', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          _Section('О приложении'),
          _InfoRow('Версия', version),
          _InfoRow('Пакет', 'pixellnet.net'),
          _InfoRow('Платформа', _platformLabel()),

          const SizedBox(height: 16),
          _Section('Диагностика'),
          _ActionRow(
            icon: Icons.article_outlined,
            label: 'Логи sing-box',
            onTap: () => context.pushNamed('logs'),
          ),
          _ActionRow(
            icon: Icons.content_copy_outlined,
            label: _collectingDiag ? 'Собираем…' : 'Скопировать отчёт',
            subtitle: 'OS, версия, провайдер, последние события',
            onTap: _collectingDiag ? null : _copyDiagnostics,
          ),
          _ActionRow(
            icon: Icons.share_outlined,
            label: 'Поделиться отчётом',
            onTap: _collectingDiag ? null : _shareDiagnostics,
          ),
          _ActionRow(
            icon: Icons.phone_android_outlined,
            label: 'Скопировать устройство',
            onTap: _copyDeviceId,
          ),

          const SizedBox(height: 16),
          _Section('Прочее'),
          _ActionRow(
            icon: Icons.info_outline,
            label: 'О программе',
            onTap: () => context.pushNamed('about'),
          ),
        ],
      ),
    );
  }

  String _platformLabel() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: PixellnetBrand.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: PixellnetBrand.textPrimary, fontSize: 14)),
          ),
          Text(value, style: const TextStyle(color: PixellnetBrand.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final fg = disabled ? PixellnetBrand.textMuted : PixellnetBrand.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: fg, fontSize: 14)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(color: PixellnetBrand.textMuted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (!disabled)
              const Icon(Icons.chevron_right_outlined, size: 18, color: PixellnetBrand.textMuted),
          ],
        ),
      ),
    );
  }
}
