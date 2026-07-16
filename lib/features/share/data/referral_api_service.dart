import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ReferralProfile {
  final String refCode;
  final String refLink;
  final String inviteText;
  final int referralsConfirmed;
  final int referralsPending;
  final int bonusDaysEarned;

  const ReferralProfile({
    required this.refCode,
    required this.refLink,
    required this.inviteText,
    required this.referralsConfirmed,
    required this.referralsPending,
    required this.bonusDaysEarned,
  });

  factory ReferralProfile.fromJson(Map<String, dynamic> json) => ReferralProfile(
        refCode: json['ref_code'] as String? ?? '',
        refLink: json['ref_link'] as String? ?? '',
        inviteText: json['invite_text'] as String? ?? '',
        referralsConfirmed: (json['referrals_confirmed'] as num?)?.toInt() ?? 0,
        referralsPending: (json['referrals_pending'] as num?)?.toInt() ?? 0,
        bonusDaysEarned: (json['bonus_days_earned'] as num?)?.toInt() ?? 0,
      );
}

/// Fetches referral profile from pixellnet-api.
/// Uses trial subscription_url stored in prefs (по TrialService key).
class ReferralApiService {
  ReferralApiService._();
  static final instance = ReferralApiService._();

  static const _apiBase = 'https://pixellnet.com/api';
  static const _kPrefTrialUrl = 'pixellnet.trial.subscription_url';
  static const _kPrefRefCode = 'pixellnet.referral.ref_code';
  static const _kPrefRefCachedAt = 'pixellnet.referral.cached_at';

  /// Fetch referral profile — по sub_url из prefs.
  /// Returns null если trial ещё не создан или API недоступен.
  Future<ReferralProfile?> fetchMyProfile({bool useCache = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final subUrl = prefs.getString(_kPrefTrialUrl);
    if (subUrl == null || subUrl.isEmpty) return null;

    // Simple cache — 6 часов (per plan бонусы не меняются мгновенно)
    if (useCache) {
      final cachedAt = prefs.getInt(_kPrefRefCachedAt) ?? 0;
      final cachedCode = prefs.getString(_kPrefRefCode);
      if (cachedCode != null && cachedCode.isNotEmpty) {
        final ageMs = DateTime.now().millisecondsSinceEpoch - cachedAt;
        if (ageMs < 6 * 3600 * 1000) {
          return _profileFromCache(prefs, cachedCode);
        }
      }
    }

    try {
      final resp = await http
          .get(
            Uri.parse('$_apiBase/referral/my?sub_url=${Uri.encodeQueryComponent(subUrl)}'),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final profile = ReferralProfile.fromJson(data);

      // Cache для offline / rapid re-opens
      await prefs.setString(_kPrefRefCode, profile.refCode);
      await prefs.setInt('pixellnet.referral.confirmed', profile.referralsConfirmed);
      await prefs.setInt('pixellnet.referral.pending', profile.referralsPending);
      await prefs.setInt('pixellnet.referral.bonus_days', profile.bonusDaysEarned);
      await prefs.setInt(_kPrefRefCachedAt, DateTime.now().millisecondsSinceEpoch);
      return profile;
    } catch (_) {
      return null;
    }
  }

  ReferralProfile _profileFromCache(SharedPreferences prefs, String code) {
    final link = 'https://pixellnet.com/i/$code';
    return ReferralProfile(
      refCode: code,
      refLink: link,
      inviteText: 'Пользуюсь PIXELLNET — быстрый VPN без танцев с бубном. '
          'Держи 7 дней бесплатно: $link',
      referralsConfirmed: prefs.getInt('pixellnet.referral.confirmed') ?? 0,
      referralsPending: prefs.getInt('pixellnet.referral.pending') ?? 0,
      bonusDaysEarned: prefs.getInt('pixellnet.referral.bonus_days') ?? 0,
    );
  }
}
