import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/features/home/presentation/main_menu_screen.dart';
import 'package:asd_intervention/features/home/providers.dart';

void main() {
  group('MainMenuScreen', () {
    testWidgets('renders app title', (WidgetTester tester) async {
      // Provide a mock progress provider
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async => const UserProgress()),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      // Wait for async provider to load
      await tester.pumpAndSettle();

      expect(find.text('Social Skills Adventure'), findsOneWidget);
    });

    testWidgets('renders supportive subtitle', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async => const UserProgress()),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("Let's practice together!"), findsOneWidget);
    });

    testWidgets('displays progress cards with default values', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async => const UserProgress()),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Default values: 0 scenarios, level 1, 0% success
      expect(find.text('0'), findsOneWidget); // scenarios
      expect(find.text('1'), findsOneWidget); // level
      expect(find.text('0%'), findsOneWidget); // success rate
    });

    testWidgets('displays progress cards with real data', (WidgetTester tester) async {
      // Mock progress with known values
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async => const UserProgress(
              scenariosCompleted: 42,
              currentLevel: 5,
              successRate: 0.78,
            )),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('42'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget);
    });

    testWidgets('displays Start Playing button', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async => const UserProgress()),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Start Playing'), findsOneWidget);
    });

    testWidgets('Start Playing button is tappable', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async => const UserProgress()),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      await tester.pumpAndSettle();

      final button = find.text('Start Playing');
      expect(button, findsOneWidget);

      // Verify button is tappable (doesn't throw)
      await tester.tap(button);
      await tester.pumpAndSettle();
    });

    testWidgets('shows loading indicator while data loads', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async {
              // Simulate slow loading
              await Future.delayed(const Duration(milliseconds: 100));
              return const UserProgress();
            }),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      // Loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for load to complete
      await tester.pumpAndSettle();

      // Loading indicator should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('gracefully handles error with default values', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProgressProvider.overrideWith((ref) async {
              throw Exception('Database error');
            }),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Should show default values (graceful degradation)
      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });
  });
}
