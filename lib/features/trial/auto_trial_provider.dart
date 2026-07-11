import 'package:hiddify/features/diagnostics/diagnostics_service.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/trial/trial_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Zero-config auto-trial.
///
/// При первом обращении:
/// 1. Проверяет — есть ли активный профиль (юзер сам импортировал раньше).
/// 2. Если нет — вызывает `TrialService.obtainTrial()` через pixellnet-api.
/// 3. Импортирует полученный `sub_url` через `ProfileRepository.upsertRemote()`.
/// 4. Возвращает [TrialInfo] в качестве data.
///
/// UI (HomePage) слушает этот провайдер и показывает splash пока идёт запрос,
/// либо кнопку Retry при ошибке.
final autoTrialProvider = FutureProvider<TrialInfo?>((ref) async {
  final hasProfile = await ref.watch(hasAnyProfileProvider.future);
  if (hasProfile) {
    return null;
  }

  DiagnosticsService.instance.event('auto_trial.start');

  final cached = await TrialService.instance.loadCached();
  final TrialInfo info;
  if (cached != null && !cached.isExpired) {
    info = cached;
    DiagnosticsService.instance.event('auto_trial.cached', {'days_left': info.daysLeft});
  } else {
    info = await TrialService.instance.obtainTrial();
  }

  final repo = await ref.read(profileRepositoryProvider.future);
  final result = await repo.upsertRemote(info.subscriptionUrl).run();
  result.fold(
    (failure) {
      DiagnosticsService.instance.event('auto_trial.import_failed', {'error': failure.toString()});
      throw TrialException('Не удалось добавить профиль: $failure');
    },
    (_) {
      DiagnosticsService.instance.event('auto_trial.imported');
    },
  );

  return info;
});
