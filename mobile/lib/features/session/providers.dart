import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'domain/session_manager.dart';
import 'data/session_repository.dart';
import 'data/session_local_datasource.dart';
import 'data/session_remote_datasource.dart';
import '../profile/data/profile_local_datasource.dart';
import '../../core/database/database_provider.dart';
import '../../core/network/network_provider.dart';
import '../home/providers.dart';

/// Active session manager state notifier.
class ActiveSessionNotifier extends Notifier<SessionManager?> {
  @override
  SessionManager? build() => null;

  void setSession(SessionManager? manager) {
    state = manager;
  }

  void clearSession() {
    state = null;
  }
}

/// Active session manager (null when no session active).
final activeSessionProvider = NotifierProvider<ActiveSessionNotifier, SessionManager?>(
  ActiveSessionNotifier.new,
);

/// Session repository provider (async because it needs Database).
final sessionRepositoryProvider = FutureProvider<SessionRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final apiClient = ref.watch(apiClientProvider);

  return SessionRepository(
    localDataSource: SessionLocalDataSource(db),
    remoteDataSource: SessionRemoteDataSource(apiClient),
  );
});

/// Provider that returns the current user's resumable session, or null.
///
/// A session is resumable when:
/// - ended_at IS NULL (not yet formally ended)
/// - Time remaining > 0 (started less than 30 minutes ago)
/// - Scenarios remaining > 0 (fewer than 20 completed)
///
/// Invalidate this provider after starting/ending a session so the main
/// menu reflects the current state.
final resumableSessionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final userId = await ref.watch(userIdProvider.future);

  final local = SessionLocalDataSource(db);
  final session = await local.getActiveSession(userId);
  if (session == null) return null;

  // Check remaining time
  final startedAt = (session['started_at'] as int?) ?? 0;
  final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAt;
  final maxMs = 30 * 60 * 1000; // 30 minutes in ms
  if (elapsedMs >= maxMs) {
    // Session expired while app was away — end it silently
    await local.updateSession(session['id'] as String, {
      'ended_at': DateTime.now().millisecondsSinceEpoch,
    });
    return null;
  }

  // Check remaining scenarios
  final scenariosCompleted = (session['scenarios_completed'] as int?) ?? 0;
  if (scenariosCompleted >= 20) return null;

  return session;
});

/// Legacy provider — kept for compatibility with any code that still references it.
/// Prefer creating SessionManager directly inside SessionWrapper.
final sessionManagerProvider = FutureProvider.family<SessionManager, String>((ref, userId) async {
  final repository = await ref.watch(sessionRepositoryProvider.future);
  final db = await ref.watch(databaseProvider.future);
  final profileDataSource = ProfileLocalDataSource(db);

  final sessionId = await repository.startSession(userId);

  final manager = SessionManager(
    repository: repository,
    profileDataSource: profileDataSource,
    sessionId: sessionId,
    userId: userId,
    onStatusChange: (status) {},
  );

  await manager.start();

  ref.read(activeSessionProvider.notifier).setSession(manager);

  return manager;
});
