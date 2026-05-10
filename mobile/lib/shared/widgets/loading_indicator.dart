import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// App loading indicator for async operations
///
/// Features:
/// - Centered CircularProgressIndicator
/// - Optional message text below indicator
/// - Uses ASD-friendly primary color
/// - Used for database loading, sync operations, etc.
class AppLoadingIndicator extends StatelessWidget {
  final String? message;

  const AppLoadingIndicator({
    super.key,
    this.message = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
