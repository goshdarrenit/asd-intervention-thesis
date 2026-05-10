import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'api_endpoints.dart';

String _detectClientPlatform() {
  if (kIsWeb) {
    return 'browser';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

/// HTTP client for backend API communication.
///
/// Wraps Dio with configured timeouts, headers, and error handling.
/// Supports Bearer token auth — call [setAuthToken] after login/registration.
/// On 401, [onUnauthorized] callback is invoked so the caller can clear the
/// token and navigate to the login screen.
class ApiClient {
  late final Dio _dio;
  final String baseUrl;

  String? _authToken;

  /// Called when a 401 response is received (token expired/invalid).
  void Function()? onUnauthorized;

  ApiClient({required this.baseUrl}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(
      LogInterceptor(requestBody: true, responseBody: true),
    );

    // Auth interceptor: attach Bearer token + handle 401
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authToken != null) {
            options.headers['Authorization'] = 'Bearer $_authToken';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Set the JWT token used for all subsequent requests.
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Clear the stored auth token (on logout or expiry).
  void clearAuthToken() {
    _authToken = null;
  }

  // ── Auth endpoints ──────────────────────────────────────────────────────

  /// POST /api/auth/register — Register with email, password, age, severity.
  ///
  /// Response: {"access_token": "...", "token_type": "bearer", "user_id": "..."}
  Future<Map<String, dynamic>> authRegister({
    required String email,
    required String password,
    required int age,
    required int severityLevel,
  }) async {
    final response = await _dio.post(
      ApiEndpoints.authRegister,
      data: {
        'email': email,
        'password': password,
        'age': age,
        'severity_level': severityLevel,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// POST /api/auth/login — Login with email + password.
  ///
  /// Response: {"access_token": "...", "token_type": "bearer", "user_id": "..."}
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      ApiEndpoints.authLogin,
      data: {'email': email, 'password': password},
    );
    return response.data as Map<String, dynamic>;
  }

  /// GET /api/auth/me — Return current authenticated user info.
  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get(ApiEndpoints.authMe);
    return response.data as Map<String, dynamic>;
  }

  // ── Legacy / other endpoints ────────────────────────────────────────────

  /// POST /api/users/register - Create new user (legacy anonymous)
  Future<Map<String, dynamic>> registerUser(
    String age,
    String severity, {
    String? guardianEmail,
  }) async {
    final data = <String, dynamic>{
      'age': int.tryParse(age) ?? 8,
      'severity_level': int.tryParse(severity) ?? 1,
    };
    if (guardianEmail != null) {
      data['guardian_email'] = guardianEmail;
    }
    final response = await _dio.post(ApiEndpoints.register, data: data);
    return response.data as Map<String, dynamic>;
  }

  /// GET /api/users/{user_id}/profile - Get user profile
  Future<Map<String, dynamic>> getProfile(String userId) async {
    final response = await _dio.get(ApiEndpoints.profile(userId));
    return response.data as Map<String, dynamic>;
  }

  /// POST /api/sessions/start - Start new session
  Future<Map<String, dynamic>> startSession(String userId) async {
    final response = await _dio.post(
      ApiEndpoints.sessionStart,
      data: {
        'user_id': userId,
        'platform': _detectClientPlatform(),
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// POST /api/sessions/{session_id}/end - End session
  Future<Map<String, dynamic>> endSession(String sessionId) async {
    final response = await _dio.post(ApiEndpoints.sessionEnd(sessionId));
    return response.data as Map<String, dynamic>;
  }

  /// POST /api/v1/scenarios/next - Get next scenario from RL model
  Future<Map<String, dynamic>> getNextScenario(
      String userId, String sessionId) async {
    final response = await _dio.post(
      ApiEndpoints.scenarioNext,
      data: {'user_id': userId, 'session_id': sessionId},
    );
    return response.data as Map<String, dynamic>;
  }

  /// POST /api/v1/scenarios/submit - Submit scenario result
  Future<Map<String, dynamic>> submitScenarioResult({
    required String userId,
    required String sessionId,
    required String scenarioType,
    required int difficulty,
    required String complexity,
    required String reinforcementMode,
    required bool success,
    required int completionTimeMs,
    required Map<String, dynamic> telemetry,
  }) async {
    final response = await _dio.post(
      ApiEndpoints.scenarioSubmit,
      data: {
        'user_id': userId,
        'session_id': sessionId,
        'scenario_type': scenarioType,
        'difficulty': difficulty,
        'complexity': complexity,
        'reinforcement_mode': reinforcementMode,
        'success': success,
        'completion_time_ms': completionTimeMs,
        'telemetry': telemetry,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Get Dio instance for custom requests (advanced use cases).
  Dio get dio => _dio;
}
