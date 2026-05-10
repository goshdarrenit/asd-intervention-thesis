import 'package:flutter/material.dart';
import '../../../shared/widgets/accessible_button.dart';
import '../../../shared/widgets/accessible_card.dart';
import '../game/base_scenario_game.dart';

/// Pause menu overlay for scenario games
///
/// Features:
/// - Semi-transparent dark background
/// - Accessible card with supportive language
/// - Resume and Exit buttons with clear actions
/// - ASD-friendly: calm, supportive, no alarming language
class PauseOverlay extends StatelessWidget {
  /// The game instance
  final BaseScenarioGame game;

  /// Callback when user taps resume
  final VoidCallback onResume;

  /// Callback when user taps exit/quit
  final VoidCallback onQuit;

  const PauseOverlay({
    super.key,
    required this.game,
    required this.onResume,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Semi-transparent dark background
      color: Colors.black54,
      child: Center(
        child: AccessibleCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                'Game Paused',
                style: Theme.of(context).textTheme.displayLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Supportive subtitle
              Text(
                'Take a break if you need one',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Resume button (primary action)
              AccessibleButton(
                label: 'Resume',
                onPressed: onResume,
                variant: AccessibleButtonVariant.primary,
              ),
              const SizedBox(height: 16),

              // Main menu button (secondary action)
              AccessibleButton(
                label: 'Main Menu',
                icon: Icons.home_rounded,
                onPressed: onQuit,
                variant: AccessibleButtonVariant.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
