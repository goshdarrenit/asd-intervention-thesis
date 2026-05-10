"""
State vector construction for the RL environment.

The state vector is a 60-dimensional observation combining:
- Profile features (20 dims): Demographics and behavioral tendencies
- Context features (15 dims): Current scenario and session state
- Performance features (10 dims): Recent task success and trends
- Emotion features (10 dims): Emotional state and trends
- Game theory features (5 dims): Social interaction preferences
"""

import numpy as np


def build_context_features(
    difficulty: int,
    scenario_type_idx: int,
    step: int,
    session_time: float,
    reinforcement_idx: int,
    complexity_idx: int,
    last_action_idx: int,
    max_steps: int = 100,
) -> np.ndarray:
    """
    Build 15-dimensional context feature vector.

    Args:
        difficulty: Current difficulty level (1-5)
        scenario_type_idx: Scenario type index (0-4)
        step: Current step in episode
        session_time: Elapsed session time in seconds
        reinforcement_idx: Reinforcement mode index (0-2)
        complexity_idx: Complexity level index (0-2)
        last_action_idx: Last action type index (0-14)
        max_steps: Maximum steps per episode for normalization

    Returns:
        15-dimensional numpy array
    """
    features = np.zeros(15, dtype=np.float32)

    # Dim 0: Normalized difficulty (1-5 -> 0-1)
    features[0] = (difficulty - 1) / 4.0

    # Dims 1-5: Scenario type one-hot (5 types)
    if 0 <= scenario_type_idx < 5:
        features[1 + scenario_type_idx] = 1.0

    # Dim 6: Normalized step in episode
    features[6] = step / max_steps

    # Dim 7: Normalized session time (cap at 3600s = 1 hour)
    features[7] = min(session_time / 3600.0, 1.0)

    # Dims 8-10: Reinforcement mode one-hot (3 modes)
    if 0 <= reinforcement_idx < 3:
        features[8 + reinforcement_idx] = 1.0

    # Dims 11-13: Complexity level one-hot (3 levels)
    if 0 <= complexity_idx < 3:
        features[11 + complexity_idx] = 1.0

    # Dim 14: Normalized last action type index (0-14 -> 0-1)
    features[14] = last_action_idx / 14.0

    return features


def build_performance_features(
    last_5_success: list[bool],
    rolling_success: float,
    avg_completion: float,
    scenarios_completed: int,
    streak: int,
    improvement: float,
) -> np.ndarray:
    """
    Build 10-dimensional performance feature vector.

    Args:
        last_5_success: Last 5 task outcomes (True/False)
        rolling_success: Rolling success rate (0-1)
        avg_completion: Average completion time in seconds
        scenarios_completed: Number of scenarios completed in episode
        streak: Current streak (positive or negative)
        improvement: Improvement trend (-1 to 1)

    Returns:
        10-dimensional numpy array
    """
    features = np.zeros(10, dtype=np.float32)

    # Dims 0-4: Last 5 success (0 or 1)
    for i, success in enumerate(last_5_success[-5:]):
        features[i] = 1.0 if success else 0.0

    # Fill remaining with 0 if less than 5 history items
    # (already initialized to 0)

    # Dim 5: Rolling success rate
    features[5] = np.clip(rolling_success, 0.0, 1.0)

    # Dim 6: Normalized avg completion time (cap at 60s)
    features[6] = min(avg_completion / 60.0, 1.0)

    # Dim 7: Normalized scenarios completed (cap at 20)
    features[7] = min(scenarios_completed / 20.0, 1.0)

    # Dim 8: Normalized streak (clip to [-10, 10] range, then scale to [-1, 1])
    features[8] = np.clip(streak / 10.0, -1.0, 1.0)

    # Dim 9: Improvement trend (already in [-1, 1])
    features[9] = np.clip(improvement, -1.0, 1.0)

    return features


