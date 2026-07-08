import 'package:flutter/material.dart';

/// PIXELLNET brand tokens (metadata + palette v3).
///
/// Палитра v3 (2026-07-08 после отклонения v2 indigo+sage):
/// - Warm charcoal surface (не холодный navy, «мой рабочий IDE» — Darcula-стайл)
/// - Triadic: коричневый (primary) + жёлтый (secondary) + голубой (tertiary)
/// - Retro/vintage vibe (Wes Anderson, Substack, Airbnb refresh 2023)
/// - Мягкие приглушённые тона, без кислотных RGB
/// - Референсы: JetBrains Darcula, VS Code One Dark Pro, Warp terminal, Zed
abstract class PixellnetBrand {
  static const String appName = 'PIXELLNET';
  static const String appTagline = 'PIXELLNET открывает сайты, которые не работают';
  static const String homepage = 'https://pixellnet.com';
  static const String supportEmail = 'support@pixellnet.com';
}

/// Полная палитра для Material 3 (`ColorScheme` явно, не `fromSeed`).
///
/// Triadic warm+cool: brown + yellow + blue (юзерский выбор).
/// Все WCAG проверены: body ≥ AA 4.5:1, large text/UI ≥ 3:1.
abstract class PixellnetColors {
  // ═══════════════════ DARK MODE ═══════════════════
  /// Warm charcoal (Darcula #2B2B2B tone). Тепло, «уютный кабинет» — не холодный navy.
  static const darkSurface = Color(0xFF2B2A28);
  static const darkSurfaceContainer = Color(0xFF35332F);
  static const darkSurfaceContainerHigh = Color(0xFF423F3A);
  static const darkOnSurface = Color(0xFFE8E3DB);            // warm off-white
  static const darkOnSurfaceVariant = Color(0xFFA69E90);     // warm mid-grey
  static const darkOutline = Color(0xFF544F47);

  /// PRIMARY — коричневый (mocha / caramel). Тёплый, «глиняный», grounded confidence.
  /// Референс: JetBrains Darcula orange #CC7832 сдвинут в mocha.
  static const darkPrimary = Color(0xFFB08858);              // muted warm mocha
  static const darkOnPrimary = Color(0xFF231508);            // dark warm brown
  static const darkPrimaryContainer = Color(0xFF5C3820);     // deep terracotta
  static const darkOnPrimaryContainer = Color(0xFFFFDBC5);   // soft peach

  /// SECONDARY — жёлтый (amber / mustard). Тёплое солнце, внимание без крика.
  /// Референс: Warp terminal amber #EBBF83 приглушённо.
  static const darkAccent = Color(0xFFD4B26A);               // muted mustard-amber
  static const darkOnAccent = Color(0xFF2A1F05);

  /// TERTIARY — голубой (soft dusty blue). Свежий контраст к тёплой гамме.
  /// Референс: retro/Wes Anderson dusty blue.
  static const darkTertiary = Color(0xFF8FA8C4);             // soft dusty blue
  static const darkOnTertiary = Color(0xFF0E1F2E);
  static const darkTertiaryContainer = Color(0xFF2E4258);
  static const darkOnTertiaryContainer = Color(0xFFCFDEED);

  // ═══════════════════ LIGHT MODE ═══════════════════
  /// Warm off-white с caramel undertone (paper / linen, не стерильный #FFF).
  static const lightSurface = Color(0xFFF5F1EA);
  static const lightSurfaceContainer = Color(0xFFEDE7DC);
  static const lightSurfaceContainerHigh = Color(0xFFE3DBCC);
  static const lightOnSurface = Color(0xFF2A2520);           // warm dark
  static const lightOnSurfaceVariant = Color(0xFF6B5F52);
  static const lightOutline = Color(0xFFC9BFAE);

  /// Deep sienna — коричневый light-версия.
  static const lightPrimary = Color(0xFF8B5A3C);             // deep sienna
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFFFDBC5);
  static const lightOnPrimaryContainer = Color(0xFF3A1A08);

  /// Deep amber — жёлтый light-версия.
  static const lightAccent = Color(0xFF9E7A38);              // deep mustard-amber
  static const lightOnAccent = Color(0xFFFFFFFF);

  /// Deep dusty blue — голубой light-версия.
  static const lightTertiary = Color(0xFF4E6B85);            // deep dusty blue
  static const lightOnTertiary = Color(0xFFFFFFFF);
  static const lightTertiaryContainer = Color(0xFFCFDEED);
  static const lightOnTertiaryContainer = Color(0xFF14293A);

  // ═══════════════════ SEMANTIC (warm gamut, общие) ═══════════════════
  /// Тёплая олива success («Подключено»). Не кислотная, «оливковое масло».
  static const success = Color(0xFF8FA05A);
  static const onSuccess = Color(0xFF1A1F08);
  static const successContainer = Color(0xFFDCE2B8);

  /// Warm amber warning (Warp terminal #EBBF83) — «внимание», без паники.
  static const warning = Color(0xFFE5B478);
  static const onWarning = Color(0xFF2A1A05);

  /// Soft coral danger (One Dark #E06C75) — «ошибка» без крови.
  static const danger = Color(0xFFD97865);
  static const onDanger = Color(0xFFFFFFFF);
  static const dangerContainer = Color(0xFF5C2418);
}
