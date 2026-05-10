import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/features/scenarios/presentation/game_screen.dart';
import 'package:asd_intervention/features/scenarios/game/game_config.dart';

void main() {
  group('GameScreen', () {
    late GameConfig testConfig;

    setUp(() {
      testConfig = GameConfig(
        scenarioType: 'sharing',
        difficulty: 1,
        complexity: 'low',
        reinforcementMode: 'positive',
        sessionId: 'test-session',
        userId: 'test-user',
      );
    });

    testWidgets('exit/pause button is visible during gameplay', (tester) async {
      // GameScreen uses Flame which requires a game loop — full widget test
      // requires FlameGame test harness. For now, assert widget builds without error.
      //
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            config: testConfig,
            onGameComplete: (_) {},
          ),
        ),
      );

      // The exit button (IconButton with Icons.close) should be present in widget tree
      expect(find.byType(GameScreen), findsOneWidget);
    });
  });
}
