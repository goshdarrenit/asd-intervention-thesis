"""AI peer strategy for game theory scenarios.
Strategies:
- Difficulty 1-2: Always cooperate (encouraging for learners)
- Difficulty 3: Tit-for-tat (reciprocation, starts cooperative)
- Difficulty 4-5: Stochastic tit-for-tat (70% reciprocate, 30% random)
"""
import numpy as np


def ai_peer_action(
    user_history: list[str],
    difficulty: int,
    rng: np.random.Generator
) -> str:
    """Determine AI peer's next action based on difficulty and user history.

    Args:
        user_history: List of user's previous actions ("cooperate" or "defect")
        difficulty: Integer in range [1, 5]
        rng: Numpy random generator for stochastic strategies

    Returns:
        "cooperate" or "defect"

    Example:
        >>> rng = np.random.default_rng(42)
        >>> ai_peer_action([], 1, rng)
        'cooperate'
        >>> ai_peer_action(['cooperate'], 3, rng)
        'cooperate'
        >>> ai_peer_action(['defect'], 3, rng)
        'defect'
    """
    assert 1 <= difficulty <= 5, f"Difficulty must be in [1, 5], got {difficulty}"

    if difficulty <= 2:
        # Always cooperate (encouraging for beginners)
        return "cooperate"

    elif difficulty == 3:
        # Tit-for-tat: copy opponent's last move, start cooperative
        if len(user_history) == 0:
            return "cooperate"
        else:
            return user_history[-1]

    else:  # difficulty 4-5
        # Stochastic tit-for-tat: 70% reciprocate, 30% random
        if rng.random() < 0.3:
            # Random action
            return "cooperate" if rng.random() < 0.5 else "defect"
        else:
            # Tit-for-tat
            if len(user_history) == 0:
                return "cooperate"
            else:
                return user_history[-1]
