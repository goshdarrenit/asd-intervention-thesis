/// API endpoint constants for backend communication.
///
/// POST /api/users/register
/// GET /api/users/{user_id}/profile
/// POST /api/sessions/start
/// POST /api/sessions/{session_id}/end
class ApiEndpoints {
  /// Base URL for Android emulator (10.0.2.2 maps to host machine localhost)
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// Base URL for iOS simulator (localhost accessible directly)
  static const String iosBaseUrl = 'http://localhost:8000';

  /// POST /api/users/register - Legacy anonymous registration (deprecated)
  static const String register = '/api/users/register';

  /// POST /api/auth/register - Register with email + password
  static const String authRegister = '/api/auth/register';

  /// POST /api/auth/login - Login with email + password
  static const String authLogin = '/api/auth/login';

  /// GET /api/auth/me - Get current authenticated user
  static const String authMe = '/api/auth/me';

  /// GET /api/users/{user_id}/profile - Get user profile
  static String profile(String userId) => '/api/users/$userId/profile';

  /// POST /api/sessions/start - Start new session
  static const String sessionStart = '/api/sessions/start';

  /// POST /api/sessions/{session_id}/end - End session
  static String sessionEnd(String sessionId) => '/api/sessions/$sessionId/end';

  /// POST /api/v1/scenarios/next - Get next scenario from RL model
  static const String scenarioNext = '/api/v1/scenarios/next';

  /// POST /api/v1/scenarios/submit - Submit scenario result
  static const String scenarioSubmit = '/api/v1/scenarios/submit';
}