def build_emotion_features(
    frustration: float,
    engagement: float,
    confidence: float,
    prev_frustration: float,
    prev_engagement: float,
    prev_confidence: float,
) -> np.ndarray:
    """
    Build 10-dimensional emotion feature vector with trends.

    Args:
        frustration: Current frustration level (0-1)
        engagement: Current engagement level (0-1)
        confidence: Current confidence level (0-1)
        prev_frustration: Previous frustration for trend calculation
        prev_engagement: Previous engagement for trend calculation
        prev_confidence: Previous confidence for trend calculation

    Returns:
        10-dimensional numpy array
    """
    features = np.zeros(10, dtype=np.float32)

    # Dims 0-2: Current emotion levels
    features[0] = np.clip(frustration, 0.0, 1.0)
    features[1] = np.clip(engagement, 0.0, 1.0)
    features[2] = np.clip(confidence, 0.0, 1.0)

    # Frustration trend (3 dims: current, delta, acceleration)
    frustration_delta = frustration - prev_frustration
    features[3] = features[0]  # Current frustration (repeated for convenience)
    features[4] = np.clip(frustration_delta, -1.0, 1.0)  # Delta
    # Acceleration would require 2 previous values, use 0 for now
    features[5] = 0.0

    # Engagement trend (2 dims: current, delta)
    engagement_delta = engagement - prev_engagement
    features[6] = features[1]  # Current engagement
    features[7] = np.clip(engagement_delta, -1.0, 1.0)  # Delta

    # Confidence trend (2 dims: current, delta)
    confidence_delta = confidence - prev_confidence
    features[8] = features[2]  # Current confidence
    features[9] = np.clip(confidence_delta, -1.0, 1.0)  # Delta

    return features


def build_game_theory_features(
    cooperation: float,
    risk: float,
    fairness: float,
    trust: float,
    reciprocity: float,
) -> np.ndarray:
    """
    Build 5-dimensional game theory feature vector.

    Args:
        cooperation: Cooperation score (0-1)
        risk: Risk-taking propensity (0-1)
        fairness: Fairness preference (0-1)
        trust: Trust level (0-1)
        reciprocity: Reciprocity tendency (0-1)

    Returns:
        5-dimensional numpy array
    """
    features = np.zeros(5, dtype=np.float32)

    features[0] = np.clip(cooperation, 0.0, 1.0)
    features[1] = np.clip(risk, 0.0, 1.0)
    features[2] = np.clip(fairness, 0.0, 1.0)
    features[3] = np.clip(trust, 0.0, 1.0)
    features[4] = np.clip(reciprocity, 0.0, 1.0)

    return features


def build_state_vector(
    profile_features: np.ndarray,
    context_features: np.ndarray,
    performance_features: np.ndarray,
    emotion_features: np.ndarray,
    game_theory_features: np.ndarray,
) -> np.ndarray:
    """
    Construct the full 60-dimensional state vector.

    Structure:
    - Dims 0-19: Profile features (from SyntheticUserProfile.to_profile_features())
    - Dims 20-34: Context features (difficulty, scenario, step, etc.)
    - Dims 35-44: Performance features (success history, trends)
    - Dims 45-54: Emotion features (frustration, engagement, confidence + trends)
    - Dims 55-59: Game theory features (cooperation, risk, fairness, trust, reciprocity)

    Args:
        profile_features: 20-dimensional profile vector
        context_features: 15-dimensional context vector
        performance_features: 10-dimensional performance vector
        emotion_features: 10-dimensional emotion vector
        game_theory_features: 5-dimensional game theory vector

    Returns:
        60-dimensional state vector (float32)
    """
    # Validate input shapes
    assert profile_features.shape == (20,), f"Expected profile (20,), got {profile_features.shape}"
    assert context_features.shape == (15,), f"Expected context (15,), got {context_features.shape}"
    assert performance_features.shape == (10,), f"Expected performance (10,), got {performance_features.shape}"
    assert emotion_features.shape == (10,), f"Expected emotion (10,), got {emotion_features.shape}"
    assert game_theory_features.shape == (5,), f"Expected game_theory (5,), got {game_theory_features.shape}"

    # Concatenate all components
    state = np.concatenate([
        profile_features,
        context_features,
        performance_features,
        emotion_features,
        game_theory_features,
    ], dtype=np.float32)

    # Validate output shape
    assert state.shape == (60,), f"Expected state (60,), got {state.shape}"

    return state
