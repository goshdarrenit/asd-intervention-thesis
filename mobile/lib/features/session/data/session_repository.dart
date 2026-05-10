import 'package:uuid/uuid.dart';
import 'session_local_datasource.dart';
import 'session_remote_datasource.dart';

/// Session repository implementing offline-first pattern
///
/// Key pattern: Local write FIRST, then attempt remote sync.
/// If remote fails, data persists locally with synced=0 and will be synced later.
/// This ensures no data loss and smooth UX even without network.
class SessionRepository {
  final SessionLocalDataSource _localDataSource;
  final SessionRemoteDataSource _remoteDataSource;

  SessionRepository({
    required SessionLocalDataSource localDataSource,
    required SessionRemoteDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource;

  /// Start new session with offline-first pattern.
  ///
  /// 1. Try backend start first (preferred, returns canonical remote session ID)
  /// 2. Mirror the session locally with synced=1 when online
  /// 3. If backend is unavailable, fall back to local-only session (synced=0)
  Future<String> startSession(String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final response = await _remoteDataSource.startSession(userId);
      final remoteId = response['session_id'] as String;

      await _localDataSource.insertSession({
        'id': remoteId,
        'user_id': userId,
        'started_at': now,
        'scenarios_completed': 0,
        'max_scenarios': 20,
        'max_duration_minutes': 30,
        'synced': 1,
        'remote_session_id': remoteId,
      });

      return remoteId;
    } catch (e) {
      // Backend unavailable: continue offline with a local session ID.
      final sessionId = const Uuid().v4();
      await _localDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'scenarios_completed': 0,
        'max_scenarios': 20,
        'max_duration_minutes': 30,
        'synced': 0,
      });
      return sessionId;
    }
  }

  /// End session with offline-first pattern.
  ///
  /// 1. Update local DB immediately with ended_at
  /// 2. Attempt remote sync (fire and forget)
  Future<void> endSession(String sessionId) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Update local DB immediately
    await _localDataSource.updateSession(sessionId, {
      'ended_at': now,
      'synced': 0, // Mark as unsynced since ended_at changed
    });

    // Attempt remote sync (fire and forget)
    try {
      // Get remote_session_id from local record
      final unsynced = await _localDataSource.getUnsyncedSessions();
      final session = unsynced.firstWhere(
        (s) => s['id'] == sessionId,
        orElse: () => {},
      );

      if (session.isNotEmpty && session['remote_session_id'] != null) {
        final remoteId = session['remote_session_id'] as String;
        await _remoteDataSource.endSession(remoteId);
        await _localDataSource.markSessionSynced(sessionId, remoteId);
      }
    } catch (e) {
      // Sync failed - will retry later
    }
  }

  /// Submit scenario result with offline-first pattern.
  ///
  /// 1. Write to local DB immediately
  /// 2. Increment session scenarios_completed counter
  /// 3. Remote sync handled by periodic sync service
  Future<void> submitResult(
    String sessionId,
    Map<String, dynamic> result,
  ) async {
    final resultId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Write result to local DB
    await _localDataSource.insertResult({
      'id': resultId,
      'session_id': sessionId,
      'scenario_type': result['scenario_type'],
      'difficulty': result['difficulty'],
      'outcome': result['outcome'],
      'reward': result['reward'],
      'completion_time_ms': result['completion_time_ms'],
      'created_at': now,
      'synced': 0,
    });

    // Increment session counter
    final count = await _localDataSource.getScenarioCountForSession(sessionId);
    await _localDataSource.updateSession(sessionId, {
      'scenarios_completed': count,
    });
  }

  /// Get scenario count for session (local only).
  Future<int> getScenarioCount(String sessionId) async {
    return await _localDataSource.getScenarioCountForSession(sessionId);
  }

  /// Get active session for user (local only).
  Future<Map<String, dynamic>?> getActiveSession(String userId) async {
    return await _localDataSource.getActiveSession(userId);
  }

  /// Get all results for session (local only).
  Future<List<Map<String, dynamic>>> getResultsForSession(
    String sessionId,
  ) async {
    return await _localDataSource.getResultsForSession(sessionId);
  }
}
