import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';

/// Manages sessions, scenario_results, and user_profile tables with sync tracking.
/// Uses singleton pattern to ensure single database instance across app lifecycle.
class AppDatabase {
  static Database? _database;
  static const int _version = 2;
  static const String _databaseName = 'asd_intervention.db';

  /// Get database instance (lazy initialization).
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database with path and create tables.
  Future<Database> _initDatabase() async {
    // sqflite uses platform channels on mobile, but Flutter web needs an
    // in-browser database factory implementation.
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }

    final path = await _resolveDatabasePath();

    return await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create all tables on first database creation.
  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // Sessions table: tracks user gameplay sessions
    batch.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        scenarios_completed INTEGER DEFAULT 0,
        max_scenarios INTEGER DEFAULT 20,
        max_duration_minutes INTEGER DEFAULT 30,
        synced INTEGER DEFAULT 0,
        remote_session_id TEXT
      )
    ''');

    // Scenario results table: stores individual scenario outcomes
    batch.execute('''
      CREATE TABLE scenario_results (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        scenario_type TEXT NOT NULL,
        difficulty INTEGER NOT NULL,
        outcome TEXT NOT NULL,
        reward REAL NOT NULL,
        completion_time_ms INTEGER,
        created_at INTEGER NOT NULL,
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    // User profile table: stores user progress and preferences
    batch.execute('''
      CREATE TABLE user_profile (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL UNIQUE,
        display_name TEXT,
        scenarios_completed INTEGER DEFAULT 0,
        success_rate REAL DEFAULT 0.0,
        current_level INTEGER DEFAULT 1,
        last_difficulty INTEGER DEFAULT 1,
        last_synced_at INTEGER,
        data_json TEXT
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_scenario_results_session_id
      ON scenario_results(session_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_sessions_synced
      ON sessions(synced)
    ''');

    batch.execute('''
      CREATE INDEX idx_scenario_results_synced
      ON scenario_results(synced)
    ''');

    await batch.commit(noResult: true);
  }

  /// Handle database upgrades in future versions.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add last_difficulty column to user_profile table
      await db.execute('''
        ALTER TABLE user_profile ADD COLUMN last_difficulty INTEGER DEFAULT 1
      ''');
    }
  }

  /// Close database connection.
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Delete database (for testing).
  Future<void> deleteDatabase() async {
    final path = await _resolveDatabasePath();
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }

  Future<String> _resolveDatabasePath() async {
    if (kIsWeb) {
      return _databaseName;
    }

    final dbPath = await getDatabasesPath();
    return join(dbPath, _databaseName);
  }
}
