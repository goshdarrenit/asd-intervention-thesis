import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:asd_intervention/core/database/app_database.dart';
import 'package:asd_intervention/features/session/data/session_local_datasource.dart';

void main() {
  // Initialize FFI for desktop/test environment
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late Database db;
  late SessionLocalDataSource sessionDataSource;

  setUp(() async {
    appDatabase = AppDatabase();
    db = await appDatabase.database;
    sessionDataSource = SessionLocalDataSource(db);
  });

  tearDown(() async {
    await appDatabase.close();
    await appDatabase.deleteDatabase();
  });

  group('AppDatabase', () {
    test('creates all 3 tables (sessions, scenario_results, user_profile)',
        () async {
      // Query sqlite_master to verify tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );

      final tableNames = tables.map((t) => t['name'] as String).toList();

      expect(tableNames, contains('sessions'));
      expect(tableNames, contains('scenario_results'));
      expect(tableNames, contains('user_profile'));
      expect(tableNames.length, greaterThanOrEqualTo(3));
    });

    test('creates indexes on synced columns', () async {
      // Query sqlite_master to verify indexes exist
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
      );

      final indexNames = indexes.map((i) => i['name'] as String).toList();

      expect(indexNames, contains('idx_sessions_synced'));
      expect(indexNames, contains('idx_scenario_results_synced'));
      expect(indexNames, contains('idx_scenario_results_session_id'));
    });
  });

  group('SessionLocalDataSource', () {
    test('insert and read session', () async {
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      final session = {
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'scenarios_completed': 0,
        'max_scenarios': 20,
        'max_duration_minutes': 30,
        'synced': 0,
      };

      await sessionDataSource.insertSession(session);

      final activeSession = await sessionDataSource.getActiveSession(userId);

      expect(activeSession, isNotNull);
      expect(activeSession!['id'], equals(sessionId));
      expect(activeSession['user_id'], equals(userId));
      expect(activeSession['synced'], equals(0));
    });

    test('insert and read scenario result', () async {
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final resultId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insert session first
      await sessionDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'synced': 0,
      });

      // Insert result
      final result = {
        'id': resultId,
        'session_id': sessionId,
        'scenario_type': 'greeting',
        'difficulty': 1,
        'outcome': 'success',
        'reward': 1.0,
        'completion_time_ms': 5000,
        'created_at': now,
        'synced': 0,
      };

      await sessionDataSource.insertResult(result);

      final results =
          await sessionDataSource.getResultsForSession(sessionId);

      expect(results.length, equals(1));
      expect(results.first['id'], equals(resultId));
      expect(results.first['scenario_type'], equals('greeting'));
      expect(results.first['synced'], equals(0));
    });

    test('getUnsyncedSessions returns only unsynced records', () async {
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insert synced session
      await sessionDataSource.insertSession({
        'id': const Uuid().v4(),
        'user_id': userId,
        'started_at': now,
        'synced': 1,
        'remote_session_id': 'remote-123',
      });

      // Insert unsynced session
      final unsyncedId = const Uuid().v4();
      await sessionDataSource.insertSession({
        'id': unsyncedId,
        'user_id': userId,
        'started_at': now + 1000,
        'synced': 0,
      });

      final unsynced = await sessionDataSource.getUnsyncedSessions();

      expect(unsynced.length, equals(1));
      expect(unsynced.first['id'], equals(unsyncedId));
      expect(unsynced.first['synced'], equals(0));
    });

    test('markSessionSynced updates synced flag', () async {
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await sessionDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'synced': 0,
      });

      final remoteId = 'remote-${const Uuid().v4()}';
      await sessionDataSource.markSessionSynced(sessionId, remoteId);

      final unsynced = await sessionDataSource.getUnsyncedSessions();
      expect(unsynced.length, equals(0));

      // Verify synced flag and remote_session_id
      final results = await db.query(
        'sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      expect(results.first['synced'], equals(1));
      expect(results.first['remote_session_id'], equals(remoteId));
    });

    test('getScenarioCountForSession returns correct count', () async {
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await sessionDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'synced': 0,
      });

      // Insert 3 results
      for (int i = 0; i < 3; i++) {
        await sessionDataSource.insertResult({
          'id': const Uuid().v4(),
          'session_id': sessionId,
          'scenario_type': 'greeting',
          'difficulty': 1,
          'outcome': 'success',
          'reward': 1.0,
          'created_at': now + i,
          'synced': 0,
        });
      }

      final count =
          await sessionDataSource.getScenarioCountForSession(sessionId);

      expect(count, equals(3));
    });

    test('getSessionCount returns total sessions for user', () async {
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insert 2 sessions
      for (int i = 0; i < 2; i++) {
        await sessionDataSource.insertSession({
          'id': const Uuid().v4(),
          'user_id': userId,
          'started_at': now + i,
          'synced': 0,
        });
      }

      final count = await sessionDataSource.getSessionCount(userId);

      expect(count, equals(2));
    });

    test('updateSession modifies existing session', () async {
      final sessionId = const Uuid().v4();
      final userId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await sessionDataSource.insertSession({
        'id': sessionId,
        'user_id': userId,
        'started_at': now,
        'scenarios_completed': 0,
        'synced': 0,
      });

      await sessionDataSource.updateSession(sessionId, {
        'scenarios_completed': 5,
        'ended_at': now + 10000,
      });

      final results = await db.query(
        'sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      expect(results.first['scenarios_completed'], equals(5));
      expect(results.first['ended_at'], equals(now + 10000));
    });
  });
}
