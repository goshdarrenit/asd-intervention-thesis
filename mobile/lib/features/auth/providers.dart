import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/network_provider.dart';

const _tokenKey = 'auth_token';
const _userIdKey = 'auth_user_id';

/// Provides a FlutterSecureStorage instance.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

/// Reads the stored JWT token from secure storage (null if not found).
final authTokenProvider = FutureProvider<String?>((ref) async {
  final storage = ref.read(secureStorageProvider);
  return storage.read(key: _tokenKey);
});

// ── Login notifier ─────────────────────────────────────────────────────────

/// State for the login flow.
class LoginState {
  final bool isLoading;
  final String? errorMessage;

  const LoginState({this.isLoading = false, this.errorMessage});

  LoginState copyWith({bool? isLoading, String? errorMessage}) => LoginState(
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
      );
}

class LoginNotifier extends AsyncNotifier<LoginState> {
  @override
  Future<LoginState> build() async => const LoginState();

  /// Authenticate with email + password, persist token, update ApiClient.
  ///
  /// Returns true on success, false on failure (errorMessage is set).
  Future<bool> login(String email, String password) async {
    state = const AsyncData(LoginState(isLoading: true));

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.login(email: email, password: password);

      final token = response['access_token'] as String;
      final userId = response['user_id'] as String;

      // Persist token securely
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: _tokenKey, value: token);
      await storage.write(key: _userIdKey, value: userId);

      // Persist user_id in SharedPreferences for offline access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      await prefs.setString('remote_user_id', userId);
      await prefs.setBool('is_registered', true);

      // Attach token to ApiClient
      apiClient.setAuthToken(token);

      state = const AsyncData(LoginState());
      return true;
    } on Exception catch (e) {
      final message = _parseError(e);
      state = AsyncData(LoginState(errorMessage: message));
      return false;
    }
  }

  /// Sign out: clear secure storage + ApiClient token.
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteAll();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_registered');
    await prefs.remove('user_id');

    ref.read(apiClientProvider).clearAuthToken();
    state = const AsyncData(LoginState());
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('401')) return 'Invalid email or password.';
    if (msg.contains('SocketException') || msg.contains('DioException')) {
      return 'Cannot reach server. Check your connection.';
    }
    return 'Login failed. Please try again.';
  }
}

final loginProvider =
    AsyncNotifierProvider<LoginNotifier, LoginState>(LoginNotifier.new);
