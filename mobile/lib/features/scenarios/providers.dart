import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/network_provider.dart';
import '../../core/database/database_provider.dart';
import '../profile/data/profile_local_datasource.dart';
import 'data/scenario_api_service.dart';

/// Future provider for ScenarioApiService (async initialization).
///
/// Provides scenario selection and result submission with offline fallback.
final scenarioApiServiceProvider = FutureProvider<ScenarioApiService>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final db = await ref.watch(databaseProvider.future);
  final profileDataSource = ProfileLocalDataSource(db);

  return ScenarioApiService(apiClient, profileDataSource);
});
