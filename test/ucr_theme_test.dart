import 'package:declara_horario/core/theme/ucr_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('Institutional palette is centralized and foregrounds are readable', () {
    final light = UcrTheme.light.colorScheme;
    final dark = UcrTheme.dark.colorScheme;

    expect(light.primary, UcrPalette.blue);
    expect(light.primaryContainer, UcrPalette.sky);
    expect(light.secondary, UcrPalette.yellow);
    expect(light.tertiary, UcrPalette.green);
    expect(
      _contrast(light.primary, light.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(light.primaryContainer, light.onPrimaryContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(light.secondary, light.onSecondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(light.tertiary, light.onTertiary),
      greaterThanOrEqualTo(4.5),
    );
    expect(_contrast(dark.primary, dark.onPrimary), greaterThanOrEqualTo(4.5));
    expect(
      _contrast(dark.secondary, dark.onSecondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(dark.tertiary, dark.onTertiary),
      greaterThanOrEqualTo(4.5),
    );
    expect(UcrTheme.light.textTheme.bodyMedium?.fontFamily, 'Arial');
    expect(UcrTheme.dark.textTheme.bodyMedium?.fontFamily, 'Arial');
  });
}
