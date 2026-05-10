import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/features/scenarios/game/difficulty_config.dart';

void main() {
  group('DifficultyConfig', () {
    test('all scenario types return valid configs for all combinations', () {
      final scenarios = [
        'sharing',
        'patience',
        'emotion_recognition',
        'turn_taking',
        'conflict_resolution'
      ];
      final difficulties = [1, 2, 3, 4, 5];
      final complexities = ['low', 'medium', 'high'];

      for (final scenario in scenarios) {
        for (final difficulty in difficulties) {
          for (final complexity in complexities) {
            final config =
                DifficultyConfig.getConfig(scenario, difficulty, complexity);
            expect(config, isNotEmpty,
                reason:
                    '$scenario d$difficulty $complexity should return config');
          }
        }
      }
    });

    test('invalid scenario type returns empty config', () {
      final config = DifficultyConfig.getConfig('invalid', 3, 'medium');
      expect(config, isEmpty);
    });

    group('Sharing scenario', () {
      test('difficulty 1 vs 5 shows >30% change in drag distance', () {
        final d1 = DifficultyConfig.getConfig('sharing', 1, 'low');
        final d5 = DifficultyConfig.getConfig('sharing', 5, 'low');

        final distance1 = d1['drag_distance'] as double;
        final distance5 = d5['drag_distance'] as double;

        final percentChange = (distance5 - distance1) / distance1;
        expect(percentChange, greaterThan(0.30),
            reason: 'Drag distance should increase >30% from d1 to d5');
      });

      test('complexity changes toy count, not time parameters', () {
        final low = DifficultyConfig.getConfig('sharing', 3, 'low');
        final high = DifficultyConfig.getConfig('sharing', 3, 'high');

        // Element counts should differ
        expect(low['toys'], lessThan(high['toys']));

        // Time parameters should be the same (same difficulty)
        expect(low['time_limit_seconds'], equals(high['time_limit_seconds']));
        expect(low['drag_distance'], equals(high['drag_distance']));
      });

      test('time limit increases with difficulty', () {
        final d1 = DifficultyConfig.getConfig('sharing', 1, 'low');
        final d5 = DifficultyConfig.getConfig('sharing', 5, 'low');

        // d1 has no time limit, d5 has strict time limit
        expect(d1['time_limit_seconds'], isNull);
        expect(d5['time_limit_seconds'], isNotNull);
      });
    });

    group('Patience scenario', () {
      test('difficulty 1 vs 5 shows >30% change in wait time', () {
        final d1 = DifficultyConfig.getConfig('patience', 1, 'low');
        final d5 = DifficultyConfig.getConfig('patience', 5, 'low');

        final wait1 = d1['wait_seconds'] as int;
        final wait5 = d5['wait_seconds'] as int;

        final percentChange = (wait5 - wait1) / wait1;
        expect(percentChange, greaterThan(0.30),
            reason: 'Wait time should increase >30% from d1 to d5');
      });

      test('complexity changes reward count, not time parameters', () {
        final low = DifficultyConfig.getConfig('patience', 3, 'low');
        final high = DifficultyConfig.getConfig('patience', 3, 'high');

        // Element counts should differ
        expect(low['reward_count'], lessThan(high['reward_count']));

        // Time parameters should be the same (same difficulty)
        expect(low['wait_seconds'], equals(high['wait_seconds']));
        expect(
            low['early_tap_penalty'], equals(high['early_tap_penalty']));
      });
    });

    group('Emotion Recognition scenario', () {
      test('difficulty 1 vs 5 shows >30% increase in emotion count', () {
        final d1 = DifficultyConfig.getConfig('emotion_recognition', 1, 'low');
        final d5 = DifficultyConfig.getConfig('emotion_recognition', 5, 'low');

        final emotions1 = (d1['emotion_set'] as List).length;
        final emotions5 = (d5['emotion_set'] as List).length;

        final percentChange = (emotions5 - emotions1) / emotions1;
        expect(percentChange, greaterThan(0.30),
            reason: 'Emotion count should increase >30% from d1 to d5');
      });

      test('complexity changes face count, not emotion set', () {
        final low = DifficultyConfig.getConfig('emotion_recognition', 3, 'low');
        final high =
            DifficultyConfig.getConfig('emotion_recognition', 3, 'high');

        // Element counts should differ
        expect(low['face_count'], lessThan(high['face_count']));

        // Emotion set should be the same (same difficulty)
        expect(low['emotion_set'], equals(high['emotion_set']));
      });
    });

    group('Turn Taking scenario', () {
      test('difficulty 1 vs 5 shows >30% decrease in AI delay', () {
        final d1 = DifficultyConfig.getConfig('turn_taking', 1, 'low');
        final d5 = DifficultyConfig.getConfig('turn_taking', 5, 'low');

        final delay1 = d1['ai_turn_delay_ms'] as int;
        final delay5 = d5['ai_turn_delay_ms'] as int;

        // Delay should decrease (faster = harder)
        final percentChange = (delay1 - delay5) / delay1;
        expect(percentChange, greaterThan(0.30),
            reason: 'AI delay should decrease >30% from d1 to d5');
      });

      test('complexity changes turn count, not time parameters', () {
        final low = DifficultyConfig.getConfig('turn_taking', 3, 'low');
        final high = DifficultyConfig.getConfig('turn_taking', 3, 'high');

        // Element counts should differ
        expect(low['turn_count'], lessThan(high['turn_count']));

        // Time parameters should be the same (same difficulty)
        expect(low['ai_turn_delay_ms'], equals(high['ai_turn_delay_ms']));
      });
    });

    group('Conflict Resolution scenario', () {
      test('difficulty 1 vs 5 shows increased wrong choice penalty', () {
        final d1 = DifficultyConfig.getConfig('conflict_resolution', 1, 'low');
        final d5 = DifficultyConfig.getConfig('conflict_resolution', 5, 'low');

        final penalty1 = d1['wrong_choice_penalty'] as double;
        final penalty5 = d5['wrong_choice_penalty'] as double;

        // Penalty should increase significantly
        expect(penalty5, greaterThan(penalty1));
        expect(penalty5 - penalty1, greaterThanOrEqualTo(0.3));
      });

      test('complexity changes choice levels, not time parameters', () {
        final low = DifficultyConfig.getConfig('conflict_resolution', 3, 'low');
        final high =
            DifficultyConfig.getConfig('conflict_resolution', 3, 'high');

        // Element counts should differ
        expect(low['levels'], lessThan(high['levels']));

        // Time parameters should be the same (same difficulty)
        expect(
            low['time_limit_seconds'], equals(high['time_limit_seconds']));
        expect(low['wrong_choice_penalty'],
            equals(high['wrong_choice_penalty']));
      });
    });
  });
}
