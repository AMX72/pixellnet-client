import 'package:flutter/material.dart';

abstract class PixellnetBrand {
  static const String appName = 'PIXELLNET';
  static const String appTagline = 'Стабильное соединение в один клик';
  static const String homepage = 'https://pixellnet.com';
  static const String supportEmail = 'support@pixellnet.com';

  // ─── iOS Settings palette (v4, 2026-11-11) ───
  // Переход с warm-charcoal/mocha на системные iOS-цвета. Референс — Settings.app
  // на iOS 17: #F2F2F7 grouped bg, #FFF card, #007AFF tint, #8E8E93 secondary text.
  // В dark — #000 bg, #1C1C1E card, #0A84FF tint, #AEAEB2 secondary. Контрасты AA.

  // Backgrounds — grouped-table style (один из двух фонов по iOS-стандарту)
  static const Color bgLight = Color(0xFFF2F2F7);         // iOS systemGroupedBackground
  static const Color bgDark = Color(0xFF000000);          // iOS systemGroupedBackground dark
  static const Color surfaceLight = Color(0xFFFFFFFF);    // iOS secondarySystemGroupedBackground
  static const Color surface = Color(0xFF1C1C1E);         // iOS secondarySystemGroupedBackground dark
  static const Color surfaceElevated = Color(0xFF2C2C2E); // iOS tertiarySystemGroupedBackground dark
  static const Color surfaceHover = Color(0xFF3A3A3C);    // tap feedback dark

  // Tint (accent) — iOS system blue
  static const Color tintLight = Color(0xFF007AFF);
  static const Color tintDark = Color(0xFF0A84FF);

  // Semantic (iOS system colors)
  static const Color amberLight = Color(0xFFFF9500);      // iOS systemOrange
  static const Color amberDark = Color(0xFFFF9F0A);
  static const Color greenLight = Color(0xFF34C759);      // iOS systemGreen — connected
  static const Color greenDark = Color(0xFF30D158);
  static const Color redLight = Color(0xFFFF3B30);        // iOS systemRed — error
  static const Color redDark = Color(0xFFFF453A);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);     // dark mode primary (contrast 21:1 on #000)
  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textSecondary = Color(0xFFAEAEB2);   // iOS secondaryLabel dark
  static const Color textSecondaryLight = Color(0xFF8E8E93); // iOS secondaryLabel
  static const Color textMuted = Color(0xFF8E8E93);       // iOS tertiaryLabel ~
  static const Color separatorLight = Color(0xFFC6C6C8);  // iOS separator
  static const Color separatorDark = Color(0xFF38383A);

  // ─── Backward-compat aliases (чтоб старый код не ломался) ───
  static const Color mocha = tintDark;                    // primary action
  static const Color mochaOnDark = tintDark;
  static const Color mochaDark = tintLight;               // pressed state → light tint
  static const Color amber = amberDark;                   // connecting/trial
  static const Color olive = greenDark;                   // success/connected
  static const Color coral = redDark;                     // error
  static const Color coralOnDark = redDark;
  static const Color blue = tintDark;                     // info/links
  static const Color primary = tintDark;
  static const Color accent = tintDark;
  static const Color textOnDark = textPrimary;
}
