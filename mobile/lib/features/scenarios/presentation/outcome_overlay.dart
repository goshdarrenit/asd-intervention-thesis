import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/accessible_button.dart';
import '../../../shared/widgets/accessible_card.dart';
import '../game/base_scenario_game.dart';

/// Outcome overlay for scenario completion 
///
/// Features:
/// - Gentle scale-up animation on appearance
/// - Star-based reward display (0.0-1.0 reward mapped to 0-5 stars)
/// - Encouraging ASD-friendly text (no negative language)
/// - Success: "Great job!" with trophy icon
/// - Failure: "Nice try! Let's try again" with supportive icon (no red, no negative language)
class OutcomeOverlay extends StatefulWidget {
  /// The game instance
  final BaseScenarioGame game;

  /// Callback when user taps continue
  final VoidCallback onContinue;

  const OutcomeOverlay({
    super.key,
    required this.game,
    required this.onContinue,
  });

  @override
  State<OutcomeOverlay> createState() => _OutcomeOverlayState();
}

class _OutcomeOverlayState extends State<OutcomeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Create gentle scale-up animation
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    // Start animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.game.outcome!;

    return Container(
      // Semi-transparent dark background
      color: Colors.black54,
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AccessibleCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon (success or encouraging)
                _buildIcon(outcome.success),
                const SizedBox(height: 24),

                // Title text
                Text(
                  _getTitle(outcome.success),
                  style: Theme.of(context).textTheme.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Subtitle text
                Text(
                  _getSubtitle(outcome.success),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Star reward display
                _buildStarReward(outcome.reward),
                const SizedBox(height: 32),

                // Continue button
                AccessibleButton(
                  label: 'Continue',
                  onPressed: widget.onContinue,
                  variant: AccessibleButtonVariant.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build icon based on success state
  Widget _buildIcon(bool success) {
    if (success) {
      // Success: trophy icon in reward gold
      return Icon(
        Icons.emoji_events,
        size: 64,
        color: AppColors.rewardGold,
      );
    } else {
      // Failure: supportive thumbs up (not red, not negative)
      return Icon(
        Icons.thumb_up,
        size: 64,
        color: AppColors.secondary,
      );
    }
  }

  /// Get title text (ASD-friendly, factual, encouraging)
  String _getTitle(bool success) {
    if (success) {
      return 'Great job!';
    } else {
      return 'Nice try!';
    }
  }

  /// Get subtitle text (specific, encouraging, no negative language)
  String _getSubtitle(bool success) {
    if (success) {
      return 'You completed the scenario!';
    } else {
      return "Let's try again";
    }
  }

  /// Build star reward display (0.0-1.0 reward mapped to 0-5 stars)
  Widget _buildStarReward(double reward) {
    // Map reward (0.0-1.0) to star count (0-5)
    final starCount = (reward * 5).round().clamp(0, 5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < starCount ? Icons.star : Icons.star_outline,
          size: 32,
          color: AppColors.rewardGold,
        );
      }),
    );
  }
}
