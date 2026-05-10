import 'package:flutter_test/flutter_test.dart';
import 'package:asd_intervention/features/session/domain/session_manager.dart';
import 'package:asd_intervention/features/session/data/session_repository.dart';
import 'package:asd_intervention/features/profile/data/profile_local_datasource.dart';
import 'package:asd_intervention/features/scenarios/game/game_config.dart';

/// Mock SessionRepository for testing
class MockSessionRepository implements SessionRepository {
  final List<Map<String, dynamic>> submittedResults = [];
  bool sessionEnded = false;

  @override
  Future<void> submitResult(String sessionId, Map<String, dynamic> result) async {
    submittedResults.add(result);
  }

  @override
  Future<void> endSession(String sessionId) async {
    sessionEnded = true;
  }

  // Unused methods for testing
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mock ProfileLocalDataSource for testing
class MockProfileLocalDataSource implements ProfileLocalDataSource {
  Map<String, dynamic>? mockProfile;
  Map<String, dynamic>? lastUpdate;

  @override
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    return mockProfile;
  }

  @override
  Future<void> updateProgress(
    String userId, {
    int? scenariosCompleted,
    double? successRate,
    int? currentLevel,
  }) async {
    lastUpdate = {
      'user_id': userId,
      'scenarios_completed': scenariosCompleted,
      'success_rate': successRate,
      'current_level': currentLevel,
    };
  }

  // Unused methods for testing
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SessionManager', () {
    late MockSessionRepository mockRepository;
    late MockProfileLocalDataSource mockProfileDataSource;

    setUp(() {
      mockRepository = MockSessionRepository();
      mockProfileDataSource = MockProfileLocalDataSource();
      mockProfileDataSource.mockProfile = {
        'user_id': 'test-user',
        'scenarios_completed': 10,
        'success_rate': 0.75,
        'current_level': 2,
      };
    });

    test('canPlayNextScenario returns true when within limits', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      expect(manager.canPlayNextScenario(), true);
    });

    test('canPlayNextScenario returns false after 20 scenarios', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      // Record 20 scenarios
      for (int i = 0; i < 20; i++) {
        final outcome = ScenarioOutcome(
          success: true,
          reward: 0.8,
          completionTimeMs: 5000,
          scenarioType: 'sharing',
          difficulty: 1,
        );
        await manager.recordScenarioCompletion(outcome);
      }

      expect(manager.canPlayNextScenario(), false);
    });

    test('recordScenarioCompletion returns scenarioLimitReached after 20th scenario', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      SessionStatus? lastStatus;

      // Record 19 scenarios
      for (int i = 0; i < 19; i++) {
        final outcome = ScenarioOutcome(
          success: true,
          reward: 0.8,
          completionTimeMs: 5000,
          scenarioType: 'sharing',
          difficulty: 1,
        );
        lastStatus = await manager.recordScenarioCompletion(outcome);
        expect(lastStatus, SessionStatus.continuePlay);
      }

      // 20th scenario should trigger limit
      final finalOutcome = ScenarioOutcome(
        success: true,
        reward: 0.8,
        completionTimeMs: 5000,
        scenarioType: 'sharing',
        difficulty: 1,
      );
      lastStatus = await manager.recordScenarioCompletion(finalOutcome);

      expect(lastStatus, SessionStatus.scenarioLimitReached);
      expect(mockRepository.sessionEnded, true);
    });

    test('remainingScenarios decrements correctly', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      expect(manager.remainingScenarios, 20);

      // Record 5 scenarios
      for (int i = 0; i < 5; i++) {
        final outcome = ScenarioOutcome(
          success: true,
          reward: 0.8,
          completionTimeMs: 5000,
          scenarioType: 'sharing',
          difficulty: 1,
        );
        await manager.recordScenarioCompletion(outcome);
      }

      expect(manager.remainingScenarios, 15);
    });

    test('session can be ended and _isEnded flag is set', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      expect(manager.canPlayNextScenario(), true);

      await manager.endSession();

      expect(manager.canPlayNextScenario(), false);
      expect(mockRepository.sessionEnded, true);
    });

    test('canPlayNextScenario returns false after endSession() called', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      await manager.endSession();

      expect(manager.canPlayNextScenario(), false);
    });

    test('canPlayNextScenario returns false when time limit reached', () async {
      // Create manager with 0 minute duration (immediate expiry)
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 0,
        maxScenarios: 20,
      );

      await manager.start();

      // Allow time check to be evaluated
      await Future.delayed(const Duration(milliseconds: 50));

      expect(manager.canPlayNextScenario(), false);
    });

    test('scenariosCompleted tracks count correctly', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      expect(manager.scenariosCompleted, 0);

      // Record 3 scenarios
      for (int i = 0; i < 3; i++) {
        final outcome = ScenarioOutcome(
          success: true,
          reward: 0.8,
          completionTimeMs: 5000,
          scenarioType: 'sharing',
          difficulty: 1,
        );
        await manager.recordScenarioCompletion(outcome);
      }

      expect(manager.scenariosCompleted, 3);
    });

    test('endSession updates profile progress', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );

      await manager.start();

      // Record 5 scenarios
      for (int i = 0; i < 5; i++) {
        final outcome = ScenarioOutcome(
          success: true,
          reward: 0.8,
          completionTimeMs: 5000,
          scenarioType: 'sharing',
          difficulty: 1,
        );
        await manager.recordScenarioCompletion(outcome);
      }

      // End session should update profile
      await manager.endSession();

      // Check that profile was updated
      expect(mockProfileDataSource.lastUpdate, isNotNull);
      expect(mockProfileDataSource.lastUpdate!['scenarios_completed'], 15); // 10 + 5
      expect(mockProfileDataSource.lastUpdate!['current_level'], 2); // (15 ~/ 10) + 1
    });

    test('consecutiveFailures increments on failure and resets on success', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );
      await manager.start();

      final failure = ScenarioOutcome(
        success: false, reward: 0.3, completionTimeMs: 30000,
        scenarioType: 'sharing', difficulty: 2,
      );
      final success = ScenarioOutcome(
        success: true, reward: 0.9, completionTimeMs: 8000,
        scenarioType: 'sharing', difficulty: 2,
      );

      await manager.recordScenarioCompletion(failure);
      expect(manager.consecutiveFailures, 1);      // NEW getter — will fail until 08-01 adds it

      await manager.recordScenarioCompletion(failure);
      expect(manager.consecutiveFailures, 2);

      await manager.recordScenarioCompletion(success);
      expect(manager.consecutiveFailures, 0);      // reset on success
    });

    test('shouldForceEasier is true after 3 consecutive failures', () async {
      final manager = SessionManager(
        repository: mockRepository,
        profileDataSource: mockProfileDataSource,
        sessionId: 'test-session',
        userId: 'test-user',
        maxDurationMinutes: 30,
        maxScenarios: 20,
      );
      await manager.start();

      final failure = ScenarioOutcome(
        success: false, reward: 0.3, completionTimeMs: 30000,
        scenarioType: 'patience', difficulty: 3,
      );

      expect(manager.shouldForceEasier, false);    // NEW getter — will fail until 08-01 adds it

      await manager.recordScenarioCompletion(failure);
      await manager.recordScenarioCompletion(failure);
      expect(manager.shouldForceEasier, false);    // only 2, not yet 3

      await manager.recordScenarioCompletion(failure);
      expect(manager.shouldForceEasier, true);     // 3rd failure triggers
    });
  });
}
