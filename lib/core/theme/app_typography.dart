import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Premium typography: serif headings, sans-serif body and prices.
abstract final class AppTypography {
  static TextTheme textTheme() {
    final headingFont = GoogleFonts.playfairDisplayTextTheme();
    final bodyFont = GoogleFonts.interTextTheme();

    return TextTheme(
      displayLarge: headingFont.displayLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      displayMedium: headingFont.displayMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      displaySmall: headingFont.displaySmall?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      headlineLarge: headingFont.headlineLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: headingFont.headlineMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: headingFont.headlineSmall?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      titleLarge: headingFont.titleLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: bodyFont.titleMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
      titleSmall: bodyFont.titleSmall?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      bodyLarge: bodyFont.bodyLarge?.copyWith(
        color: AppColors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: bodyFont.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
        height: 1.5,
      ),
      bodySmall: bodyFont.bodySmall?.copyWith(
        color: AppColors.textSecondary,
        height: 1.4,
      ),
      labelLarge: bodyFont.labelLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      labelMedium: bodyFont.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
      labelSmall: bodyFont.labelSmall?.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  /// Sans-serif style for product prices and numeric values.
  static TextStyle price({
    double fontSize = 18,
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.accent,
      letterSpacing: 0.25,
      decoration: decoration,
      decorationColor: color ?? AppColors.textSecondary,
    );
  }

  /// Название товара в карточке каталога.
  static TextStyle productName() {
    return GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
      height: 1.25,
    );
  }

  /// Металл / характеристика изделия.
  static TextStyle productMeta() {
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
      height: 1.2,
    );
  }

  /// Serif style for hero and section headings.
  static TextStyle heading({double fontSize = 32, Color? color}) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.textPrimary,
      letterSpacing: -0.25,
    );
  }

  /// Компактная подпись под историями и мелкими блоками.
  static TextStyle caption({Color? color, FontWeight fontWeight = FontWeight.w500}) {
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: fontWeight,
      color: color ?? AppColors.textPrimary,
      letterSpacing: 0.1,
      height: 1.2,
    );
  }

  /// Крупный акцентный заголовок для промо-баннеров.
  static TextStyle bannerTitle({Color? color}) {
    return GoogleFonts.playfairDisplay(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: color ?? AppColors.textOnPrimary,
      letterSpacing: 0.5,
      height: 1.15,
    );
  }

  /// Таймер и числовые блоки акций.
  static TextStyle countdown({Color? color, double fontSize = 13}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.textOnPrimary,
      letterSpacing: 1.2,
    );
  }

  /// Подписи нижней навигации.
  static TextStyle navLabel({required bool isActive}) {
    return GoogleFonts.inter(
      fontSize: 10,
      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
      letterSpacing: 0.2,
    );
  }
}
