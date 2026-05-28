import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Builds the light + dark `ThemeData` for the portal. M3-first, designed to
/// feel like a modern productivity app (Linear / Notion style) — soft shadows,
/// 14–18px radii, slate neutrals, indigo primary, teal accent.
class AppTheme {
  AppTheme._();

  // Shared shape tokens
  static final _cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
  );
  static final _smallShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  static final _pillShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(999),
  );

  static ThemeData light() => _build(_lightScheme(), Brightness.light);
  static ThemeData dark() => _build(_darkScheme(), Brightness.dark);

  // ----- Color schemes ------------------------------------------------------
  static ColorScheme _lightScheme() {
    return const ColorScheme.light(
      primary: AppColors.indigo600,
      onPrimary: Colors.white,
      primaryContainer: AppColors.indigo100,
      onPrimaryContainer: AppColors.indigo950,
      secondary: AppColors.teal600,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.teal100,
      onSecondaryContainer: AppColors.teal900,
      tertiary: AppColors.amber600,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFFF3D6),
      onTertiaryContainer: AppColors.amber700,
      error: AppColors.danger600,
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: Colors.white,
      onSurface: AppColors.slate900,
      surfaceContainerHighest: AppColors.slate100,
      onSurfaceVariant: AppColors.slate500,
      outline: AppColors.slate200,
      outlineVariant: AppColors.slate300,
      shadow: AppColors.slate900,
      scrim: AppColors.slate900,
      inverseSurface: AppColors.slate900,
      onInverseSurface: AppColors.slate50,
      inversePrimary: AppColors.indigo300,
    );
  }

  static ColorScheme _darkScheme() {
    return const ColorScheme.dark(
      primary: AppColors.indigo400,
      onPrimary: AppColors.indigo950,
      primaryContainer: AppColors.indigo800,
      onPrimaryContainer: AppColors.indigo100,
      secondary: AppColors.teal400,
      onSecondary: AppColors.teal900,
      secondaryContainer: AppColors.teal800,
      onSecondaryContainer: AppColors.teal100,
      tertiary: AppColors.amber400,
      onTertiary: AppColors.amber700,
      tertiaryContainer: Color(0xFF78350F),
      onTertiaryContainer: Color(0xFFFEF3C7),
      error: Color(0xFFFCA5A5),
      onError: Color(0xFF7F1D1D),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: AppColors.slate900,
      onSurface: AppColors.slate50,
      surfaceContainerHighest: AppColors.slate800,
      onSurfaceVariant: AppColors.slate400,
      outline: AppColors.slate700,
      outlineVariant: AppColors.slate800,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.slate50,
      onInverseSurface: AppColors.slate900,
      inversePrimary: AppColors.indigo700,
    );
  }

  // ----- Theme builder ------------------------------------------------------
  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final textTheme = _textTheme(scheme.onSurface);
    final outline = scheme.outline;
    // Card border is stronger than the global outline so cards pop on the
    // light page background.
    final cardBorderColor =
        isLight ? AppColors.slate200 : AppColors.slate700;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isLight ? AppTokens.lightPageBg : AppTokens.darkPageBg,
      canvasColor: scheme.surface,
      dividerColor: scheme.outline,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      iconTheme: IconThemeData(
        color: isLight ? AppColors.slate700 : AppColors.slate200,
        size: 22,
      ),
      primaryIconTheme: IconThemeData(color: scheme.onPrimary),

      // ---- AppBar ----------------------------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 18,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
          fontSize: 17,
        ),
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),

      // ---- Cards -----------------------------------------------------------
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        // Slight elevation + soft shadow so cards pop against the slate-50
        // page background even when the border is subtle.
        elevation: isLight ? 1.5 : 0,
        shadowColor: isLight
            ? AppColors.slate900.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.4),
        margin: EdgeInsets.zero,
        shape: _cardShape.copyWith(
          side: BorderSide(color: cardBorderColor),
        ),
      ),

      // ---- Inputs ----------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : AppColors.slate800,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        prefixIconColor: isLight ? AppColors.slate500 : AppColors.slate400,
        suffixIconColor: isLight ? AppColors.slate500 : AppColors.slate400,
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? AppColors.slate500 : AppColors.slate400,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        helperStyle: textTheme.bodySmall?.copyWith(
          color: isLight ? AppColors.slate500 : AppColors.slate400,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? AppColors.slate400 : AppColors.slate500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),

      // ---- Buttons ---------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: outline,
          disabledForegroundColor: isLight
              ? AppColors.slate400
              : AppColors.slate600,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: _smallShape,
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          side: BorderSide(color: outline, width: 1.2),
          shape: _smallShape,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          shape: _smallShape,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: isLight ? AppColors.slate700 : AppColors.slate200,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // ---- Chips -----------------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: isLight
            ? AppColors.slate100
            : AppColors.slate800,
        disabledColor:
            isLight ? AppColors.slate100 : AppColors.slate800,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        side: BorderSide(color: outline),
        shape: _pillShape,
        labelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 0,
        pressElevation: 0,
        showCheckmark: false,
      ),

      // ---- Dialogs / Bottom sheets -----------------------------------------
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? AppColors.slate600 : AppColors.slate300,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        modalElevation: 0,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // ---- Snackbars -------------------------------------------------------
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        actionTextColor: scheme.inversePrimary,
      ),

      // ---- Navigation ------------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? scheme.primary
                : (isLight ? AppColors.slate500 : AppColors.slate400),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? scheme.primary
                : (isLight ? AppColors.slate500 : AppColors.slate400),
          );
        }),
        elevation: 0,
        height: 70,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(
          color: isLight ? AppColors.slate500 : AppColors.slate400,
        ),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: isLight ? AppColors.slate500 : AppColors.slate400,
        ),
      ),

      // ---- Misc components -------------------------------------------------
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: isLight ? AppColors.slate200 : AppColors.slate800,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isLight ? Colors.white : AppColors.slate400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isLight ? AppColors.slate300 : AppColors.slate700;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide(color: outline, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isLight ? AppColors.slate400 : AppColors.slate500;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor:
            isLight ? AppColors.slate500 : AppColors.slate400,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: outline,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: isLight ? AppColors.slate600 : AppColors.slate300,
        textColor: scheme.onSurface,
        tileColor: Colors.transparent,
        shape: _smallShape,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(scheme.surface),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: outline),
            ),
          ),
          elevation: WidgetStateProperty.all(2),
        ),
      ),
    );
  }

  // ----- Typography ---------------------------------------------------------
  static TextTheme _textTheme(Color onSurface) {
    // Slightly tighter line heights and bolder weights than the M3 defaults,
    // matching the look of premium productivity apps.
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.15,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.2,
        letterSpacing: -0.3,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.25,
      ),
      headlineLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.35,
      ),
      titleSmall: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.4,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: onSurface,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurface,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: onSurface,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: 0.2,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: 0.4,
      ),
    );
  }
}
