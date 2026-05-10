"""Difficulty and reward calculation helpers for scenario feedback.

Provides utilities for:
- Calculating adjusted difficulty levels (clamped 1-5)
- Computing rewards based on success, time, difficulty, and emotions
- Generating non-stigmatizing encouragement messages
"""


def calculate_difficulty(current: int, delta: int) -> int:
    """Calculate new difficulty level, clamped to [1, 5].

    Args:
        current: Current difficulty level (1-5)
        delta: Difficulty adjustment from RL model (-2 to +2)

    Returns:
        New difficulty level clamped to valid range [1, 5]

    Example:
        >>> calculate_difficulty(3, 2)
        5
        >>> calculate_difficulty(1, -2)
        1
    """
    return max(1, min(5, current + delta))


def calculate_reward(
    success: bool,
    completion_time_ms: int,
    difficulty: int,
    emotions: dict[str, float],
) -> float:
    """Calculate reward for scenario completion.

    Reward components:
    - Base: 1.0 if success, 0.3 if failure (participation credit)
    - Time bonus: up to +0.2 for completing faster than target time
    - Emotion penalty: up to -0.3 for high frustration

    Target time formula: 10000 + (difficulty-1) * 12500 ms
    - Difficulty 1: 10s target
    - Difficulty 2: 22.5s target
    - Difficulty 3: 35s target
    - Difficulty 4: 47.5s target
    - Difficulty 5: 60s target

    Args:
        success: Whether scenario was completed successfully
        completion_time_ms: Time taken in milliseconds
        difficulty: Scenario difficulty (1-5)
        emotions: Emotion dict with keys: frustration, engagement, confidence

    Returns:
        Reward value clamped to [0.0, 1.0]

    Example:
        >>> calculate_reward(True, 8000, 1, {"frustration": 0.1})
        1.2  # Will be clamped to 1.0
        >>> calculate_reward(False, 50000, 3, {"frustration": 0.8})
        0.06  # 0.3 base - 0.24 frustration penalty
    """
    # Base reward
    reward = 1.0 if success else 0.3

    # Time bonus: reward faster completion
    target_time_ms = 10000 + (difficulty - 1) * 12500
    if completion_time_ms < target_time_ms:
        time_ratio = completion_time_ms / target_time_ms
        # Linear bonus: 0.2 at instant completion, 0.0 at target time
        time_bonus = 0.2 * (1.0 - time_ratio)
        reward += time_bonus

    # Emotion penalty: penalize high frustration
    frustration = emotions.get("frustration", 0.0)
    emotion_penalty = 0.3 * frustration
    reward -= emotion_penalty

    # Clamp to valid range
    return max(0.0, min(1.0, reward))


def generate_encouragement(success: bool, emotions: dict[str, float]) -> str:
    """Generate non-stigmatizing encouragement message.

    Messages are supportive and non-stigmatizing.
    Explain consequences (how others feel), not morality (right/wrong).
    Adapts tone based on success and emotional state.

    Args:
        success: Whether scenario was completed successfully
        emotions: Emotion dict with keys: frustration, engagement, confidence

    Returns:
        Encouragement message string

    Examples:
        - Success + high engagement: "Excellent work! You helped your friend feel happy!"
        - Success: "Good job! Everyone had a great time."
        - Failure + high frustration: "That was tricky. Take your time — you can try again!"
        - Failure: "Nice try! Next time, think about how your friend might feel."
    """
    engagement = emotions.get("engagement", 0.5)
    frustration = emotions.get("frustration", 0.3)

    if success:
        if engagement > 0.7:
            return "Excellent work! You helped your friend feel happy!"
        else:
            return "Good job! Everyone had a great time."
    else:
        if frustration > 0.6:
            return "That was tricky. Take your time — you can try again!"
        else:
            return "Nice try! Next time, think about how your friend might feel."
