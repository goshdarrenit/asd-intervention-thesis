import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_provider.dart';
import 'api_client.dart';
import 'api_endpoints.dart';
import 'sync_service.dart';

String _resolveBaseUrl() {
  const configuredBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (configuredBaseUrl.isNotEmpty) {
    return configuredBaseUrl;
  }

  // Web and desktop builds can reach the local backend directly.
  if (kIsWeb) {
    return 'http://localhost:8000';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      // Android emulator maps host machine localhost to 10.0.2.2.
      return ApiEndpoints.baseUrl;
    case TargetPlatform.iOS:
      return ApiEndpoints.iosBaseUrl;
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      return 'http://localhost:8000';
  }
}

final apiBaseUrlProvider = Provider<String>((ref) => _resolveBaseUrl());

/// Riverpod provider for ApiClient singleton.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: ref.watch(apiBaseUrlProvider));
});

/// Riverpod provider for SyncService.
/// Requires database to be initialized.
final syncServiceProvider = Provider<SyncService>((ref) {
  // We need to handle async database provider properly
  // For now, this will be initialized when database is ready
  throw UnimplementedError(
    'SyncService provider requires async database initialization. '
    'Use syncServiceFutureProvider instead.',
  );
});

/// Future provider for SyncService (async initialization).
final syncServiceFutureProvider = FutureProvider<SyncService>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final db = await ref.watch(databaseProvider.future);

  return SyncService(
    apiClient: apiClient,
    database: db,
  );
});
