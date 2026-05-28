import 'package:flutter/material.dart';

/// Brand palette for the portal. Designed in the style of Linear / Notion —
/// modern indigo primary, teal secondary, amber tertiary, slate neutrals.
///
/// All colors come from the Tailwind v3 reference palette so the values feel
/// consistent across cards / chips / borders / typography.
class AppColors {
  AppColors._();

  // ---- Brand ---------------------------------------------------------------
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const indigo800 = Color(0xFF3730A3);
  static const indigo900 = Color(0xFF312E81);
  static const indigo950 = Color(0xFF1E1B4B);

  // ---- Accent --------------------------------------------------------------
  static const teal50 = Color(0xFFF0FDFA);
  static const teal100 = Color(0xFFCCFBF1);
  static const teal200 = Color(0xFF99F6E4);
  static const teal400 = Color(0xFF2DD4BF);
  static const teal500 = Color(0xFF14B8A6);
  static const teal600 = Color(0xFF0D9488);
  static const teal700 = Color(0xFF0F766E);
  static const teal800 = Color(0xFF115E59);
  static const teal900 = Color(0xFF134E4A);

  static const amber400 = Color(0xFFFBBF24);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);

  static const violet50 = Color(0xFFF5F3FF);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet400 = Color(0xFFA78BFA);
  static const violet600 = Color(0xFF7C3AED);

  // ---- Neutrals (slate) ----------------------------------------------------
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);

  // ---- Semantic ------------------------------------------------------------
  static const success500 = Color(0xFF10B981);
  static const warning500 = Color(0xFFF59E0B);
  static const danger500 = Color(0xFFEF4444);
  static const danger600 = Color(0xFFDC2626);
}

/// Brightness-aware semantic tokens. Use these in widgets so the same code
/// renders correctly in light + dark mode.
class AppTokens {
  AppTokens._();

  // Brand
  static const Color brand = AppColors.indigo600;
  static const Color brandSoft = AppColors.indigo50;
  static const Color brandBorder = AppColors.indigo100;
  static const Color accent = AppColors.teal600;
  static const Color accentSoft = AppColors.teal50;
  static const Color highlight = AppColors.amber600;

  // Light surfaces
  static const Color lightPageBg = AppColors.slate50;
  static const Color lightCardBg = Colors.white;
  static const Color lightCardBorder = AppColors.slate200;
  static const Color lightTextPrimary = AppColors.slate900;
  static const Color lightTextSecondary = AppColors.slate500;
  static const Color lightTextMuted = AppColors.slate400;
  static const Color lightDivider = AppColors.slate200;
  static const Color lightSurfaceVariant = AppColors.slate100;

  // Dark surfaces
  static const Color darkPageBg = AppColors.slate950;
  static const Color darkCardBg = AppColors.slate900;
  static const Color darkCardBorder = AppColors.slate800;
  static const Color darkTextPrimary = AppColors.slate50;
  static const Color darkTextSecondary = AppColors.slate400;
  static const Color darkTextMuted = AppColors.slate500;
  static const Color darkDivider = AppColors.slate800;
  static const Color darkSurfaceVariant = AppColors.slate800;
}
