import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'spotify_colors.dart';

/// A fully hand-composed ThemeData rather than a Material 3 seed color:
/// Spotify's specific near-black/green look does not fall out of the
/// seed-color tonal-palette algorithm.
abstract final class SpotifyTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: SpotifyColors.white,
      displayColor: SpotifyColors.white,
    );

    return base.copyWith(
      scaffoldBackgroundColor: SpotifyColors.black,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        surface: SpotifyColors.black,
        primary: SpotifyColors.green,
        onPrimary: Colors.black,
        error: SpotifyColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SpotifyColors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SpotifyColors.green,
          foregroundColor: Colors.black,
          disabledBackgroundColor: SpotifyColors.surfaceBright,
          disabledForegroundColor: SpotifyColors.textSecondary,
          minimumSize: const Size.fromHeight(50),
          shape: const StadiumBorder(),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SpotifyColors.white,
          side: const BorderSide(color: SpotifyColors.white),
          minimumSize: const Size.fromHeight(50),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: SpotifyColors.green),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SpotifyColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: SpotifyColors.textSecondary),
        hintStyle: const TextStyle(color: SpotifyColors.textSecondary),
        errorStyle: const TextStyle(color: SpotifyColors.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: SpotifyColors.green, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: SpotifyColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: SpotifyColors.error, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SpotifyColors.surfaceBright,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: SpotifyColors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
