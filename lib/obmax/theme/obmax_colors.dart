import 'package:flutter/painting.dart';

/// OB Max palette, taken from the logo.
abstract final class ObMaxColors {
  /// Night blue of the logo: app background.
  static const background = Color(0xFF080A23);

  /// Cards, panels, settings drawer.
  static const surface = Color(0xFF11143A);

  /// Fields, inactive tabs, navigation bar.
  static const surfaceVariant = Color(0xFF1A1E4D);

  /// Gold: TV focus, main "Play" button, active tab, sliders.
  static const primary = Color(0xFFEDA631);
  static const onPrimary = Color(0xFF080A23);

  /// OB blue: links, progress, badges.
  static const secondary = Color(0xFF24B8F2);

  /// Halo violet: gradients and backdrop glows.
  static const tertiary = Color(0xFF75439B);

  /// MAX cream: section titles, accent text.
  static const highlight = Color(0xFFFCE4B6);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB8BBD9);

  static const error = Color(0xFFFF6B6B);
}
