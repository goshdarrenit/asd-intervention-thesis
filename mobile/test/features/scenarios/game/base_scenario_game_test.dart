import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/features/scenarios/game/base_scenario_game.dart';
import 'package:asd_intervention/features/scenarios/game/game_config.dart';

/// Test implementation of BaseScenarioGame
class TestScenarioGame extends BaseScenarioGame {
  TestScenarioGame({required super.config});

  // Track whether extension points are called
  bool loadScenarioCalled = false;
  bool updateScenarioCalled = false;
  int updateScenarioCallCount = 0;

  @override
  Future<void> loadScenario() async {
    loadScenarioCalled = true;
    await super.loadScenario();
  }

  @override
  void updateScenario(double dt) {
    updateScenarioCalled = true;
    updateScenarioCallCount++;
    super.updateScenario(dt);
  }
}

void main() {
  group('BaseScenarioGame', () {
    late GameConfig config;

    setUp(() {
      config = const GameConfig(
        scenarioType: 'sharing',
        difficulty: 3,
        sessionId: 'test-session',
        userId: 'test-user',
      );
    });

    test('creates without errors given a GameConfig', () {
      final game = TestScenarioGame(config: config);
      expect(game.config, equals(config));
      expect(game.isPaused, isFalse);
      expect(game.isComplete, isFalse);
    });

    test('onLoad initializes game and calls loadScenario', () async {
      final game = TestScenarioGame(config: config);
      await game.onLoad();

      expect(game.loadScenarioCalled, isTrue);
      expect(game.tempVelocity, isNotNull);
      expect(game.tempPosition, isNotNull);
    });

    test('update calls updateScenario when not paused or complete', () async {
      final game = TestScenarioGame(config: config);
      await game.onLoad();

      expect(game.updateScenarioCalled, isFalse);

      game.update(0.016);

      expect(game.updateScenarioCalled, isTrue);
      expect(game.updateScenarioCallCount, equals(1));
    });

    test('update returns early when isPaused is true', () async {
      final game = TestScenarioGame(config: config);
      await game.onLoad();

      // Update once to verify it works
      game.update(0.016);
      expect(game.updateScenarioCalled, isTrue);
      expect(game.updateScenarioCallCount, equals(1));

      // Set paused state and verify update doesn't call updateScenario
      game.setIsPausedForTest(true);
      game.updateScenarioCalled = false;

      game.update(0.016);
      expect(game.updateScenarioCalled, isFalse);
      expect(game.updateScenarioCallCount, equals(1)); // Still 1, not 2
    });

    test('update returns early when isComplete is true', () async {
      final game = TestScenarioGame(config: config);
      await game.onLoad();

      // Update once to verify it works
      game.update(0.016);
      expect(game.updateScenarioCalled, isTrue);
      expect(game.updateScenarioCallCount, equals(1));

      // Set complete state and verify update doesn't call updateScenario
      game.setIsCompleteForTest(true);
      game.updateScenarioCalled = false;

      game.update(0.016);
      expect(game.updateScenarioCalled, isFalse);
      expect(game.updateScenarioCallCount, equals(1)); // Still 1, not 2
    });

    test('elapsedMs increases over time', () async {
      final game = TestScenarioGame(config: config);
      await game.onLoad();

      expect(game.elapsedMs, equals(0));

      // Simulate time passing with multiple updates
      for (int i = 0; i < 60; i++) {
        game.update(0.016); // 16ms per frame (60 FPS)
        await Future.delayed(const Duration(milliseconds: 1));
      }

      // ElapsedMs should be greater than 0 after updates
      expect(game.elapsedMs, greaterThan(0));
    });

    test('pre-allocated Vector2 objects are available', () async {
      final game = TestScenarioGame(config: config);
      await game.onLoad();

      // Verify Vector2 objects are pre-allocated
      final velocity = game.tempVelocity;
      final position = game.tempPosition;

      expect(velocity, isNotNull);
      expect(position, isNotNull);

      // Verify they can be modified without creating new instances
      velocity.setValues(10.0, 20.0);
      position.setValues(100.0, 200.0);

      expect(velocity.x, equals(10.0));
      expect(velocity.y, equals(20.0));
      expect(position.x, equals(100.0));
      expect(position.y, equals(200.0));
    });

    test('config is accessible', () {
      final game = TestScenarioGame(config: config);

      expect(game.config.scenarioType, equals('sharing'));
      expect(game.config.difficulty, equals(3));
      expect(game.config.sessionId, equals('test-session'));
      expect(game.config.userId, equals('test-user'));
    });

    test('isPaused, isComplete, elapsedMs getters work', () async {
      final game = TestScenarioGame(config: config);
      await game.onLoad();

      // Initial state
      expect(game.isPaused, isFalse);
      expect(game.isComplete, isFalse);
      expect(game.elapsedMs, equals(0));

      // Change state
      game.setIsPausedForTest(true);
      expect(game.isPaused, isTrue);

      game.setIsCompleteForTest(true);
      expect(game.isComplete, isTrue);
    });
  });

  group('ScenarioOutcome', () {
    test('creates with correct values', () {
      final outcome = ScenarioOutcome(
        success: true,
        reward: 0.85,
        completionTimeMs: 12500,
        scenarioType: 'patience',
        difficulty: 4,
        telemetry: {'pause_count': 3, 'retry_count': 1},
      );

      expect(outcome.success, isTrue);
      expect(outcome.reward, equals(0.85));
      expect(outcome.completionTimeMs, equals(12500));
      expect(outcome.scenarioType, equals('patience'));
      expect(outcome.difficulty, equals(4));
      expect(outcome.telemetry['pause_count'], equals(3));
      expect(outcome.telemetry['retry_count'], equals(1));
    });

    test('handles empty telemetry', () {
      final outcome = ScenarioOutcome(
        success: false,
        reward: 0.2,
        completionTimeMs: 8000,
        scenarioType: 'sharing',
        difficulty: 1,
      );

      expect(outcome.telemetry, isEmpty);
    });
  });

  group('GameConfig', () {
    test('creates with correct values', () {
      const config = GameConfig(
        scenarioType: 'emotion_recognition',
        difficulty: 5,
        sessionId: 'sess-123',
        userId: 'user-456',
      );

      expect(config.scenarioType, equals('emotion_recognition'));
      expect(config.difficulty, equals(5));
      expect(config.sessionId, equals('sess-123'));
      expect(config.userId, equals('user-456'));
    });
  });
}
