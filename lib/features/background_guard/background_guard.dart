// v0.1.101: «Чтобы PIXELLNET не отключался» (Android).
//
// Xiaomi/Redmi/POCO (MIUI/HyperOS) и другие прошивки ночью закрывают приложение,
// которое «тратит батарею» при выключенном экране (MIUI: ScreenOffCPUCheckKill, >2% CPU
// за 25 мин). Без «Автозапуска» защищённое соединение после этого не поднимается до утра
// (CHANGELOG 2026-11-21 part 42). Включить эти разрешения может только сам человек —
// приложение показывает шаги и открывает нужные экраны телефона одной кнопкой.
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/brand/pixellnet_brand.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _channel = MethodChannel('com.hiddify.app/platform');

/// «Напомнить завтра»: до этого момента (мс) баннер не показываем.
final bgGuardSnoozeUntil = PreferencesNotifier.create<int, int>('bg_guard_snooze_until', 0);

/// Сколько раз окно с шагами открывалось само и когда последний раз (мс).
/// Открывается само у новых и у обновившихся (настроек ещё нет), пока шаги не сделаны:
/// не чаще раза в 3 дня, не больше 3 раз — дальше только баннер.
final bgGuardAutoCount = PreferencesNotifier.create<int, int>('bg_guard_auto_count', 0);
final bgGuardAutoAt = PreferencesNotifier.create<int, int>('bg_guard_auto_at', 0);
const _autoMaxTimes = 3;
const _autoEvery = Duration(days: 3);

/// Человек открывал экран производителя (если прочитать его состояние нельзя).
final bgGuardOpenedAutostart = PreferencesNotifier.create<bool, bool>('bg_guard_opened_autostart', false);

/// Xiaomi: человек открывал «Контроль активности» и вернулся. «Нет ограничений» в MIUI не всегда
/// попадает в системный список исключений батареи (тест 2026-11-21: в одном прогоне попал,
/// в другом — нет), поэтому одного isIgnoringBatteryOptimizations для Xiaomi мало.
final bgGuardOpenedBattery = PreferencesNotifier.create<bool, bool>('bg_guard_opened_battery', false);

class BackgroundStatus {
  const BackgroundStatus({required this.oem, required this.batteryOk, required this.autostart});

  /// xiaomi / huawei / honor / samsung / oppo / vivo / other
  final String oem;

  /// Приложение исключено из оптимизации батареи Android.
  final bool batteryOk;

  /// MIUI «Автозапуск»: allowed / denied / unknown.
  final String autostart;

  factory BackgroundStatus.fromJson(Map<String, dynamic> j) => BackgroundStatus(
        oem: (j['oem'] as String?) ?? 'other',
        batteryOk: (j['battery_ok'] as bool?) ?? false,
        autostart: (j['autostart'] as String?) ?? 'unknown',
      );
}

