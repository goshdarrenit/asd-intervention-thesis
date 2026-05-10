import '../../../core/network/api_client.dart';

/// Remote data source for session API operations.
///
/// Wraps ApiClient methods with domain-specific naming.
/// Throws DioException on network or server errors.
class SessionRemoteDataSource {
  final ApiClient _apiClient;

  SessionRemoteDataSource(this._apiClient);

  /// Start session on backend.
  /// Returns remote session data including session_id.
  Future<Map<String, dynamic>> startSession(String userId) async {
    return await _apiClient.startSession(userId);
  }

  /// End session on backend.
  /// Returns updated session data including ended_at.
  Future<Map<String, dynamic>> endSession(String sessionId) async {
    return await _apiClient.endSession(sessionId);
  }
}
