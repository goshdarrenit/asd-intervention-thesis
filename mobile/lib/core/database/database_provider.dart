import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'app_database.dart';

/// Riverpod provider for AppDatabase singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// Riverpod provider for Database instance (async).
/// Use this provider when you need the actual Database object.
final databaseProvider = FutureProvider<Database>((ref) async {
  final appDb = ref.watch(appDatabaseProvider);
  return appDb.database;
});
