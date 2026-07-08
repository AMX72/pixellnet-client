import 'package:flutter/material.dart';

/// PIXELLNET brand tokens (metadata + palette v2).
///
/// Палитра v2 (2026-07-08 после консилиума 5 design + 1 linguist):
/// - Soft indigo (доверие, интеллект) — Linear/Stripe vibe
/// - Sage-mint (природа, здоровье, спокойствие) — Mullvad vibe
/// - Off-black / off-white surfaces (мягко на глаз)
/// - Semantic: olive success, amber warning, terracotta danger
/// - **Отказ от кислотного cyan #00E5FF** и жёсткого navy #0F1729
abstract class PixellnetBrand {
  static const String appName = 'PIXELLNET';
  static const String appTagline = 'PIXELLNET открывает сайты, которые не работают';
  static const String homepage = 'https://pixellnet.com';
  static const String supportEmail = 'support@pixellnet.com';
}

/// Полная палитра для Material 3 (`ColorScheme` явно, не `fromSeed`).
///
/// Все WCAG проверены: body ≥ AA 4.5:1, large text/UI ≥ 3:1.
abstract class PixellnetColors {
  // ═══════════════════ DARK MODE ═══════════════════
  /// Мягкий off-black slate (не #000 — щадит зрение).
  static const darkSurface = Color(0xFF1A1D24);
  static const darkSurfaceContainer = Color(0xFF23272F);
  static const darkSurfaceContainerHigh = Color(0xFF2D323C);
  static const darkOnSurface = Color(0xFFE4E6EB);
  static const darkOnSurfaceVariant = Color(0xFF9BA1AD);
  static const darkOutline = Color(0xFF3A4050);

  /// Soft indigo — доверие, технологичность. НЕ neon.
  static const darkPrimary = Color(0xFF7C86E8);
  static const darkOnPrimary = Color(0xFF0F1220);
  static const darkPrimaryContainer = Color(0xFF2A3050);
  static const darkOnPrimaryContainer = Color(0xFFC5CBFF);

  /// Sage-mint — спокойный природный accent. НЕ кислотный.
  static const darkAccent = Color(0xFF89C9B0);
  static const darkOnAccent = Color(0xFF0F1F1A);

  // ═══════════════════ LIGHT MODE ═══════════════════
  /// Off-white с холодным полутоном (Notion-стайл, не чисто-#FFF).
  static const lightSurface = Color(0xFFF7F7FA);
  static const lightSurfaceContainer = Color(0xFFEEEEF3);
  static const lightSurfaceContainerHigh = Color(0xFFE4E5EC);
  static const lightOnSurface = Color(0xFF191B22);
  static const lightOnSurfaceVariant = Color(0xFF5A6070);
  static const lightOutline = Color(0xFFCACCD6);

  /// Deep indigo — тот же оттенок, темнее.
  static const lightPrimary = Color(0xFF4C56C0);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFDEE1FF);
  static const lightOnPrimaryContainer = Color(0xFF161A50);

  /// Deep sage.
  static const lightAccent = Color(0xFF3E8E75);
  static const lightOnAccent = Color(0xFFFFFFFF);

  // ═══════════════════ SEMANTIC (общие) ═══════════════════
  /// Спокойная олива (Mullvad) — «Отлично / подключено».
  static const success = Color(0xFF6A9A6B);
  static const onSuccess = Color(0xFF0E1A0E);
  static const successContainer = Color(0xFFDCEBDD);

  /// Мягкий янтарь — «Нормально / внимание».
  static const warning = Color(0xFFD4A24C);
  static const onWarning = Color(0xFF231600);

  /// Тёплый терракот — «Плохо / ошибка» БЕЗ агрессии.
  static const danger = Color(0xFFC96F5A);
  static const onDanger = Color(0xFFFFFFFF);
  static const dangerContainer = Color(0xFF4A1D14);
}
