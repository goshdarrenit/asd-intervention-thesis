import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:asd_intervention/core/database/app_database.dart';
import 'package:asd_intervention/core/network/sync_service.dart';
import 'package:asd_intervention/core/network/api_client.dart';
import 'package:asd_intervention/features/session/data/session_local_datasource.dart';

/// Mock Connectivity for testing network status.
class MockConnectivity implements Connectivity {
  ConnectivityResult _currentResult = ConnectivityResult.wifi;

  void setConnectivity(ConnectivityResult result) {
    _currentResult = result;
  }

  @override
  Future<ConnectivityResult> checkConnectivity() async {
    return _currentResult;
  }

  @override
  Stream<ConnectivityResult> get onConnectivityChanged =>
      Stream.value(_currentResult);
}

void main() {
  // Initialize FFI for desktop/test environment
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;
  late SessionLocalDataSource localDataSource;
  late ApiClient apiClient;
  late MockConnectivity mockConnectivity;
  late SyncService syncService;

  setUp(() async {
    appDatabase = AppDatabase();
    db = await appDatabase.database;
    localDataSource = SessionLocalDataSource(db);

    // Use real API client (it will fail to connect in tests, which is fine)
    apiClient = ApiClient(baseUrl: 'http://localhost:9999');
    mockConnectivity = MockConnectivity();

    syncService = SyncService(
      apiClient: apiClient,
      database: db,
      connectivity: mockConnectivity,
    );
  });

  tearDown(() async {
    syncService.stopPeriodicSync();
    await appDatabase.close();
    await appDatabase.deleteDatabase();
  });

  group('SyncService', () {
    test('syncPendingData with no unsynced records returns zero counts',
        () async {
      final result = await syncService.syncPendingData();

      expect(result.synced, equals(0));
      expect(result.failed, equals(0));
      expect(result.pending, equals(0));
    });

    test('syncPendingData with unsynced session attempts sync', () async {
      // Insert unsynced session
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await localDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'synced': 0,
      });

      // Verify unsynced before sync
      var unsynced = await localDataSource.getUnsyncedSessions();
      expect(unsynced.length, equals(1));

      // Sync will fail (no backend running), but should not crash
      final result = await syncService.syncPendingData();

      // Record should still be unsynced due to failure
      expect(result.failed, equals(1));

      unsynced = await localDataSource.getUnsyncedSessions();
      expect(unsynced.length, equals(1));
      expect(unsynced.first['id'], equals(sessionId));
      expect(unsynced.first['synced'], equals(0));
    });

    test(
        'syncPendingData with failed API call leaves record unsynced (does not delete)',
        () async {
      // Insert unsynced session
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await localDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'synced': 0,
      });

      // Sync with failure (no backend)
      final result = await syncService.syncPendingData();

      // Verify record still exists and is unsynced
      expect(result.synced, equals(0));
      expect(result.failed, equals(1));

      final unsynced = await localDataSource.getUnsyncedSessions();
      expect(unsynced.length, equals(1));
      expect(unsynced.first['id'], equals(sessionId));
      expect(unsynced.first['synced'], equals(0));

      // Verify record was NOT deleted (tombstone pattern)
      final sessions = await db.query('sessions');
      expect(sessions.length, equals(1));
    });

    test('sync does not throw when API is unreachable', () async {
      // Insert unsynced session
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await localDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'synced': 0,
      });

      // Simulate no network
      mockConnectivity.setConnectivity(ConnectivityResult.none);

      // Should not throw
      expect(() async => await syncService.syncPendingData(), returnsNormally);

      final result = await syncService.syncPendingData();

      // Should report pending records
      expect(result.pending, equals(1));
      expect(result.synced, equals(0));
      expect(result.failed, equals(0));
    });

    test('startPeriodicSync and stopPeriodicSync work without errors',
        () async {
      // Should not throw
      expect(
        () => syncService.startPeriodicSync(const Duration(seconds: 30)),
        returnsNormally,
      );

      // Give it a moment to start
      await Future.delayed(const Duration(milliseconds: 100));

      // Should not throw
      expect(() => syncService.stopPeriodicSync(), returnsNormally);
    });

    test('syncPendingData returns pending count when network unavailable',
        () async {
      // Insert unsynced session
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await localDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'synced': 0,
      });

      // Insert unsynced result
      await localDataSource.insertResult({
        'id': const Uuid().v4(),
        'session_id': sessionId,
        'scenario_type': 'greeting',
        'difficulty': 1,
        'outcome': 'success',
        'reward': 1.0,
        'created_at': now,
        'synced': 0,
      });

      // Simulate no network
      mockConnectivity.setConnectivity(ConnectivityResult.none);

      final result = await syncService.syncPendingData();

      // Should report 2 pending records (1 session + 1 result)
      expect(result.pending, equals(2));
      expect(result.synced, equals(0));
      expect(result.failed, equals(0));
    });
  });
}
