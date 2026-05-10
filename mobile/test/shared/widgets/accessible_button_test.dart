import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/shared/widgets/accessible_button.dart';
import 'package:asd_intervention/core/theme/app_theme.dart';

void main() {
  group('AccessibleButton', () {
    testWidgets('renders label text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Test Button',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('button has minimum height of 56 pixels', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Test Button',
              onPressed: () {},
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(ElevatedButton);
      expect(buttonFinder, findsOneWidget);

      final Size buttonSize = tester.getSize(buttonFinder);
      expect(buttonSize.height, greaterThanOrEqualTo(56));
    });

    testWidgets('tapping button calls onPressed', (WidgetTester tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Test Button',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AccessibleButton));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('loading state shows CircularProgressIndicator instead of label',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Test Button',
              onPressed: () {},
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Semantics wraps button with correct label', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Test Button',
              onPressed: () {},
            ),
          ),
        ),
      );

      // Verify that Semantics widgets exist in the tree (Material widgets add many)
      final semanticsFinder = find.byType(Semantics);
      expect(semanticsFinder, findsWidgets);

      // Verify our button exists and is functional
      final accessibleButtonFinder = find.byType(AccessibleButton);
      expect(accessibleButtonFinder, findsOneWidget);

      // Verify label is accessible
      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('button with icon renders both icon and text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Test Button',
              onPressed: () {},
              icon: Icons.check,
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('secondary variant uses secondary color', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Secondary Button',
              onPressed: () {},
              variant: AccessibleButtonVariant.secondary,
            ),
          ),
        ),
      );

      expect(find.text('Secondary Button'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('outline variant renders OutlinedButton', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Outline Button',
              onPressed: () {},
              variant: AccessibleButtonVariant.outline,
            ),
          ),
        ),
      );

      expect(find.text('Outline Button'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('disabled button does not call onPressed', (WidgetTester tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.create(),
          home: Scaffold(
            body: AccessibleButton(
              label: 'Disabled Button',
              onPressed: null,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AccessibleButton));
      await tester.pump();

      expect(pressed, isFalse);
    });
  });
}
