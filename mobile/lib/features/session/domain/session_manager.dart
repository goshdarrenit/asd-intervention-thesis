import 'dart:async';
import '../data/session_repository.dart';
import '../../../features/profile/data/profile_local_datasource.dart';
import '../../../features/home/providers.dart';
import '../../scenarios/game/game_config.dart';

/// Session status after scenario completion.
enum SessionStatus {
  continuePlay,
  scenarioLimitReached,
  timeLimitReached,
  ended,
}

/// Session manager that enforces time and scenario limits.
///
/// Tracks session progress and automatically ends session when:
/// - 30 minutes elapsed (time limit)
/// - 20 scenarios completed (scenario limit)
///
/// Supports resuming an interrupted session by accepting an optional [startTime]
/// (original session start) and [initialCompleted] count from the DB.
///
/// Profile progress (scenarios_completed, success_rate, level) is updated
/// incrementally after EACH scenario so no progress is lost if the session
/// is interrupted before endSession() is called.
class SessionManager {
  final SessionRepository _repository;
  final ProfileLocalDataSource _profileDataSource;
  final String _sessionId;
  final String _userId;
  final int maxDurationMinutes;
  final int maxScenarios;
  final DateTime _startTime;
  final void Function(SessionStatus)? onStatusChange;

  int _scenariosCompleted;
  int _scenariosSucceeded = 0;
  int _consecutiveFailures = 0;
  bool _isEnded = false;
  Timer? _durationTimer;

  SessionManager({
    required SessionRepository repository,
    required ProfileLocalDataSource profileDataSource,
    required String sessionId,
    required String userId,
    this.maxDurationMinutes = 30,
    this.maxScenarios = 20,
    this.onStatusChange,
    /// Pass the original session start time when resuming a paused session.
    /// Defaults to now for fresh sessions.
    DateTime? startTime,
    /// Number of scenarios already completed in this session (for resumes).
    int initialCompleted = 0,
  })  : _repository = repository,
        _profileDataSource = profileDataSource,
        _sessionId = sessionId,
        _userId = userId,
        _startTime = startTime ?? DateTime.now(),
        _scenariosCompleted = initialCompleted;

  /// Start session and initialise the duration timer.
  ///
  /// Uses the actual remaining time so resumed sessions count down correctly
  /// rather than getting a fresh 30-minute window.
  Future<void> start() async {
    final remaining = remainingTime;
    if (remaining <= Duration.zero) {
      // Time already expired (resumed a session that ran out while away)
      _onTimeLimitReached();
      return;
    }
    _durationTimer = Timer(remaining, _onTimeLimitReached);
  }

  /// Check if player can start next scenario.
  bool canPlayNextScenario() {
    if (_isEnded) return false;
    if (_scenariosCompleted >= maxScenarios) return false;
    if (_isTimeLimitReached) return false;
    return true;
  }

  /// Record scenario completion and check limits.
  ///
  /// Updates the user profile immediately after each scenario (incremental)
  /// so progress is never lost even if the session is interrupted.
  Future<SessionStatus> recordScenarioCompletion(ScenarioOutcome outcome) async {
    if (_isEnded) return SessionStatus.ended;

    if (outcome.success) {
      _scenariosSucceeded++;
      _consecutiveFailures = 0;  // reset on success
    } else {
      _consecutiveFailures++;    // increment on failure
    }
    _scenariosCompleted++;

    // Store result in repository
    await _repository.submitResult(_sessionId, {
      'scenario_type': outcome.scenarioType,
      'difficulty': outcome.difficulty,
      'outcome': outcome.success ? 'success' : 'failure',
      'reward': outcome.reward,
      'completion_time_ms': outcome.completionTimeMs,
    });

    // Persist progress immediately so it's never lost to an unawaited dispose
    await _updateProfileIncremental(outcome.success);

    // Check limits (defensive: check time even if timer hasn't fired)
    if (_isTimeLimitReached) {
      await endSession();
      _notifyStatusChange(SessionStatus.timeLimitReached);
      return SessionStatus.timeLimitReached;
    }

    if (_scenariosCompleted >= maxScenarios) {
      await endSession();
      _notifyStatusChange(SessionStatus.scenarioLimitReached);
      return SessionStatus.scenarioLimitReached;
    }

    _notifyStatusChange(SessionStatus.continuePlay);
    return SessionStatus.continuePlay;
  }

