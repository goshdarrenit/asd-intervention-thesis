import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../profile/data/profile_local_datasource.dart';
import '../../core/database/database_provider.dart';
import '../../core/network/network_provider.dart';
import '../auth/providers.dart';

/// Registration state for tracking the registration flow.
class RegistrationState {
  final bool isRegistered;
  final bool isLoading;
  final String? userId;
  final String? errorMessage;

  const RegistrationState({
    this.isRegistered = false,
    this.isLoading = true,
    this.userId,
    this.errorMessage,
  });

  RegistrationState copyWith({
    bool? isRegistered,
    bool? isLoading,
    String? userId,
    String? errorMessage,
  }) {
    return RegistrationState(
      isRegistered: isRegistered ?? this.isRegistered,
      isLoading: isLoading ?? this.isLoading,
      userId: userId ?? this.userId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Notifier that manages registration state and API calls.
///
/// Handles:
/// - Checking whether user has already registered (SharedPreferences)
/// - Submitting registration to backend /api/auth/register
/// - Persisting JWT in flutter_secure_storage
/// - Persisting profile locally for offline-first use
class RegistrationNotifier extends AsyncNotifier<RegistrationState> {
  @override
  Future<RegistrationState> build() async {
    // Check if user is already registered
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final isRegistered = prefs.getBool('is_registered') ?? false;

    return RegistrationState(
      isRegistered: isRegistered && userId != null,
      isLoading: false,
      userId: userId,
    );
  }

  /// Register a new guardian account with email + password.
  ///
  /// 1. Call POST /api/auth/register -> receive JWT + user_id
  /// 2. Store JWT in flutter_secure_storage
  /// 3. Save profile to local SQLite (offline-first)
  /// 4. Store registration state in SharedPreferences
  Future<void> register({
    required String email,
    required String password,
    required int age,
    required int severityLevel,
  }) async {
    state = const AsyncData(RegistrationState(isLoading: true));

    try {
      final apiClient = ref.read(apiClientProvider);
      final storage = ref.read(secureStorageProvider);

      // Call new auth registration endpoint
      final response = await apiClient.authRegister(
        email: email,
        password: password,
        age: age,
        severityLevel: severityLevel,
      );

      final token = response['access_token'] as String;
      final userId = response['user_id'] as String;

      // Store JWT securely
      await storage.write(key: 'auth_token', value: token);
      await storage.write(key: 'auth_user_id', value: userId);

      // Set token on ApiClient for subsequent requests
      apiClient.setAuthToken(token);

      // Save locally (offline-first)
      final db = await ref.read(databaseProvider.future);
      final profileDs = ProfileLocalDataSource(db);
      await profileDs.upsertProfile({
        'id': userId,
        'user_id': userId,
        'display_name': 'Explorer',
        'scenarios_completed': 0,
        'success_rate': 0.0,
        'current_level': 1,
        'last_difficulty': 1,
      });

      // Store registration state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      await prefs.setString('remote_user_id', userId);
      await prefs.setBool('is_registered', true);
      await prefs.setInt('user_age', age);
      await prefs.setInt('user_severity', severityLevel);

      state = AsyncData(RegistrationState(
        isRegistered: true,
        isLoading: false,
        userId: userId,
      ));
    } catch (e) {
      state = AsyncData(RegistrationState(
        isRegistered: false,
        isLoading: false,
        errorMessage: e.toString(),
      ));
      rethrow;
    }
  }
}

/// Provider for registration state.
final registrationProvider =
    AsyncNotifierProvider<RegistrationNotifier, RegistrationState>(
  RegistrationNotifier.new,
);

/// Convenience provider that checks if user is registered (for routing).
final isRegisteredProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id');
  final isRegistered = prefs.getBool('is_registered') ?? false;
  return isRegistered && userId != null;
});
