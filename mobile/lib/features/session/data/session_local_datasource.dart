import 'package:sqflite/sqflite.dart';

/// Local data source for session and scenario result operations.
///
/// Implements offline-first pattern: all writes go to local SQLite first,
/// then sync to backend when network is available. Uses synced flag to track
/// which records need backend sync.
class SessionLocalDataSource {
  final Database _db;

  SessionLocalDataSource(this._db);

  /// Insert new session with synced=0 (needs sync).
  Future<void> insertSession(Map<String, dynamic> session) async {
    await _db.insert(
      'sessions',
      session,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update session fields.
  Future<void> updateSession(String id, Map<String, dynamic> updates) async {
    await _db.update(
      'sessions',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get most recent non-ended session for user.
  /// Returns null if no active session exists.
  Future<Map<String, dynamic>?> getActiveSession(String userId) async {
    final results = await _db.query(
      'sessions',
      where: 'user_id = ? AND ended_at IS NULL',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// Insert scenario result with synced=0.
  Future<void> insertResult(Map<String, dynamic> result) async {
    await _db.insert(
      'scenario_results',
      result,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all results for a session.
  Future<List<Map<String, dynamic>>> getResultsForSession(
    String sessionId,
  ) async {
    return await _db.query(
      'scenario_results',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  /// Get all sessions that haven't been synced to backend.
  Future<List<Map<String, dynamic>>> getUnsyncedSessions() async {
    return await _db.query(
      'sessions',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'started_at ASC',
    );
  }

  /// Get all scenario results that haven't been synced to backend.
  Future<List<Map<String, dynamic>>> getUnsyncedResults() async {
    return await _db.query(
      'scenario_results',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
  }

  /// Mark session as synced and store remote session ID.
  Future<void> markSessionSynced(String id, String remoteSessionId) async {
    await _db.update(
      'sessions',
      {
        'synced': 1,
        'remote_session_id': remoteSessionId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark scenario result as synced.
  Future<void> markResultSynced(String id) async {
    await _db.update(
      'scenario_results',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get total session count for a user.
  Future<int> getSessionCount(String userId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM sessions WHERE user_id = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get scenario result count for a session.
  Future<int> getScenarioCountForSession(String sessionId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM scenario_results WHERE session_id = ?',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
