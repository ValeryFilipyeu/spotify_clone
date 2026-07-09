import 'package:flutter/material.dart';

/// A Spotify-lookalike palette: these are plain color facts (near-black bg,
/// brand green), not copyrighted assets. No real Spotify logo image or
/// proprietary font is used anywhere in this app.
abstract final class SpotifyColors {
  static const Color black = Color(0xFF121212);
  static const Color surfaceDim = Color(0xFF181818);
  static const Color surface = Color(0xFF212121);
  static const Color surfaceBright = Color(0xFF282828);
  static const Color green = Color(0xFF1ED760);
  static const Color greenDark = Color(0xFF1DB954);
  static const Color white = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color error = Color(0xFFF15E6C);
}
