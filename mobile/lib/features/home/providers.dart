import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../profile/data/profile_local_datasource.dart';
import '../../core/database/database_provider.dart';
import '../../core/network/network_provider.dart';

/// Progress data loaded from local SQLite (offline-first).
///
/// Displays user progress on main menu including scenarios completed,
/// current level, and success rate
class UserProgress {
  final int scenariosCompleted;
  final int currentLevel;
  final double successRate; // 0.0 to 1.0
  final String displayName;

  const UserProgress({
    this.scenariosCompleted = 0,
    this.currentLevel = 1,
    this.successRate = 0.0,
    this.displayName = 'Explorer',
  });

  /// Derive level from scenarios completed (every 10 scenarios = 1 level).
  static int calculateLevel(int scenariosCompleted) {
    return (scenariosCompleted ~/ 10) + 1;
  }
}

/// Helper to get or create anonymous device-based user ID.
///
/// Stores user ID in SharedPreferences. If no user ID exists, generates
/// a new UUID and stores it (anonymous device-based identity per research).
Future<String> _getStoredUserId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'user_id';

  String? userId = prefs.getString(key);
  if (userId == null) {
    userId = const Uuid().v4();
    await prefs.setString(key, userId);
  }

  return userId;
}

/// Riverpod provider for user progress data.
///
/// Loads progress from local SQLite profile table. Returns default values
/// for new users. Handles errors gracefully (offline-first pattern).
final userProgressProvider = FutureProvider<UserProgress>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final profileDs = ProfileLocalDataSource(db);
  final apiClient = ref.watch(apiClientProvider);

  final userId = await _getStoredUserId();

  // For authenticated users, prefer backend as source of truth so progress
  // is consistent across devices (web/mobile) and cache it locally.
  try {
    final remote = await apiClient.getProfile(userId);
    final scenariosCompleted = (remote['scenarios_completed'] as int?) ?? 0;
    final successRate =
        (remote['overall_success_rate'] as num?)?.toDouble() ?? 0.0;

    await profileDs.upsertProfile({
      'id': userId,
      'user_id': userId,
      'display_name': 'Explorer',
      'scenarios_completed': scenariosCompleted,
      'success_rate': successRate,
      'current_level': UserProgress.calculateLevel(scenariosCompleted),
      'last_difficulty': (remote['current_difficulty'] as int?) ?? 1,
      'last_synced_at': DateTime.now().millisecondsSinceEpoch,
      'data_json': null,
    });

    return UserProgress(
      scenariosCompleted: scenariosCompleted,
      currentLevel: UserProgress.calculateLevel(scenariosCompleted),
      successRate: successRate,
      displayName: 'Explorer',
    );
  } catch (_) {
    // Offline or backend unavailable: fall back to local cache.
  }

  final profile = await profileDs.getProfile(userId);

  if (profile == null) {
    return const UserProgress(); // Default for new user
  }

  final scenariosCompleted = profile['scenarios_completed'] as int? ?? 0;
  return UserProgress(
    scenariosCompleted: scenariosCompleted,
    currentLevel: UserProgress.calculateLevel(scenariosCompleted),
    successRate: (profile['success_rate'] as num?)?.toDouble() ?? 0.0,
    displayName: profile['display_name'] as String? ?? 'Explorer',
  );
});

/// Provider for stored user ID (convenience).
final userIdProvider = FutureProvider<String>((ref) async {
  return await _getStoredUserId();
});
