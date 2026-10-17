import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'obmax_colors.dart';

/// The single OB Max theme. Registered as the forced theme in
/// [ThemeRegistry], so every theme lookup in the app resolves to it.
const obMaxThemeSpec = ThemeSpec(
  id: 'obmax',
  displayName: 'OB Max',
  colors: ThemeColorTokens(
    background: ObMaxColors.background,
    onBackground: ObMaxColors.textPrimary,
    surface: ObMaxColors.surface,
    onSurface: ObMaxColors.textPrimary,
    surfaceVariant: ObMaxColors.surfaceVariant,
    scrim: Color(0xCC080A23),
    accent: ObMaxColors.primary,
    onAccent: ObMaxColors.onPrimary,
    buttonNormal: ObMaxColors.surfaceVariant,
    buttonFocused: ObMaxColors.primary,
    buttonDisabled: Color(0xFF14173F),
    buttonActive: Color(0xFF262B66),
    onButtonNormal: ObMaxColors.textPrimary,
    onButtonFocused: ObMaxColors.onPrimary,
    onButtonDisabled: Color(0xFF6A6E99),
    inputBackground: ObMaxColors.surfaceVariant,
    inputFocused: Color(0xFF232861),
    inputBorder: Color(0xFF2E3470),
    inputBorderFocused: ObMaxColors.primary,
    rangeTrack: Color(0xFF2E3470),
    rangeProgress: ObMaxColors.primary,
    rangeThumb: ObMaxColors.primary,
    seekbarBuffered: Color(0x80B8BBD9),
    badgeBackground: ObMaxColors.secondary,
    onBadge: ObMaxColors.onPrimary,
    badgeUnplayed: ObMaxColors.secondary,
    badgeWatched: Color(0xFF3FBF7F),
    recordingActive: Color(0xFFE5484D),
    recordingScheduled: ObMaxColors.primary,
    error: ObMaxColors.error,
    card: ObMaxColors.surface,
  ),
  borders: ThemeBorderTokens(
    cardBorder: BorderSide(color: Colors.transparent),
    chipBorder: BorderSide(color: Color(0x5524B8F2)),
    // TV focus: a 3 px gold ring with a soft gold glow.
    focusBorder: BorderSide(color: ObMaxColors.primary, width: 3),
    cardRadius: BorderRadius.all(Radius.circular(8)),
    chipRadius: BorderRadius.all(Radius.circular(999)),
    chipBackground: Color(0x2224B8F2),
    focusGlow: [
      BoxShadow(color: Color(0x59EDA631), blurRadius: 16, spreadRadius: 1),
    ],
  ),
);

abstract final class ObMaxTheme {
  /// Makes [obMaxThemeSpec] the only theme. Call before the first theme
  /// lookup (ObMaxBoot does).
  static void install() {
    ThemeRegistry.forcedTheme = obMaxThemeSpec;
    ThemeRegistry.setActiveById(obMaxThemeSpec.id);
  }

  /// The parts of the Material theme Moonfin takes from fixed Jellyfin tokens
  /// rather than from the theme spec.
  static ThemeData adapt(ThemeData theme) {
    final scheme = theme.colorScheme.copyWith(
      secondary: ObMaxColors.secondary,
      onSecondary: ObMaxColors.onPrimary,
      tertiary: ObMaxColors.tertiary,
      onTertiary: ObMaxColors.textPrimary,
      onSurfaceVariant: ObMaxColors.textSecondary,
      surfaceContainerLowest: ObMaxColors.background,
      surfaceContainerLow: ObMaxColors.surface,
      surfaceContainer: ObMaxColors.surface,
      surfaceContainerHigh: ObMaxColors.surfaceVariant,
      outline: const Color(0xFF2E3470),
      outlineVariant: const Color(0xFF232861),
    );
    final text = theme.textTheme;
    return theme.copyWith(
      colorScheme: scheme,
      // Section titles in the cream of "MAX".
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(color: ObMaxColors.highlight),
        headlineSmall: text.headlineSmall?.copyWith(
          color: ObMaxColors.highlight,
        ),
      ),
      // Progress in OB blue, sliders stay gold.
      progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
        color: ObMaxColors.secondary,
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        backgroundColor: ObMaxColors.surface,
      ),
      drawerTheme: theme.drawerTheme.copyWith(
        backgroundColor: ObMaxColors.surface,
      ),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        backgroundColor: ObMaxColors.surfaceVariant,
        indicatorColor: ObMaxColors.primary.withValues(alpha: 0.22),
      ),
      bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
        backgroundColor: ObMaxColors.surfaceVariant,
        selectedItemColor: ObMaxColors.primary,
        unselectedItemColor: ObMaxColors.textSecondary,
      ),
      tabBarTheme: theme.tabBarTheme.copyWith(
        labelColor: ObMaxColors.primary,
        unselectedLabelColor: ObMaxColors.textSecondary,
        indicatorColor: ObMaxColors.primary,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ObMaxColors.secondary),
      ),
    );
  }
}
