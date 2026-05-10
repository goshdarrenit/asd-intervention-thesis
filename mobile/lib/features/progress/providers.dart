import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_provider.dart';
import '../../core/theme/app_colors.dart';
import '../home/providers.dart';

/// Per-scenario statistics for the dashboard breakdown.
class ScenarioStat {
  final String type;
  final String displayName;
  final IconData icon;
  final Color color;
  final int completed;
  final double successRate;

  const ScenarioStat({
    required this.type,
    required this.displayName,
    required this.icon,
    required this.color,
    required this.completed,
    required this.successRate,
  });
}

/// Summary of a single session for the recent history list.
class SessionSummary {
  final String sessionId;
  final String dateLabel;
  final int scenariosPlayed;
  final int durationMinutes;
  final double successRate;

  const SessionSummary({
    required this.sessionId,
    required this.dateLabel,
    required this.scenariosPlayed,
    required this.durationMinutes,
    required this.successRate,
  });
}

/// All data needed to render the progress dashboard.
class DashboardData {
  final int totalScenarios;
  final int currentLevel;
  final double overallSuccessRate;
  final int totalSessionsPlayed;
  final List<ScenarioStat> scenarioStats;
  final List<SessionSummary> recentSessions;
  final double avgFrustration;
  final double avgEngagement;
  final double avgConfidence;

  const DashboardData({
    required this.totalScenarios,
    required this.currentLevel,
    required this.overallSuccessRate,
    required this.totalSessionsPlayed,
    required this.scenarioStats,
    required this.recentSessions,
    required this.avgFrustration,
    required this.avgEngagement,
    required this.avgConfidence,
  });

  /// Empty dashboard for new users or error fallback.
  factory DashboardData.empty() => DashboardData(
        totalScenarios: 0,
        currentLevel: 1,
        overallSuccessRate: 0.0,
        totalSessionsPlayed: 0,
        scenarioStats: _defaultScenarioStats(),
        recentSessions: const [],
        avgFrustration: 0.0,
        avgEngagement: 0.0,
        avgConfidence: 0.0,
      );
}

/// Default scenario stats with zero completion.
List<ScenarioStat> _defaultScenarioStats() {
  return const [
    ScenarioStat(
      type: 'sharing',
      displayName: 'Sharing',
      icon: Icons.card_giftcard_rounded,
      color: AppColors.primary,
      completed: 0,
      successRate: 0.0,
    ),
    ScenarioStat(
      type: 'patience',
      displayName: 'Patience',
      icon: Icons.hourglass_bottom_rounded,
      color: AppColors.secondary,
      completed: 0,
      successRate: 0.0,
    ),
    ScenarioStat(
      type: 'emotion_recognition',
      displayName: 'Emotions',
      icon: Icons.emoji_emotions_rounded,
      color: AppColors.warning,
      completed: 0,
      successRate: 0.0,
    ),
    ScenarioStat(
      type: 'turn_taking',
      displayName: 'Turn Taking',
      icon: Icons.swap_horiz_rounded,
      color: AppColors.info,
      completed: 0,
      successRate: 0.0,
    ),
    ScenarioStat(
      type: 'conflict_resolution',
      displayName: 'Conflict Resolution',
      icon: Icons.handshake_rounded,
      color: AppColors.success,
      completed: 0,
      successRate: 0.0,
    ),
  ];
}

/// Scenario type metadata for icon / colour mapping.
const _scenarioMeta = {
  'sharing': (Icons.card_giftcard_rounded, AppColors.primary, 'Sharing'),
  'patience': (Icons.hourglass_bottom_rounded, AppColors.secondary, 'Patience'),
  'emotion_recognition': (Icons.emoji_emotions_rounded, AppColors.warning, 'Emotions'),
  'turn_taking': (Icons.swap_horiz_rounded, AppColors.info, 'Turn Taking'),
  'conflict_resolution': (Icons.handshake_rounded, AppColors.success, 'Conflict Resolution'),
};

