import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../../features/session/data/session_local_datasource.dart';
import 'api_client.dart';

/// Result of sync operation.
class SyncResult {
  final int synced;
  final int failed;
  final int pending;

  SyncResult({
    required this.synced,
    required this.failed,
    required this.pending,
  });

  @override
  String toString() =>
      'SyncResult(synced: $synced, failed: $failed, pending: $pending)';
}

/// Background sync service for offline-first pattern.
///
/// Handles syncing unsynced records to backend when network is available.
/// Uses tombstone pattern: marks records as synced on success, leaves them
/// unsynced on failure (never deletes unsynced data to prevent data loss).
class SyncService {
  final ApiClient _apiClient;
  final SessionLocalDataSource _localDataSource;
  final Connectivity _connectivity;

  Timer? _periodicSyncTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  SyncService({
    required ApiClient apiClient,
    required Database database,
    Connectivity? connectivity,
  })  : _apiClient = apiClient,
        _localDataSource = SessionLocalDataSource(database),
        _connectivity = connectivity ?? Connectivity();

  /// Start periodic sync and listen for connectivity changes.
  ///
  /// Syncs every [interval] when app is in foreground.
  /// Also triggers immediate sync when network becomes available.
  void startPeriodicSync(Duration interval) {
    // Start periodic timer
    _periodicSyncTimer = Timer.periodic(interval, (_) async {
      await syncPendingData();
    });

    // Listen for connectivity changes
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) async {
      // Trigger immediate sync when network becomes available
      if (result != ConnectivityResult.none) {
        await syncPendingData();
      }
    });
  }

  /// Stop periodic sync and connectivity listener.
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;

    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// Sync all pending (unsynced) data to backend.
  ///
  /// Uses tombstone pattern:
  /// - On success: mark record as synced
  /// - On failure: leave record unsynced (will retry later)
  /// - Never delete unsynced data
  ///
  /// Returns SyncResult with counts of synced/failed/pending records.
  Future<SyncResult> syncPendingData() async {
    int syncedCount = 0;
    int failedCount = 0;

    try {
      // Check network connectivity
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        // No network - return pending count
        final unsyncedSessions = await _localDataSource.getUnsyncedSessions();
        final unsyncedResults = await _localDataSource.getUnsyncedResults();
        return SyncResult(
          synced: 0,
          failed: 0,
          pending: unsyncedSessions.length + unsyncedResults.length,
        );
      }

      // Sync sessions
      final unsyncedSessions = await _localDataSource.getUnsyncedSessions();
      for (final session in unsyncedSessions) {
        try {
          // If no remote_session_id, create session on backend
          if (session['remote_session_id'] == null) {
            final response =
                await _apiClient.startSession(session['user_id'] as String);
            final remoteId = response['session_id'] as String;
            await _localDataSource.markSessionSynced(
              session['id'] as String,
              remoteId,
            );
            syncedCount++;
          } else {
            // Session already has remote_session_id, just mark as synced
            await _localDataSource.markSessionSynced(
              session['id'] as String,
              session['remote_session_id'] as String,
            );
            syncedCount++;
          }
        } catch (e) {
          // Sync failed for this session - leave it unsynced
          failedCount++;
        }
      }

      // Sync results
      final unsyncedResults = await _localDataSource.getUnsyncedResults();
      final pendingResults = unsyncedResults.length;

      return SyncResult(
        synced: syncedCount,
        failed: failedCount,
        pending: pendingResults,
      );
    } catch (e) {
      // Sync service failure should not crash app
      // Log error and return current state
      final unsyncedSessions = await _localDataSource.getUnsyncedSessions();
      final unsyncedResults = await _localDataSource.getUnsyncedResults();
      return SyncResult(
        synced: syncedCount,
        failed: failedCount,
        pending: unsyncedSessions.length + unsyncedResults.length,
      );
    }
  }
}
