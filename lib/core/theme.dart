import 'package:flutter/material.dart';

class DfColors {
  static const bg = Color(0xFF080A1C);
  static const bgTop = Color(0xFF17144A);
  static const surface = Color(0xFF12153A);
  static const raise = Color(0xFF1B1F52);
  static const ink = Color(0xFFF1F2FF);
  static const muted = Color(0xFF9AA0CC);
  static const line = Color(0xFF2B3073);
  static const accent = Color(0xFF8B5CFF);
  static const accentDeep = Color(0xFF5B3BE0);
  static const onAccent = Color(0xFFFFFFFF);
  static const ok = Color(0xFF3DDC84);
  static const warn = Color(0xFFFF9F43);
  static const danger = Color(0xFFFF8A80);

  // "Aurora glass": the violet of the brand with a cyan and a pink glow.
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFFF4FA3);
  static const gold = Color(0xFFFFC857);
  static const glassFill = Color(0x12FFFFFF);
  static const glassEdge = Color(0x24FFFFFF);
}

/// Gradients shared by the home screen and the other studio screens.
class DfGradients {
  /// Page background: deep indigo at the top fading into the base colour.
  static const page = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [DfColors.bgTop, DfColors.bg],
    stops: [0.0, 0.55],
  );

  /// Soft frosted fill used by cards (a light veil over the dark page).
  static const glass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1CFFFFFF), Color(0x08FFFFFF)],
  );

  /// Thin bright edge of a glass card: lit from the top left.
  static const glassEdge = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x55FFFFFF), Color(0x0FFFFFFF), Color(0x26FFFFFF)],
  );

  /// Violet to cyan, for accents (logo, selected states).
  static const aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA855F7), Color(0xFF6366F1), DfColors.cyan],
  );

  /// Main call-to-action (buttons, hero).
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9A6BFF), DfColors.accentDeep],
  );

  /// A tile gradient built from one base colour (lighter top-left, deeper bottom-right).
  static LinearGradient tile(Color base) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(base, Colors.white, 0.12)!,
          Color.lerp(base, Colors.black, 0.38)!,
        ],
      );
}

/// Used when the bundled Burmese font is not installed (see pubspec.yaml).
const List<String> burmeseFallback = [
  'Noto Sans Myanmar',
  'Padauk',
  'Myanmar Text',
];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DfColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: DfColors.accent,
    onPrimary: DfColors.onAccent,
    surface: DfColors.surface,
    onSurface: DfColors.ink,
    error: DfColors.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: DfColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: DfColors.ink,
      displayColor: DfColors.ink,
      fontFamilyFallback: burmeseFallback,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: DfColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: DfColors.ink,
        fontFamilyFallback: burmeseFallback,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0C0E2B),
      surfaceTintColor: Colors.transparent,
      height: 68,
      indicatorColor: DfColors.accent.withValues(alpha: 0.32),
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          color: on ? DfColors.ink : DfColors.muted,
          fontFamilyFallback: burmeseFallback,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return IconThemeData(color: on ? DfColors.accent : DfColors.muted);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DfColors.accentDeep,
        foregroundColor: DfColors.onAccent,
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontFamilyFallback: burmeseFallback),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DfColors.ink,
        minimumSize: const Size(64, 46),
        side: const BorderSide(color: DfColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: DfColors.accentDeep,
      foregroundColor: DfColors.onAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: DfColors.raise,
      selectedColor: DfColors.accent.withValues(alpha: 0.35),
      side: const BorderSide(color: DfColors.line),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: DfColors.ink, fontFamilyFallback: burmeseFallback),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: DfColors.raise,
        selectedBackgroundColor: DfColors.accent.withValues(alpha: 0.4),
        foregroundColor: DfColors.muted,
        selectedForegroundColor: DfColors.ink,
        side: const BorderSide(color: DfColors.line),
      ),
    ),
    cardTheme: CardThemeData(
      color: DfColors.surface.withValues(alpha: 0.78),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: DfColors.glassEdge)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF14183F),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: DfColors.glassEdge)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF12153A),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: DfColors.line,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF191D4A),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: DfColors.glassEdge)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0x1FFFFFFF), space: 1),
    listTileTheme: const ListTileThemeData(iconColor: DfColors.muted),
    sliderTheme: SliderThemeData(
      activeTrackColor: DfColors.accent,
      inactiveTrackColor: DfColors.line,
      thumbColor: Colors.white,
      overlayColor: DfColors.accent.withValues(alpha: 0.18),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : DfColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? DfColors.accent : DfColors.raise),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : DfColors.line),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: DfColors.accent, linearTrackColor: DfColors.line),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DfColors.raise,
      contentTextStyle: const TextStyle(color: DfColors.ink, fontFamilyFallback: burmeseFallback),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DfColors.raise,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: DfColors.line),
      ),
    ),
  );
}
