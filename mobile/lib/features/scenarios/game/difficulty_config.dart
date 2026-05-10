/// All 5 scenario types:
/// - sharing: drag-drop toy sharing
/// - patience: impulse control with timer
/// - emotion_recognition: face-to-label matching
/// - turn_taking: alternating turns with AI peer
/// - conflict_resolution: multi-level choice tree
class DifficultyConfig {
  /// Get combined difficulty + complexity configuration for a scenario
  ///
  /// [scenarioType] - One of: sharing, patience, emotion_recognition, turn_taking, conflict_resolution
  /// [difficulty] - Level 1-5
  /// [complexity] - 'low', 'medium', or 'high'
  ///
  /// Returns map with scenario-specific parameters, or empty map if invalid type.
  static Map<String, dynamic> getConfig(
    String scenarioType,
    int difficulty,
    String complexity,
  ) {
    switch (scenarioType) {
      case 'sharing':
        return _getSharingConfig(difficulty, complexity);
      case 'patience':
        return _getPatienceConfig(difficulty, complexity);
      case 'emotion_recognition':
        return _getEmotionRecognitionConfig(difficulty, complexity);
      case 'turn_taking':
        return _getTurnTakingConfig(difficulty, complexity);
      case 'conflict_resolution':
        return _getConflictResolutionConfig(difficulty, complexity);
      default:
        return {}; // Invalid scenario type
    }
  }

  // Private configuration methods for each scenario type

  static Map<String, dynamic> _getSharingConfig(int difficulty, String complexity) {
    // Difficulty: drag distance and time limit
    final dragDistances = [100.0, 150.0, 200.0, 275.0, 375.0];
    final timeLimits = [null, 30, 25, 20, 15]; // null = no time limit

    // Complexity: number of toys and peers
    final toyPeerCounts = {
      'low': {'toys': 1, 'peers': 1},
      'medium': {'toys': 2, 'peers': 1},
      'high': {'toys': 3, 'peers': 2},
    };

    final difficultyIndex = difficulty - 1; // Convert 1-5 to 0-4 index
    return {
      'drag_distance': dragDistances[difficultyIndex],
      'time_limit_seconds': timeLimits[difficultyIndex],
      ...toyPeerCounts[complexity]!,
    };
  }

  static Map<String, dynamic> _getPatienceConfig(int difficulty, String complexity) {
    // Difficulty: wait time and early tap penalty
    final waitTimes = [5, 8, 12, 18, 25];
    final earlyTapPenalties = [0.0, 0.2, 0.4, 0.6, 0.8];

    // Complexity: number of sequential rewards
    final rewardCounts = {
      'low': 1,
      'medium': 2,
      'high': 3,
    };

    final difficultyIndex = difficulty - 1;
    return {
      'wait_seconds': waitTimes[difficultyIndex],
      'early_tap_penalty': earlyTapPenalties[difficultyIndex],
      'reward_count': rewardCounts[complexity]!,
    };
  }

  static Map<String, dynamic> _getEmotionRecognitionConfig(
      int difficulty, String complexity) {
    // Difficulty: available emotion pool grows as difficulty increases
    // Assets available: happy, sad, angry, confused, sorry
    final emotionSets = [
      ['happy', 'sad', 'angry'], // d1: basic 3
      ['happy', 'sad', 'angry', 'confused'], // d2: add confused
      ['happy', 'sad', 'angry', 'confused', 'sorry'], // d3: add sorry
      ['happy', 'sad', 'angry', 'confused', 'sorry'], // d4: full set, more faces
      ['happy', 'sad', 'angry', 'confused', 'sorry'], // d5: full set, most faces
    ];

    // Complexity: number of faces to match
    final faceCounts = {
      'low': 2,
      'medium': 3,
      'high': 4,
    };

    final difficultyIndex = difficulty - 1;
    return {
      'emotion_set': List<String>.from(emotionSets[difficultyIndex]),
      'face_count': faceCounts[complexity]!,
    };
  }

  static Map<String, dynamic> _getTurnTakingConfig(int difficulty, String complexity) {
    // Difficulty: AI turn delay (faster = harder to follow)
    final aiTurnDelays = [2000, 1500, 1000, 700, 500]; // milliseconds

    // Complexity: total number of turns
    final turnCounts = {
      'low': 4,
      'medium': 6,
      'high': 8,
    };

    final difficultyIndex = difficulty - 1;
    return {
      'ai_turn_delay_ms': aiTurnDelays[difficultyIndex],
      'turn_count': turnCounts[complexity]!,
    };
  }

  static Map<String, dynamic> _getConflictResolutionConfig(
      int difficulty, String complexity) {
    // Difficulty: choice time limit and wrong choice penalty
    final timeLimits = [null, 20, 15, 12, 10]; // null = no time limit
    final wrongPenalties = [0.0, 0.1, 0.2, 0.3, 0.4];

    // Complexity: number of choices per level and number of decision levels
    final choiceLevelCounts = {
      'low': {'choices_per_level': 2, 'levels': 1},
      'medium': {'choices_per_level': 3, 'levels': 2},
      'high': {'choices_per_level': 3, 'levels': 3},
    };

    final difficultyIndex = difficulty - 1;
    return {
      'time_limit_seconds': timeLimits[difficultyIndex],
      'wrong_choice_penalty': wrongPenalties[difficultyIndex],
      ...choiceLevelCounts[complexity]!,
    };
  }
}