/// Provider that loads all dashboard data from local SQLite.
final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final userId = await ref.watch(userIdProvider.future);

  // ── Overall stats from profile ──────────────────────────────────
  final profileRows = await db.query(
    'user_profile',
    where: 'user_id = ?',
    whereArgs: [userId],
    limit: 1,
  );

  int totalScenarios = 0;
  double overallSuccessRate = 0.0;
  if (profileRows.isNotEmpty) {
    totalScenarios = (profileRows.first['scenarios_completed'] as int?) ?? 0;
    overallSuccessRate =
        (profileRows.first['success_rate'] as num?)?.toDouble() ?? 0.0;
  }

  final currentLevel = UserProgress.calculateLevel(totalScenarios);

  // ── Session count ───────────────────────────────────────────────
  final sessionCountResult = await db.rawQuery(
    'SELECT COUNT(*) as cnt FROM sessions WHERE user_id = ?',
    [userId],
  );
  final totalSessions = (sessionCountResult.first['cnt'] as int?) ?? 0;

  // ── Per-scenario breakdown ──────────────────────────────────────
  final scenarioRows = await db.rawQuery('''
    SELECT
      scenario_type,
      COUNT(*) as cnt,
      SUM(CASE WHEN outcome = 'success' THEN 1 ELSE 0 END) as successes
    FROM scenario_results
    WHERE session_id IN (SELECT id FROM sessions WHERE user_id = ?)
    GROUP BY scenario_type
  ''', [userId]);

  final scenarioMap = <String, (int, int)>{};
  for (final row in scenarioRows) {
    final type = row['scenario_type'] as String;
    final count = (row['cnt'] as int?) ?? 0;
    final successes = (row['successes'] as int?) ?? 0;
    scenarioMap[type] = (count, successes);
  }

  final scenarioStats = _scenarioMeta.entries.map((entry) {
    final type = entry.key;
    final (icon, color, displayName) = entry.value;
    final (completed, successes) = scenarioMap[type] ?? (0, 0);
    final rate = completed > 0 ? successes / completed : 0.0;

    return ScenarioStat(
      type: type,
      displayName: displayName,
      icon: icon,
      color: color,
      completed: completed,
      successRate: rate,
    );
  }).toList();

  // ── Recent sessions (last 5) ────────────────────────────────────
  final sessionRows = await db.query(
    'sessions',
    where: 'user_id = ?',
    whereArgs: [userId],
    orderBy: 'started_at DESC',
    limit: 5,
  );

  final recentSessions = <SessionSummary>[];
  for (final row in sessionRows) {
    final sessionId = row['id'] as String;
    final startedAt = (row['started_at'] as int?) ?? 0;
    final endedAt = row['ended_at'] as int?;
    final scenariosCompleted = (row['scenarios_completed'] as int?) ?? 0;

    // Calculate duration
    final startTime = DateTime.fromMillisecondsSinceEpoch(startedAt);
    final endTime = endedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(endedAt)
        : DateTime.now();
    final durationMinutes = endTime.difference(startTime).inMinutes;

    // Format date label
    final now = DateTime.now();
    final diff = now.difference(startTime);
    String dateLabel;
    if (diff.inDays == 0) {
      dateLabel = 'Today';
    } else if (diff.inDays == 1) {
      dateLabel = 'Yesterday';
    } else if (diff.inDays < 7) {
      dateLabel = '${diff.inDays} days ago';
    } else {
      dateLabel =
          '${startTime.day}/${startTime.month}/${startTime.year}';
    }

    // Per-session success rate
    final resultRows = await db.rawQuery('''
      SELECT COUNT(*) as cnt,
             SUM(CASE WHEN outcome = 'success' THEN 1 ELSE 0 END) as successes
      FROM scenario_results
      WHERE session_id = ?
    ''', [sessionId]);

    double sessionRate = 0.0;
    if (resultRows.isNotEmpty) {
      final cnt = (resultRows.first['cnt'] as int?) ?? 0;
      final succ = (resultRows.first['successes'] as int?) ?? 0;
      sessionRate = cnt > 0 ? succ / cnt : 0.0;
    }

    recentSessions.add(SessionSummary(
      sessionId: sessionId,
      dateLabel: dateLabel,
      scenariosPlayed: scenariosCompleted,
      durationMinutes: durationMinutes.clamp(0, 60),
      successRate: sessionRate,
    ));
  }

  // ── Emotional averages (from profile data_json if available) ────
  // These come from backend EMA updates synced to local profile.
  double avgFrustration = 0.0;
  double avgEngagement = 0.5;
  double avgConfidence = 0.5;

  if (profileRows.isNotEmpty) {
    final dataJson = profileRows.first['data_json'] as String?;
    if (dataJson != null) {
      try {
        // Simple parsing — data_json stores emotional history
        // Format: {"frustration": 0.3, "engagement": 0.7, "confidence": 0.6}
        // Decode and extract values
        // Using basic string parsing to avoid importing dart:convert in provider
        if (dataJson.contains('frustration')) {
          avgFrustration = _extractJsonDouble(dataJson, 'frustration') ?? 0.0;
        }
        if (dataJson.contains('engagement')) {
          avgEngagement = _extractJsonDouble(dataJson, 'engagement') ?? 0.5;
        }
        if (dataJson.contains('confidence')) {
          avgConfidence = _extractJsonDouble(dataJson, 'confidence') ?? 0.5;
        }
      } catch (_) {
        // Use defaults on parse error
      }
    }
  }

  return DashboardData(
    totalScenarios: totalScenarios,
    currentLevel: currentLevel,
    overallSuccessRate: overallSuccessRate,
    totalSessionsPlayed: totalSessions,
    scenarioStats: scenarioStats,
    recentSessions: recentSessions,
    avgFrustration: avgFrustration,
    avgEngagement: avgEngagement,
    avgConfidence: avgConfidence,
  );
});

/// Extract a double value from a simple JSON string by key.
double? _extractJsonDouble(String json, String key) {
  final pattern = RegExp('"$key"\\s*:\\s*([\\d.]+)');
  final match = pattern.firstMatch(json);
  if (match != null) {
    return double.tryParse(match.group(1)!);
  }
  return null;
}
