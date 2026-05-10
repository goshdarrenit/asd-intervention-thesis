"""Behavioral model for simulating synthetic user responses.

Simulates realistic user behavior in response to intervention actions.
Used in RL environment's step() function.
"""
import numpy as np

from app.synthetic_users.profile import SyntheticUserProfile


def simulate_user_response(
    profile: SyntheticUserProfile,
    action: dict,  # decoded action from action_space.decode_action()
    current_difficulty: int,
    step_in_episode: int,
    rng: np.random.Generator,
) -> dict:
    """Simulate user response to an intervention action.

    Args:
        profile: SyntheticUserProfile with behavioral characteristics
        action: Decoded action dict with keys: action_type, difficulty_delta,
                reinforcement_mode, complexity_level
        current_difficulty: Current task difficulty (1-5)
        step_in_episode: Current step number in episode
        rng: Numpy random generator for stochastic behavior

    Returns:
        Dictionary with keys:
            - task_completed (bool): Whether user completed the task
            - decision_time (float): Time to make decision (seconds)
            - num_pauses (int): Number of pauses during task
            - num_retries (int): Number of retry attempts
            - quit_early (bool): Whether user quit before completion
            - completion_time (float): Total time to complete task (seconds)
            - engagement_score (float): Engagement level (0-1)
    """
    # 1. Task completion probability
    # Base success depends on learning rate and severity
    base_success = 0.5 + 0.3 * profile.learning_rate - 0.15 * (profile.severity - 1)

    # Difficulty modifier: harder tasks are less likely to succeed
    difficulty_modifier = -0.1 * action["difficulty_delta"]

    # Clamp to [0.1, 0.95]
    success_prob = max(0.1, min(0.95, base_success + difficulty_modifier))
    task_completed = rng.random() < success_prob

    # 2. Decision time with domain randomization noise
    decision_time = profile.apply_noise(profile.avg_decision_time, rng)
    decision_time = max(0.5, decision_time)  # minimum 0.5 seconds

    # 3. Pauses and retries based on profile
    num_pauses = sum(1 for _ in range(5) if rng.random() < profile.pause_probability)
    num_retries = (
        sum(1 for _ in range(3) if rng.random() < profile.retry_probability)
        if not task_completed
        else 0
    )

    # 4. Quit early probability (frustration-based)
    quit_prob = (1.0 - profile.frustration_tolerance) * 0.3
    if action["difficulty_delta"] > 0:
        quit_prob += 0.1
    quit_early = rng.random() < quit_prob and not task_completed

    # 5. Completion time (proportional to decision time and complexity)
    complexity_multiplier = {
        "low": 0.7,
        "medium": 1.0,
        "high": 1.4,
    }[action["complexity_level"]]

    completion_time = decision_time * 5 * complexity_multiplier
    completion_time = profile.apply_noise(completion_time, rng)
    completion_time = max(1.0, completion_time)  # minimum 1 second

    # 6. Engagement score (inverse of completion time ratio)
    # Expected time for medium complexity is ~25 seconds (5 * 5)
    expected_time = 25.0
    engagement_score = max(0.0, min(1.0, 1.0 - (completion_time - expected_time) / expected_time))

    return {
        "task_completed": task_completed,
        "decision_time": decision_time,
        "num_pauses": num_pauses,
        "num_retries": num_retries,
        "quit_early": quit_early,
        "completion_time": completion_time,
        "engagement_score": engagement_score,
    }