final backgroundStatusProvider = FutureProvider.autoDispose<BackgroundStatus?>((ref) async {
  if (!Platform.isAndroid) return null;
  try {
    final raw = await _channel.invokeMethod<String>('background_status');
    if (raw == null) return null;
    return BackgroundStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

enum _Action { requestBattery, openAutostart }

class _Step {
  const _Step({required this.title, required this.hint, required this.done, required this.button, required this.action});
  final String title;
  final String hint;
  final bool done;
  final String button;
  final _Action action;
}

List<_Step> _stepsFor(BackgroundStatus s, {required bool openedAutostart, required bool openedBattery}) {
  // Xiaomi (MIUI/HyperOS): системный запрос «работа в фоне» открывает экран MIUI
  // «Контроль фоновой активности» (проверено на POCO M3 Pro, MIUI 14, 2026-11-21).
  // Автозапуск читается через AppOps 10008.
  final xiaomi = s.oem == 'xiaomi';
  return [
    _Step(
      title: xiaomi ? 'Контроль активности' : 'Работа в фоне',
      hint: xiaomi ? 'Выберите «Нет ограничений»' : 'В окне телефона нажмите «Разрешить»',
      done: s.batteryOk || (xiaomi && openedBattery),
      button: xiaomi ? 'Открыть' : 'Разрешить',
      action: _Action.requestBattery,
    ),
    if (xiaomi)
      _Step(
        title: 'Автозапуск',
        hint: 'Найдите PIXELLNET (можно через поиск) и включите переключатель',
        done: s.autostart == 'allowed' || (s.autostart == 'unknown' && openedAutostart),
        button: 'Открыть',
        action: _Action.openAutostart,
      ),
    if (s.oem == 'huawei' || s.oem == 'honor')
      _Step(
        title: 'Запуск приложений',
        hint: 'У PIXELLNET выключите «Автоматически» и включите все переключатели',
        done: openedAutostart,
        button: 'Открыть',
        action: _Action.openAutostart,
      ),
    if (s.oem == 'oppo')
      _Step(
        title: 'Автозапуск',
        hint: 'Включите переключатель у PIXELLNET',
        done: openedAutostart,
        button: 'Открыть',
        action: _Action.openAutostart,
      ),
    if (s.oem == 'vivo')
      _Step(
        title: 'Работа в фоне',
        hint: 'Разрешите PIXELLNET работать в фоне',
        done: openedAutostart,
        button: 'Открыть',
        action: _Action.openAutostart,
      ),
  ];
}

/// true — остались невыполненные шаги.
final backgroundGuardNeedsSetupProvider = Provider.autoDispose<bool>((ref) {
  final s = ref.watch(backgroundStatusProvider).valueOrNull;
  if (s == null) return false;
  final steps = _stepsFor(
    s,
    openedAutostart: ref.watch(bgGuardOpenedAutostart),
    openedBattery: ref.watch(bgGuardOpenedBattery),
  );
  return steps.any((e) => !e.done);
});

/// После возврата с экрана телефона MIUI записывает настройку с небольшой задержкой —
/// перечитываем статус сразу и ещё раз через 1,5 с.
void _refreshStatus(WidgetRef ref) {
  ref.invalidate(backgroundStatusProvider);
  Future<void>.delayed(const Duration(milliseconds: 1500), () {
    try {
      ref.invalidate(backgroundStatusProvider);
    } catch (_) {
      // виджет уже закрыт
    }
  });
}

Future<void> showBackgroundGuardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _BackgroundGuardSheet(),
  );
}

/// Баннер на главном экране: виден, пока остались шаги; крестик — «напомнить завтра».
/// После первого подключения один раз сам открывает окно с шагами.
class BackgroundGuardBanner extends ConsumerStatefulWidget {
  const BackgroundGuardBanner({super.key});

  @override
  ConsumerState<BackgroundGuardBanner> createState() => _BackgroundGuardBannerState();
}

class _BackgroundGuardBannerState extends ConsumerState<BackgroundGuardBanner> with WidgetsBindingObserver {
  bool _autoOpening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus(ref);
  }

  Future<void> _autoOpen() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _autoOpening = false; // поверх открыто другое окно — попробуем при следующей перерисовке
      return;
    }
    await ref.read(bgGuardAutoCount.notifier).update(ref.read(bgGuardAutoCount) + 1);
    await ref.read(bgGuardAutoAt.notifier).update(DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    await showBackgroundGuardSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    if (!ref.watch(backgroundGuardNeedsSetupProvider)) return const SizedBox.shrink();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < ref.watch(bgGuardSnoozeUntil)) return const SizedBox.shrink();

    // Само открываем, только когда защита реально работает (канал ответил на проверку):
    // сразу после запуска ядро сообщает «подключено» ещё без ключа (β 2026-11-21).
    final delay = ref.watch(activeProxyNotifierProvider).valueOrNull?.urlTestDelay ?? 0;
    final working = ref.watch(serviceRunningProvider) && delay > 0 && delay < 65000;
    final count = ref.watch(bgGuardAutoCount);
    final due = count == 0 || now - ref.watch(bgGuardAutoAt) > _autoEvery.inMilliseconds;
    if (!_autoOpening && working && count < _autoMaxTimes && due) {
      _autoOpening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpen());
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: PixellnetBrand.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showBackgroundGuardSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.battery_alert_outlined, color: theme.colorScheme.onSurface, size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    'PIXELLNET может отключаться ночью',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('Настроить', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close_outlined, size: 18),
                  color: theme.colorScheme.onSurfaceVariant,
                  tooltip: 'Напомнить завтра',
                  onPressed: () => ref
                      .read(bgGuardSnoozeUntil.notifier)
                      .update(DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundGuardSheet extends ConsumerStatefulWidget {
  const _BackgroundGuardSheet();

  @override
  ConsumerState<_BackgroundGuardSheet> createState() => _BackgroundGuardSheetState();
}

class _BackgroundGuardSheetState extends ConsumerState<_BackgroundGuardSheet> with WidgetsBindingObserver {
  _Action? _pending; // какой экран телефона открыли — отметим по возвращении

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final p = _pending;
    _pending = null;
    if (p == _Action.openAutostart) ref.read(bgGuardOpenedAutostart.notifier).update(true);
    _refreshStatus(ref);
  }

  Future<void> _run(_Action a) async {
    try {
      switch (a) {
        case _Action.requestBattery:
          await _channel.invokeMethod<bool>('request_ignore_battery_optimizations');
          if (!mounted) return;
          await ref.read(bgGuardOpenedBattery.notifier).update(true);
          if (mounted) _refreshStatus(ref);
        case _Action.openAutostart:
          _pending = a;
          await _channel.invokeMethod<bool>('open_background_settings', {'kind': 'autostart'});
      }
    } catch (_) {
      // экран не открылся — шаг останется невыполненным, человек увидит его снова
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(backgroundStatusProvider).valueOrNull;
    final steps = status == null
        ? const <_Step>[]
        : _stepsFor(
            status,
            openedAutostart: ref.watch(bgGuardOpenedAutostart),
            openedBattery: ref.watch(bgGuardOpenedBattery),
          );
    final allDone = steps.isNotEmpty && steps.every((s) => s.done);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Чтобы PIXELLNET не отключался', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Gap(6),
            Text(
              allDone
                  ? 'Готово. Телефон больше не будет закрывать PIXELLNET ради экономии батареи.'
                  : 'Телефон экономит батарею и может закрыть PIXELLNET ночью — утром защита окажется выключенной. '
                      'Разрешите работу в фоне, это займёт минуту.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Gap(16),
            for (var i = 0; i < steps.length; i++) ...[
              _StepRow(index: i + 1, step: steps[i], onPressed: () => _run(steps[i].action)),
              if (i != steps.length - 1) const Gap(12),
            ],
            const Gap(20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(allDone ? 'Готово' : 'Закрыть'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step, required this.onPressed});
  final int index;
  final _Step step;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: step.done
              ? const Icon(Icons.check_circle, color: PixellnetBrand.success, size: 24)
              : CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text('$index', style: theme.textTheme.labelMedium),
                ),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              Text(
                step.done ? 'Готово' : step.hint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Gap(8),
        if (!step.done) OutlinedButton(onPressed: onPressed, child: Text(step.button)),
      ],
    );
  }
}
