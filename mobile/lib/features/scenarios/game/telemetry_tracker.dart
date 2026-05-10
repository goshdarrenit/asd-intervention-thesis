/// Collects behavioral signals during scenario gameplay:
/// - Pause/retry/quit counts for frustration detection
/// - Action timestamps and counts for hesitation patterns
/// - Decision-making patterns for confidence assessment
/// Performance: Simple int/List operations, no per-frame allocations.
class TelemetryTracker {
  /// Number of times user paused the scenario
  int pauseCount = 0;

  /// Number of times user retried an action
  int retryCount = 0;

  /// Number of times user attempted to quit
  int quitAttempts = 0;

  /// Timestamps (milliseconds) of key user decisions/actions
  final List<int> decisionTimestampsMs = [];

  /// Count of each action type (e.g., {'drag': 5, 'tap': 3})
  final Map<String, int> actionCounts = {};

  /// Record a user action with timestamp
  ///
  /// [action] - Type of action (e.g., 'drag', 'tap', 'drop')
  /// [timestampMs] - Millisecond timestamp of the action
  void recordAction(String action, int timestampMs) {
    actionCounts[action] = (actionCounts[action] ?? 0) + 1;
    decisionTimestampsMs.add(timestampMs);
  }

  /// Record a pause event (user paused the game)
  void recordPause() {
    pauseCount++;
  }

  /// Record a retry event (user retried an action)
  void recordRetry() {
    retryCount++;
  }

  /// Record a quit attempt (user tried to exit scenario)
  void recordQuitAttempt() {
    quitAttempts++;
  }

  /// Calculate average time between decisions
  ///
  /// Returns 0.0 if fewer than 2 decisions recorded.
  /// Used to detect hesitation patterns.
  double _calculateHesitationPattern() {
    if (decisionTimestampsMs.length < 2) return 0.0;

    int totalGaps = 0;
    for (int i = 1; i < decisionTimestampsMs.length; i++) {
      totalGaps += decisionTimestampsMs[i] - decisionTimestampsMs[i - 1];
    }

    return totalGaps / (decisionTimestampsMs.length - 1);
  }

  /// Convert telemetry to JSON for backend emotion inference
  ///
  /// Returns map with all behavioral signals:
  /// - pause_count, retry_count, quit_attempts
  /// - action_counts (per action type)
  /// - decision_timestamps_ms
  /// - hesitation_pattern (average time between decisions)
  Map<String, dynamic> toJson() {
    return {
      'pause_count': pauseCount,
      'retry_count': retryCount,
      'quit_attempts': quitAttempts,
      'action_counts': Map<String, int>.from(actionCounts),
      'decision_timestamps_ms': List<int>.from(decisionTimestampsMs),
      'hesitation_pattern': _calculateHesitationPattern(),
    };
  }
}
