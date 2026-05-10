"""Multi-objective reward calculation.

40% task success + 30% engagement + 30% emotional well-being.
"""


def calculate_reward(
    task_completed: bool,
    engagement: float,
    frustration: float,
    confidence: float
) -> float:
    """
    Calculate multi-objective reward with 40/30/30 weighting.

    Args:
        task_completed: Whether the task was successfully completed
        engagement: Engagement score [0, 1]
        frustration: Frustration level [0, 1]
        confidence: Confidence level [0, 1]

    Returns:
        Combined reward score

    Requirements:
        Multi-objective reward function (40% task + 30% engagement + 30% emotion)

    Formula:
        reward = 0.4 * task_reward + 0.3 * engagement_reward + 0.3 * emotion_reward

        Where:
        - task_reward: 1.0 if completed, -0.01 if not (small penalty)
        - engagement_reward: engagement score [0, 1]
        - emotion_reward: (1 - frustration) * 0.5 + confidence * 0.5 (well-being composite)
    """
    # Task reward: binary success with small penalty for failure
    task_reward = 1.0 if task_completed else -0.01

    # Engagement reward: already normalized [0, 1]
    engagement_reward = engagement

    # Emotional well-being: composite of low frustration (50%) and high confidence (50%)
    emotion_reward = (1.0 - frustration) * 0.5 + confidence * 0.5

    # Multi-objective weighted sum: 40/30/30
    reward = 0.4 * task_reward + 0.3 * engagement_reward + 0.3 * emotion_reward

    return reward
