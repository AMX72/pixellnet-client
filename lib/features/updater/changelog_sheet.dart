import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';

/// v0.1.28: bottom-sheet с changelog по категориям.
///
/// Парсит raw changelog (markdown с secциями) в три бакета:
/// - «Новое» (### Новое / ### New / feat:)
/// - «Починили» (### Исправлено / ### Fixed / fix:)
/// - «Стало лучше» (### Улучшено / ### Improved / perf: / refactor:)
///
/// Если категорий нет — fallback на raw text первые 500 символов.
class ChangelogSheet extends StatelessWidget {
  const ChangelogSheet({
    super.key,
    required this.version,
    required this.rawChangelog,
    this.showUpdateButton = false,
    this.onUpdatePressed,
  });

  final String version;
  final String rawChangelog;
  final bool showUpdateButton;
  final VoidCallback? onUpdatePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parseChangelog(rawChangelog);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Что нового в $version',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const Gap(4),
            Text('Расскажем главное',
                style: theme.textTheme.bodySmall?.copyWith(color: PixellnetBrand.textSecondary)),
            const Gap(20),

            if (parsed.isEmpty)
              _fallbackText(theme, rawChangelog)
            else ...[
              if (parsed['new']?.isNotEmpty ?? false) ...[
                _section(theme, 'Новое', Icons.auto_awesome_rounded, PixellnetBrand.mocha, parsed['new']!),
                const Gap(16),
              ],
              if (parsed['fixed']?.isNotEmpty ?? false) ...[
                _section(theme, 'Починили', Icons.build_rounded, PixellnetBrand.olive, parsed['fixed']!),
                const Gap(16),
              ],
              if (parsed['improved']?.isNotEmpty ?? false) ...[
                _section(theme, 'Стало лучше', Icons.trending_up_rounded, PixellnetBrand.blue, parsed['improved']!),
                const Gap(16),
              ],
            ],

            const Gap(4),
            if (showUpdateButton && onUpdatePressed != null)
              FilledButton.icon(
                icon: const Icon(Icons.system_update_rounded, size: 18),
                label: const Text('Обновить'),
                onPressed: onUpdatePressed,
              )
            else
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title, IconData icon, Color color, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const Gap(10),
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const Gap(8),
        for (final item in items.take(5)) ...[
          Padding(
            padding: const EdgeInsets.only(left: 42, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(item, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _fallbackText(ThemeData theme, String raw) {
    // v0.1.32: markdown в GH release body — фильтруем ** обёртку
    // и не показываем «Full Changelog: ...» (юзеру ссылка не нужна).
    final seen = <String>{};
    final cleaned = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) =>
            !l.toLowerCase().replaceAll('*', '').startsWith('full changelog'))
        .where(seen.add) // dedupe
        .take(8)
        .join('\n');
    return Text(
      cleaned.isEmpty ? 'Много мелких улучшений и стабильность.' : cleaned,
      style: theme.textTheme.bodyMedium,
    );
  }

  /// Парсер changelog: возвращает Map с ключами 'new', 'fixed', 'improved'.
  /// Читает markdown секции с русскими или английскими заголовками, плюс
  /// commit-conventional префиксы (feat:/fix:/perf:) из git log body.
  static Map<String, List<String>> _parseChangelog(String raw) {
    if (raw.trim().isEmpty) return {};

    final result = <String, List<String>>{'new': [], 'fixed': [], 'improved': []};
    String? currentBucket;

    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Markdown header — переключение бакета
      final lower = line.toLowerCase();
      if (lower.startsWith('#')) {
        if (lower.contains('нов') || lower.contains('new') || lower.contains('feature')) {
          currentBucket = 'new';
        } else if (lower.contains('починил') || lower.contains('исправ') || lower.contains('fix') || lower.contains('bug')) {
          currentBucket = 'fixed';
        } else if (lower.contains('улучш') || lower.contains('стало лучше') || lower.contains('improv') || lower.contains('perf')) {
          currentBucket = 'improved';
        } else {
          currentBucket = null;
        }
        continue;
      }

      // Conventional commits (feat:/fix:/perf:) — авто-классификация
      String? bucket = currentBucket;
      String content = line;
      if (line.startsWith('feat:') || line.startsWith('feat(')) {
        bucket = 'new';
        content = line.replaceFirst(RegExp(r'^feat[:(].*?[)]?:?\s*'), '');
      } else if (line.startsWith('fix:') || line.startsWith('fix(')) {
        bucket = 'fixed';
        content = line.replaceFirst(RegExp(r'^fix[:(].*?[)]?:?\s*'), '');
      } else if (line.startsWith('perf:') || line.startsWith('refactor:')) {
        bucket = 'improved';
        content = line.replaceFirst(RegExp(r'^(perf|refactor)[:(].*?[)]?:?\s*'), '');
      }

      if (bucket == null) continue;

      // Убираем bullet-маркеры и markdown-мусор
      content = content
          .replaceFirst(RegExp(r'^[-*+]\s+'), '')
          .replaceAll(RegExp(r'\*\*|\*|_|`'), '')
          .trim();

      if (content.isEmpty) continue;
      // Фильтруем технический мусор
      if (content.toLowerCase().startsWith('co-authored-by') ||
          content.toLowerCase().startsWith('bump ') ||
          content.toLowerCase().startsWith('ci:')) continue;
      // Обрезаем слишком длинные строки
      if (content.length > 120) content = '${content.substring(0, 117)}…';

      result[bucket]!.add(content);
    }

    // Убираем пустые бакеты
    result.removeWhere((_, v) => v.isEmpty);
    return result;
  }
}
