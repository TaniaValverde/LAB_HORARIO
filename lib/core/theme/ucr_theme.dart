import 'package:flutter/material.dart';

abstract final class UcrPalette {
  static const blue = Color(0xFF005DA4);
  static const sky = Color(0xFF00C0F3);
  static const white = Color(0xFFFFFFFF);
  static const yellow = Color(0xFFFFE06A);
  static const green = Color(0xFF6DC067);
  static const ink = Color(0xFF173B60);
  static const background = Color(0xFFF4F7FA);
}

abstract final class UcrTheme {
  static ThemeData get light {
    final colors = ColorScheme.fromSeed(
      seedColor: UcrPalette.blue,
      primary: UcrPalette.blue,
      onPrimary: UcrPalette.white,
      primaryContainer: UcrPalette.sky,
      onPrimaryContainer: UcrPalette.ink,
      secondary: UcrPalette.yellow,
      onSecondary: UcrPalette.ink,
      tertiary: UcrPalette.green,
      onTertiary: UcrPalette.ink,
      surface: UcrPalette.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: 'Arial',
      scaffoldBackgroundColor: UcrPalette.background,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: UcrPalette.white,
      ),
    );
  }

  static ThemeData get dark {
    final colors = ColorScheme.fromSeed(
      seedColor: UcrPalette.sky,
      brightness: Brightness.dark,
      primary: UcrPalette.sky,
      onPrimary: UcrPalette.ink,
      secondary: UcrPalette.yellow,
      onSecondary: UcrPalette.ink,
      tertiary: UcrPalette.green,
      onTertiary: UcrPalette.ink,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      brightness: Brightness.dark,
      fontFamily: 'Arial',
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
