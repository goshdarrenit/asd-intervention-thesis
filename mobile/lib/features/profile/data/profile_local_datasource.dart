import 'package:sqflite/sqflite.dart';

/// Local data source for user profile operations.
///
/// Handles profile storage and progress tracking in local SQLite.
/// Profile data syncs to backend periodically via sync service.
class ProfileLocalDataSource {
  final Database _db;

  ProfileLocalDataSource(this._db);

  /// Insert or update user profile.
  /// Uses REPLACE conflict algorithm to handle both insert and update cases.
  Future<void> upsertProfile(Map<String, dynamic> profile) async {
    await _db.insert(
      'user_profile',
      profile,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get profile by user_id.
  /// Returns null if profile doesn't exist.
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final results = await _db.query(
      'user_profile',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// Update specific progress fields for a user.
  /// Only updates non-null parameters.
  Future<void> updateProgress(
    String userId, {
    int? scenariosCompleted,
    double? successRate,
    int? currentLevel,
  }) async {
    final updates = <String, dynamic>{};

    if (scenariosCompleted != null) {
      updates['scenarios_completed'] = scenariosCompleted;
    }
    if (successRate != null) {
      updates['success_rate'] = successRate;
    }
    if (currentLevel != null) {
      updates['current_level'] = currentLevel;
    }

    if (updates.isNotEmpty) {
      await _db.update(
        'user_profile',
        updates,
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    }
  }

  /// Cache last-known difficulty for offline fallback.
  Future<void> cacheLastDifficulty(String userId, int difficulty) async {
    await _db.update(
      'user_profile',
      {'last_difficulty': difficulty},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Get cached difficulty for offline fallback (returns 1 if not cached).
  Future<int> getLastDifficulty(String userId) async {
    final results = await _db.query(
      'user_profile',
      columns: ['last_difficulty'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (results.isNotEmpty && results.first['last_difficulty'] != null) {
      return results.first['last_difficulty'] as int;
    }
    return 1; // Default difficulty
  }
}
