import 'dart:math';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../profile/data/profile_local_datasource.dart';
import '../game/game_config.dart';

const _kTestSharingOnly = false;

/// Service for scenario selection and result submission with offline fallback.
///
/// Features:
/// - Get next scenario from backend RL model
/// - Submit scenario result with telemetry
/// - Offline fallback: cached difficulty + random scenario type
/// - Caches last difficulty for offline use
class ScenarioApiService {
  final ApiClient _apiClient;
  final ProfileLocalDataSource _profileDataSource;
  final _random = Random();

  /// Tracks the last scenario type returned so we can avoid back-to-back repeats.
  String? _lastScenarioType;

  ScenarioApiService(this._apiClient, this._profileDataSource);

  /// Get next scenario config from backend with offline fallback.
  ///
  /// Returns GameConfig with scenario_type, difficulty, complexity from RL model.
  /// On network error, falls back to cached difficulty and random scenario type.
  ///
  /// [forceEasier] overrides difficulty to 1 after 3 consecutive failures.
  Future<GameConfig> getNextScenario(
    String userId,
    String sessionId, {
    bool forceEasier = false,  // override difficulty to 1 after 3 failures
  }) async {
    try {
      final response = await _apiClient.getNextScenario(userId, sessionId);
      final difficulty = response['difficulty'] as int;

      // Cache difficulty for offline fallback
      await _profileDataSource.cacheLastDifficulty(userId, difficulty);

      final rawType = _kTestSharingOnly
          ? 'sharing'
          : response['scenario_type'] as String;
      final scenarioType = _nonRepeatingType(rawType);
      _lastScenarioType = scenarioType;

      if (forceEasier) {
        return GameConfig(
          scenarioType: scenarioType,
          difficulty: 1,          // force easiest difficulty
          complexity: 'low',
          reinforcementMode: 'positive',
          sessionId: sessionId,
          userId: userId,
        );
      }

      return GameConfig(
        scenarioType: scenarioType,
        difficulty: difficulty,
        complexity: response['complexity'] as String? ?? 'low',
        reinforcementMode: response['reinforcement_mode'] as String? ?? 'positive',
        sessionId: sessionId,
        userId: userId,
      );
    } on DioException {
      // Offline fallback: use cached difficulty, non-repeating random scenario type
      return await _offlineFallback(userId, sessionId, forceEasier: forceEasier);
    }
  }

  /// Submit scenario result to backend.
  ///
  /// Returns emotions and reward from backend, or null if offline.
  /// When offline, result is already saved locally and will sync later.
  Future<Map<String, dynamic>?> submitResult({
    required String userId,
    required String sessionId,
    required ScenarioOutcome outcome,
    required String complexity,
    required String reinforcementMode,
  }) async {
    try {
      return await _apiClient.submitScenarioResult(
        userId: userId,
        sessionId: sessionId,
        scenarioType: outcome.scenarioType,
        difficulty: outcome.difficulty,
        complexity: complexity,
        reinforcementMode: reinforcementMode,
        success: outcome.success,
        completionTimeMs: outcome.completionTimeMs,
        telemetry: outcome.telemetry,
      );
    } on DioException {
      // Offline: result already saved locally by SessionManager
      // Will sync when network available via SyncService
      return null;
    }
  }

  /// Offline fallback: cached difficulty + non-repeating random scenario type.
  Future<GameConfig> _offlineFallback(
    String userId,
    String sessionId, {
    bool forceEasier = false,
  }) async {
    final cachedDifficulty = await _profileDataSource.getLastDifficulty(userId);
    final difficulty = forceEasier ? 1 : cachedDifficulty;

    final randomType = _kTestSharingOnly ? 'sharing' : _nonRepeatingType(null);
    _lastScenarioType = randomType;

    return GameConfig(
      scenarioType: randomType,
      difficulty: difficulty,
      complexity: 'low',
      reinforcementMode: 'positive',
      sessionId: sessionId,
      userId: userId,
    );
  }

  /// Returns [preferred] if it differs from the last scenario, otherwise picks
  /// a random type from the remaining four. Pass null to pick any non-repeating type.
  String _nonRepeatingType(String? preferred) {
    const types = [
      'sharing',
      'patience',
      'emotion_recognition',
      'turn_taking',
      'conflict_resolution',
    ];

    if (preferred != null && preferred != _lastScenarioType) return preferred;

    final candidates = _lastScenarioType == null
        ? types
        : types.where((t) => t != _lastScenarioType).toList();
    return candidates[_random.nextInt(candidates.length)];
  }
}
