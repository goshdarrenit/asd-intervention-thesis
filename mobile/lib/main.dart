import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/providers.dart';
import 'features/home/presentation/main_menu_screen.dart';
import 'core/network/network_provider.dart';
import 'features/scenarios/game/game_config.dart';
import 'features/scenarios/presentation/game_screen.dart';

// Set to a scenario name to jump straight to that game (skips login).
// Options: 'sharing', 'turn_taking', 'emotion_recognition', 'patience', 'conflict_resolution'
// Set to null to restore normal login flow.
const String? _kDevScenario = null;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: ASDInterventionApp()));
}

class ASDInterventionApp extends ConsumerWidget {
  const ASDInterventionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return MaterialApp(
      title: 'Social Skills Adventure',
      theme: AppTheme.create(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (!kDebugMode || child == null) {
          return child ?? const SizedBox.shrink();
        }

        return Stack(
          children: [
            child,
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'API: $baseUrl',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      home: kDebugMode && _kDevScenario != null
          ? _DevScenarioLauncher(scenario: _kDevScenario!)
          : const _AppGate(),
    );
  }
}

/// Gate widget that routes to the correct screen on app launch.
///
/// Logic:
/// 1. Check flutter_secure_storage for 'auth_token'
/// 2. If token exists -> try GET /api/auth/me
///    - Success -> MainMenuScreen (set token on ApiClient)
///    - 401 / error -> LoginScreen
/// 3. If no token -> LoginScreen (with link to RegistrationScreen)
class _AppGate extends ConsumerWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenAsync = ref.watch(authTokenProvider);

    return tokenAsync.when(
      data: (token) {
        if (token == null) {
          // No token stored — show login (links to registration)
          return const LoginScreen();
        }
        // Token exists — validate it and route accordingly
        return _TokenValidator(token: token);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const LoginScreen(),
    );
  }
}

/// Validates a stored token by calling /api/auth/me.
/// Shows MainMenuScreen on success, LoginScreen on failure.
class _TokenValidator extends ConsumerStatefulWidget {
  const _TokenValidator({required this.token});

  final String token;

  @override
  ConsumerState<_TokenValidator> createState() => _TokenValidatorState();
}

class _TokenValidatorState extends ConsumerState<_TokenValidator> {
  late final Future<bool> _validationFuture;

  @override
  void initState() {
    super.initState();
    final apiClient = ref.read(apiClientProvider);
    apiClient.setAuthToken(widget.token);

    // Wire up 401 handler once
    apiClient.onUnauthorized = () {
      ref.read(secureStorageProvider).deleteAll();
      apiClient.clearAuthToken();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    };

    _validationFuture = _validateToken(apiClient);
  }

  Future<bool> _validateToken(apiClient) async {
    try {
      await apiClient.getMe();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _validationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return const MainMenuScreen();
        }
        // Token invalid or expired
        final apiClient = ref.read(apiClientProvider);
        apiClient.clearAuthToken();
        ref.read(secureStorageProvider).deleteAll();
        return const LoginScreen();
      },
    );
  }
}

/// Debug-only: bypasses login and launches directly into a scenario game.
/// Only active when _kDevScenario is non-null and kDebugMode is true.
class _DevScenarioLauncher extends StatelessWidget {
  const _DevScenarioLauncher({required this.scenario});

  final String scenario;

  @override
  Widget build(BuildContext context) {
    return GameScreen(
      config: GameConfig(
        scenarioType: scenario,
        difficulty: 1,
        complexity: 'high',
        reinforcementMode: 'positive',
        sessionId: 'dev-session',
        userId: 'dev-user',
      ),
      onGameComplete: (_) {},
    );
  }
}
