import 'package:flutter/material.dart';

/// A selectable brand palette. Only the *brand* colors change between palettes;
/// neutrals (slate text, white cards, slate-50 page) stay constant so the app
/// stays readable in every theme.
///
/// - [primary]   : main brand color (buttons, icons, nav-selected).
/// - [secondary] : accent (gradient partner, secondary chips).
/// - [soft]      : very light primary tint — icon-chip backgrounds.
/// - [border]    : light primary tint — soft borders / containers.
/// - [heroFrom]/[heroTo] : deep → mid gradient for large hero/banner surfaces
///   (kept dark so big filled areas never look harsh / neon).
class AppPalette {
  const AppPalette({
    required this.id,
    required this.label,
    required this.primary,
    required this.secondary,
    required this.soft,
    required this.border,
    required this.heroFrom,
    required this.heroTo,
  });

  final String id;
  final String label;
  final Color primary;
  final Color secondary;
  final Color soft;
  final Color border;
  final Color heroFrom;
  final Color heroTo;

  /// Deep, calm gradient for hero cards / dashboard banners.
  LinearGradient get heroGradient => LinearGradient(
    colors: [heroFrom, heroTo],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Lively primary→accent gradient for small brand flourishes (logo, avatar).
  LinearGradient get brandGradient => LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// The curated set of themes shown in the appearance picker.
///
/// `Gold` is first so it is the default (and the `paletteById` fallback): an
/// elegant black + gold look on a warm cream page — dark antique-gold primary,
/// brighter gold accent, near-black→deep-gold hero gradient.
const List<AppPalette> kAppPalettes = [
  AppPalette(
    id: 'gold',
    label: 'Gold',
    primary: Color(0xFF8A6E16),
    secondary: Color(0xFFC9A227),
    soft: Color(0xFFFAF4E2),
    border: Color(0xFFEADBB0),
    heroFrom: Color(0xFF1B1813),
    heroTo: Color(0xFF6E5713),
  ),
  AppPalette(
    id: 'fyp_copper',
    label: 'FYP Copper',
    primary: Color(0xFFC35A06),
    secondary: Color(0xFFD4915F),
    soft: Color(0xFFFFF3E8),
    border: Color(0xFFFED7AA),
    heroFrom: Color(0xFFB84E00),
    heroTo: Color(0xFFD49462),
  ),
  AppPalette(
    id: 'fyp_gold',
    label: 'FYP Gold',
    primary: Color(0xFF8A6E16),
    secondary: Color(0xFFE7C955),
    soft: Color(0xFFFAF4E2),
    border: Color(0xFFEADBB0),
    heroFrom: Color(0xFF15140F),
    heroTo: Color(0xFF7E6908),
  ),
  AppPalette(
    id: 'fyp_teal',
    label: 'FYP Teal',
    primary: Color(0xFF078C66),
    secondary: Color(0xFF67B8A0),
    soft: Color(0xFFECFDF5),
    border: Color(0xFFC7F3E5),
    heroFrom: Color(0xFF078761),
    heroTo: Color(0xFF62B49C),
  ),
  AppPalette(
    id: 'indigo',
    label: 'Indigo',
    primary: Color(0xFF4F46E5),
    secondary: Color(0xFF14B8A6),
    soft: Color(0xFFEEF2FF),
    border: Color(0xFFE0E7FF),
    heroFrom: Color(0xFF312E81),
    heroTo: Color(0xFF4338CA),
  ),
  AppPalette(
    id: 'emerald',
    label: 'Emerald',
    primary: Color(0xFF059669),
    secondary: Color(0xFF0D9488),
    soft: Color(0xFFECFDF5),
    border: Color(0xFFD1FAE5),
    heroFrom: Color(0xFF064E3B),
    heroTo: Color(0xFF047857),
  ),
  AppPalette(
    id: 'violet',
    label: 'Violet',
    primary: Color(0xFF7C3AED),
    secondary: Color(0xFFDB2777),
    soft: Color(0xFFF5F3FF),
    border: Color(0xFFEDE9FE),
    heroFrom: Color(0xFF4C1D95),
    heroTo: Color(0xFF6D28D9),
  ),
  AppPalette(
    id: 'rose',
    label: 'Rose',
    primary: Color(0xFFE11D48),
    secondary: Color(0xFFF59E0B),
    soft: Color(0xFFFFF1F2),
    border: Color(0xFFFFE4E6),
    heroFrom: Color(0xFF881337),
    heroTo: Color(0xFFBE123C),
  ),
  AppPalette(
    id: 'ocean',
    label: 'Ocean',
    primary: Color(0xFF2563EB),
    secondary: Color(0xFF06B6D4),
    soft: Color(0xFFEFF6FF),
    border: Color(0xFFDBEAFE),
    heroFrom: Color(0xFF1E3A8A),
    heroTo: Color(0xFF1D4ED8),
  ),
  AppPalette(
    id: 'graphite',
    label: 'Graphite',
    primary: Color(0xFF334155),
    secondary: Color(0xFF14B8A6),
    soft: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    heroFrom: Color(0xFF0F172A),
    heroTo: Color(0xFF334155),
  ),
];

/// Look up a palette by id, falling back to the first (Gold) when unknown.
AppPalette paletteById(String? id) => kAppPalettes.firstWhere(
  (palette) => palette.id == id,
  orElse: () => kAppPalettes.first,
);
