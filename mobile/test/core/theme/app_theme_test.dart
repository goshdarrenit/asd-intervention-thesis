import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/core/theme/app_theme.dart';
import 'package:asd_intervention/core/theme/app_colors.dart';

void main() {
  group('AppTheme', () {
    test('create() returns valid ThemeData', () {
      final theme = AppTheme.create();
      expect(theme, isA<ThemeData>());
      expect(theme.useMaterial3, isTrue);
    });

    test('colorScheme.primary matches AppColors.primary', () {
      final theme = AppTheme.create();
      expect(theme.colorScheme.primary, equals(AppColors.primary));
    });

    test('ElevatedButton minimumSize height is at least 56', () {
      final theme = AppTheme.create();
      final buttonStyle = theme.elevatedButtonTheme.style;
      final minimumSize = buttonStyle?.minimumSize?.resolve({});
      expect(minimumSize, isNotNull);
      expect(minimumSize!.height, greaterThanOrEqualTo(56));
    });

    test('OutlinedButton minimumSize height is at least 56', () {
      final theme = AppTheme.create();
      final buttonStyle = theme.outlinedButtonTheme.style;
      final minimumSize = buttonStyle?.minimumSize?.resolve({});
      expect(minimumSize, isNotNull);
      expect(minimumSize!.height, greaterThanOrEqualTo(56));
    });

    test('TextButton minimumSize height is at least 56', () {
      final theme = AppTheme.create();
      final buttonStyle = theme.textButtonTheme.style;
      final minimumSize = buttonStyle?.minimumSize?.resolve({});
      expect(minimumSize, isNotNull);
      expect(minimumSize!.height, greaterThanOrEqualTo(56));
    });

    test('bodyLarge fontSize is at least 18', () {
      final theme = AppTheme.create();
      final fontSize = theme.textTheme.bodyLarge?.fontSize;
      expect(fontSize, isNotNull);
      expect(fontSize, greaterThanOrEqualTo(18));
    });

    test('scaffold background is NOT pure white', () {
      final theme = AppTheme.create();
      expect(theme.scaffoldBackgroundColor, isNot(equals(const Color(0xFFFFFFFF))));
      expect(theme.scaffoldBackgroundColor, equals(AppColors.background));
    });

    test('card theme has rounded corners', () {
      final theme = AppTheme.create();
      final cardShape = theme.cardTheme.shape;
      expect(cardShape, isA<RoundedRectangleBorder>());
      final roundedShape = cardShape as RoundedRectangleBorder;
      expect(roundedShape.borderRadius, equals(BorderRadius.circular(16)));
    });

    test('AppBar uses primary color', () {
      final theme = AppTheme.create();
      expect(theme.appBarTheme.backgroundColor, equals(AppColors.primary));
      expect(theme.appBarTheme.foregroundColor, equals(Colors.white));
      expect(theme.appBarTheme.centerTitle, isTrue);
    });
  });
}
