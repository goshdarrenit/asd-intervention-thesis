/// Configuration and outcome data structures for scenario games
library;

/// Configuration for a scenario game session
class GameConfig {
  /// Type of scenario: sharing, patience, emotion_recognition, turn_taking, conflict_resolution
  final String scenarioType;

  /// Difficulty level: 1-5
  final int difficulty;

  /// Complexity level: 'low', 'medium', 'high'
  /// Controls number of active elements (not time pressure)
  final String complexity;

  /// Reinforcement mode: 'positive', 'negative', 'mixed'
  final String reinforcementMode;

  /// Backend session ID for telemetry upload
  final String sessionId;

  /// User ID for personalization
  final String userId;

  const GameConfig({
    required this.scenarioType,
    required this.difficulty,
    required this.sessionId,
    required this.userId,
    this.complexity = 'low',
    this.reinforcementMode = 'positive',
  });

  @override
  String toString() =>
      'GameConfig(scenarioType: $scenarioType, difficulty: $difficulty, complexity: $complexity, reinforcementMode: $reinforcementMode, sessionId: $sessionId, userId: $userId)';
}

/// Outcome data from a completed scenario
class ScenarioOutcome {
  /// Whether the scenario was completed successfully
  final bool success;

  /// Reward value (0.0 - 1.0) from backend RL model
  final double reward;

  /// Time taken to complete scenario in milliseconds
  final int completionTimeMs;

  /// Scenario type that was played
  final String scenarioType;

  /// Difficulty level of the scenario
  final int difficulty;

  /// Behavioral telemetry data for emotion inference
  /// Contains: pause_count, retry_count, quit_attempts, completion_time_ms, etc.
  final Map<String, dynamic> telemetry;

  const ScenarioOutcome({
    required this.success,
    required this.reward,
    required this.completionTimeMs,
    required this.scenarioType,
    required this.difficulty,
    this.telemetry = const {},
  });

  @override
  String toString() =>
      'ScenarioOutcome(success: $success, reward: $reward, completionTimeMs: $completionTimeMs, scenarioType: $scenarioType, difficulty: $difficulty)';
}
