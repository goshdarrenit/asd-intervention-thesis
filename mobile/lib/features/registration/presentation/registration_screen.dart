import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/accessible_button.dart';
import '../../../shared/widgets/accessible_card.dart';
import '../../home/presentation/main_menu_screen.dart';
import '../../avatar/avatar_provider.dart';
import '../providers.dart';

/// Registration screen with guardian questionnaire.
///
/// Step 1: Email + password (account credentials)
/// Step 2: Child's age (4–18 via slider)
/// Step 3: ASD severity level (1=mild, 2=moderate, 3=severe)
/// Step 4: Avatar selection
///
/// Calls POST /api/auth/register on submit -> JWT stored in secure storage.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  int _selectedAge = 8;
  int _selectedSeverity = 1;
  String _selectedAvatar = defaultAvatarKey;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  int _currentStep = 0;

  static const _totalSteps = 4;

  static const _severityLabels = {
    1: 'Level 1',
    2: 'Level 2',
    3: 'Level 3',
  };

  static const _severityDescriptions = {
    1: 'Needs some support',
    2: 'Needs substantial support',
    3: 'Needs very substantial support',
  };

  static const _severityIcons = {
    1: Icons.sentiment_satisfied_rounded,
    2: Icons.sentiment_neutral_rounded,
    3: Icons.sentiment_dissatisfied_rounded,
  };

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // Title
                Text(
                  'Create account',
                  style: theme.textTheme.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Let's set up your adventure",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Step indicator
                _buildStepIndicator(),
                const SizedBox(height: 32),

                // Step content
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildCurrentStep(theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalSteps, (index) {
        final isActive = index == _currentStep;
        final isCompleted = index < _currentStep;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isActive ? 32 : 12,
            height: 12,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.success
                  : isActive
                      ? AppColors.primary
                      : AppColors.primaryLight.withAlpha(100),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCurrentStep(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildAccountStep(theme);
      case 1:
        return _buildAgeStep(theme);
      case 2:
        return _buildSeverityStep(theme);
      case 3:
        return _buildAvatarStep(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1: Account (email + password) ─────────────────────────────────

  Widget _buildAccountStep(ThemeData theme) {
    return Column(
      key: const ValueKey('account_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccessibleCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.account_circle_rounded,
                  size: 48, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Create your account',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your login details for this device',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Email field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: theme.textTheme.bodyLarge,
                decoration: _inputDecoration(
                  theme,
                  label: 'Email',
                  hint: 'guardian@example.com',
                  icon: Icons.mail_outline_rounded,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Email is required';
                  }
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                  if (!emailRegex.hasMatch(v.trim())) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password field
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: theme.textTheme.bodyLarge,
                decoration: _inputDecoration(
                  theme,
                  label: 'Password',
                  hint: 'Min. 8 characters',
                  icon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 8) return 'Password must be at least 8 characters';
                  return null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        AccessibleButton(
          label: 'Next',
          icon: Icons.arrow_forward_rounded,
          onPressed: _validateAndNextFromAccount,
        ),
      ],
    );
  }

  void _validateAndNextFromAccount() {
    // Only validate the account fields (email + password)
    final emailValid = _emailController.text.trim().isNotEmpty &&
        RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(_emailController.text.trim());
    final passwordValid = _passwordController.text.length >= 8;

    if (!emailValid) {
      _showFieldError('Please enter a valid email address.');
      return;
    }
    if (!passwordValid) {
      _showFieldError('Password must be at least 8 characters.');
      return;
    }
    setState(() => _currentStep = 1);
  }

  void _showFieldError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Step 2: Age Selection ───────────────────────────────────────────

  Widget _buildAgeStep(ThemeData theme) {
    return Column(
      key: const ValueKey('age_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccessibleCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.cake_rounded, size: 48, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                "How old is the child?",
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              Text(
                '$_selectedAge',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontSize: 64,
                  color: AppColors.primary,
                ),
              ),
              Text(
                'years old',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('4', style: theme.textTheme.bodyMedium),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.primaryLight.withAlpha(100),
                        thumbColor: AppColors.primary,
                        overlayColor: AppColors.primary.withAlpha(40),
                        trackHeight: 8,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 16),
                      ),
                      child: Slider(
                        value: _selectedAge.toDouble(),
                        min: 4,
                        max: 18,
                        divisions: 14,
                        label: '$_selectedAge',
                        onChanged: (v) =>
                            setState(() => _selectedAge = v.round()),
                      ),
                    ),
                  ),
                  Text('18', style: theme.textTheme.bodyMedium),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: AccessibleButton(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                variant: AccessibleButtonVariant.outline,
                onPressed: () => setState(() => _currentStep = 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AccessibleButton(
                label: 'Next',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => setState(() => _currentStep = 2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 3: Severity Selection ──────────────────────────────────────

  Widget _buildSeverityStep(ThemeData theme) {
    return Column(
      key: const ValueKey('severity_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Support level',
            style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'This helps us personalise the experience',
          style:
              theme.textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        ...List.generate(3, (index) {
          final level = index + 1;
          final isSelected = _selectedSeverity == level;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSeverityCard(
                theme: theme, level: level, isSelected: isSelected),
          );
        }),

        const SizedBox(height: 8),

        // Summary card
        AccessibleCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Summary', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildSummaryRow(
                  theme, Icons.mail_outline_rounded, 'Email', _emailController.text),
              const SizedBox(height: 8),
              _buildSummaryRow(
                  theme, Icons.cake_rounded, 'Age', '$_selectedAge years'),
              const SizedBox(height: 8),
              _buildSummaryRow(
                theme,
                _severityIcons[_selectedSeverity]!,
                'Support',
                _severityLabels[_selectedSeverity]!,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: AccessibleButton(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                variant: AccessibleButtonVariant.outline,
                onPressed: () => setState(() => _currentStep = 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AccessibleButton(
                label: 'Next',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => setState(() => _currentStep = 3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSeverityCard({
    required ThemeData theme,
    required int level,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _selectedSeverity = level),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '${_severityLabels[level]}: ${_severityDescriptions[level]}',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.primaryLight.withAlpha(100),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(40),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                _severityIcons[level],
                size: 40,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _severityLabels[level]!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _severityDescriptions[level]!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 4: Avatar Selection ────────────────────────────────────────

  Widget _buildAvatarStep(ThemeData theme) {
    return Column(
      key: const ValueKey('avatar_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccessibleCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.face_rounded, size: 48, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Choose your avatar',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a character for the adventure',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
                children: avatarKeys
                    .map((key) => _buildAvatarOption(key))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: AccessibleButton(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                variant: AccessibleButtonVariant.outline,
                onPressed: _isSubmitting ? null : () => setState(() => _currentStep = 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AccessibleButton(
                label: "Let's go!",
                icon: Icons.rocket_launch_rounded,
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarOption(String key) {
    final isSelected = _selectedAvatar == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedAvatar = key),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: 'Avatar $key',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isSelected ? AppColors.surface : Colors.white,
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.primaryLight.withAlpha(100),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(40),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Center(
                child: Image.asset(
                  avatarAssetPath(key),
                  fit: BoxFit.contain,
                ),
              ),
              if (isSelected)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
      ThemeData theme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 24, color: AppColors.primary),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style:
              theme.textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(
    ThemeData theme, {
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: AppColors.primaryLight.withAlpha(150)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  Future<void> _onSubmit() async {
    setState(() => _isSubmitting = true);

    try {
      await ref.read(registrationProvider.notifier).register(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            age: _selectedAge,
            severityLevel: _selectedSeverity,
          );

      await ref.read(avatarProvider.notifier).setAvatar(_selectedAvatar);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainMenuScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showRegistrationError(e.toString());
      }
    }
  }

  void _showRegistrationError(String message) {
    // Check for duplicate email error
    final isDuplicate = message.contains('409') || message.contains('already registered');
    final displayMessage = isDuplicate
        ? 'That email is already registered. Try logging in instead.'
        : 'Could not register. Please try again.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMessage, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
