import 'package:hiddify/features/activation/data/activation_api.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── SharedPrefs keys ──────────────────────────────────────────────────────────
const _kSubUrl = 'pixellnet.trial.sub_url';
const _kExpiresAt = 'pixellnet.trial.expires_at';
const _kActivatedAt = 'pixellnet.trial.activated_at';

// ── States ────────────────────────────────────────────────────────────────────

sealed class TrialState {
  const TrialState();
}

class TrialNotActivated extends TrialState {
  const TrialNotActivated();
}

class TrialActivating extends TrialState {
  const TrialActivating();
}

class TrialActive extends TrialState {
  final String subUrl;
  final DateTime expiresAt;
  final bool isPaid;

  const TrialActive({
    required this.subUrl,
    required this.expiresAt,
    this.isPaid = false,
  });

  int get daysLeft => expiresAt.difference(DateTime.now()).inDays.clamp(0, 9999);
  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isTrial => !isPaid;
  bool get showPaywall => isExpired && isTrial;
}

class TrialError extends TrialState {
  final String message;
  const TrialError(this.message);
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class TrialNotifier extends StateNotifier<TrialState> {
  TrialNotifier(this._ref) : super(const TrialNotActivated()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final subUrl = prefs.getString(_kSubUrl);
    final expiresStr = prefs.getString(_kExpiresAt);
    if (subUrl != null && expiresStr != null) {
      final expiresAt = DateTime.tryParse(expiresStr) ?? DateTime.now();
      state = TrialActive(subUrl: subUrl, expiresAt: expiresAt);
    }
  }

  Future<void> startTrial() async {
    if (state is TrialActivating) return;
    state = const TrialActivating();
    try {
      final api = _ref.read(activationApiProvider);
      final result = await api.startTrial();
      await _save(result.subUrl, result.expiresAt);
      await _addProfile(result.subUrl);
      state = TrialActive(subUrl: result.subUrl, expiresAt: result.expiresAt);
    } catch (e) {
      state = TrialError(_friendlyError(e));
    }
  }

  Future<void> _save(String subUrl, DateTime expiresAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSubUrl, subUrl);
    await prefs.setString(_kExpiresAt, expiresAt.toIso8601String());
    await prefs.setString(_kActivatedAt, DateTime.now().toIso8601String());
  }

  Future<void> _addProfile(String subUrl) async {
    try {
      final repo = _ref.read(profileRepositoryProvider).requireValue;
      await repo
          .upsertRemote(
            subUrl,
            userOverride: const UserOverride(name: 'PIXELLNET'),
          )
          .run();
    } catch (_) {
      // Профиль уже существует или upsert не поддерживает — игнорируем
    }
  }

  void retry() {
    state = const TrialNotActivated();
    startTrial();
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('network')) {
      return 'Сервер не отвечает, попробуй позже';
    }
    return 'Ошибка активации. Попробуй позже';
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final trialStateProvider =
    StateNotifierProvider<TrialNotifier, TrialState>((ref) {
  return TrialNotifier(ref);
});

/// true если сохранённый субUrl существует и не просрочен
final hasActiveTrialProvider = Provider<bool>((ref) {
  final state = ref.watch(trialStateProvider);
  return state is TrialActive && !state.isExpired;
});