  /// Update the user profile after each scenario using a running weighted mean.
  ///
  /// Formula: new_rate = (old_count * old_rate + this_result) / new_count
  ///
  /// This gives the exact overall success rate across all time without needing
  /// to store a separate total_successes column.
  Future<void> _updateProfileIncremental(bool success) async {
    try {
      final profile = await _profileDataSource.getProfile(_userId);
      final currentCompleted = (profile?['scenarios_completed'] as int?) ?? 0;
      final currentRate = (profile?['success_rate'] as num?)?.toDouble() ?? 0.0;

      final newCompleted = currentCompleted + 1;
      // Weighted running mean — exact, not approximate
      final newRate =
          (currentCompleted * currentRate + (success ? 1.0 : 0.0)) / newCompleted;
      final newLevel = UserProgress.calculateLevel(newCompleted);

      await _profileDataSource.updateProgress(
        _userId,
        scenariosCompleted: newCompleted,
        currentLevel: newLevel,
        successRate: newRate,
      );
    } catch (_) {
      // Non-fatal — profile will be retried on next scenario
    }
  }

  /// End the session and mark it as ended in the repository.
  ///
  /// Profile progress is already up to date from incremental updates;
  /// this just writes the ended_at timestamp.
  Future<void> endSession() async {
    if (_isEnded) return;
    _isEnded = true;
    _durationTimer?.cancel();
    await _repository.endSession(_sessionId);
  }

  /// Get remaining time in session.
  Duration get remainingTime {
    final elapsed = DateTime.now().difference(_startTime);
    final maxDuration = Duration(minutes: maxDurationMinutes);
    final remaining = maxDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Get remaining scenarios in session.
  int get remainingScenarios {
    final remaining = maxScenarios - _scenariosCompleted;
    return remaining < 0 ? 0 : remaining;
  }

  /// Get current scenarios completed in this session.
  int get scenariosCompleted => _scenariosCompleted;

  /// Get elapsed time since session start.
  Duration get elapsedTime => DateTime.now().difference(_startTime);

  /// Get session ID.
  String get sessionId => _sessionId;

  /// Whether this session has been ended.
  bool get isEnded => _isEnded;

  /// Number of consecutive failures in this session.
  int get consecutiveFailures => _consecutiveFailures;

  /// Whether the next scenario should be forced to difficulty 1.
  /// True after 3 consecutive failures.
  bool get shouldForceEasier => _consecutiveFailures >= 3;

  /// Reset consecutive failure counter after force-easier intervention fires.
  /// Called by SessionWrapper after requesting the forced d1 scenario.
  void resetConsecutiveFailures() {
    _consecutiveFailures = 0;
  }

  /// Check if time limit has been reached (defensive check).
  bool get _isTimeLimitReached {
    final elapsed = DateTime.now().difference(_startTime);
    return elapsed.inMinutes >= maxDurationMinutes;
  }

  /// Dispose resources (cancel timer only — does NOT end the session so it
  /// remains resumable in the DB).
  void dispose() {
    _durationTimer?.cancel();
  }

  /// Callback when duration timer fires.
  void _onTimeLimitReached() async {
    if (!_isEnded) {
      await endSession();
      _notifyStatusChange(SessionStatus.timeLimitReached);
    }
  }

  /// Notify status change callback if provided.
  void _notifyStatusChange(SessionStatus status) {
    onStatusChange?.call(status);
  }
}
