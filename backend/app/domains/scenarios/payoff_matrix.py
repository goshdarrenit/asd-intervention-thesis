"""Game theory payoff matrices for social skill scenarios.

Each matrix represents a 2-player game between user and AI peer:
  - Matrix[i, j] = payoff to user when user plays action i, AI plays action j
  - i, j in {0: cooperate, 1: defect}
"""
import numpy as np


def generate_payoff_matrix(scenario_type: str, difficulty: int) -> np.ndarray:
    """Generate a 2x2 payoff matrix for the given scenario type and difficulty.

    Args:
        scenario_type: One of "sharing", "patience", "emotion_recognition",
                      "turn_taking", "conflict_resolution"
        difficulty: Integer in range [1, 5] affecting temptation to defect

    Returns:
        2x2 numpy array representing user payoffs (rows=user actions, cols=AI actions)

    Example:
        >>> matrix = generate_payoff_matrix("sharing", 3)
        >>> matrix.shape
        (2, 2)
    """
    assert 1 <= difficulty <= 5, f"Difficulty must be in [1, 5], got {difficulty}"

    # Base payoff structure (higher = better)
    # difficulty 1-2: Low temptation to defect (more cooperative)
    # difficulty 3: Balanced
    # difficulty 4-5: High temptation to defect (more nuanced)

    # Temptation scaling: how much better defection is when opponent cooperates
    temptation_scale = 0.5 + (difficulty - 1) * 0.2  # [0.5, 1.3]

    # Sucker payoff scaling: how bad cooperation is when opponent defects
    sucker_penalty = 0.5 - (difficulty - 1) * 0.1  # [0.5, 0.1]

    if scenario_type == "sharing":
        # Classic cooperation dilemma: share vs hoard
        # (cooperate, cooperate) = both share = both happy (3, 3)
        # (cooperate, defect) = I share, they hoard = I get little, they get much
        # (defect, cooperate) = I hoard, they share = I get much, they get little
        # (defect, defect) = both hoard = both get moderate (1, 1)
        reward = 3.0
        temptation = reward + temptation_scale
        sucker = sucker_penalty
        punishment = 1.0

    elif scenario_type == "patience":
        # Delayed gratification vs impulsive payoff
        # (cooperate, cooperate) = both wait = both get better outcome
        # (cooperate, defect) = I wait, they grab = I miss out
        # (defect, cooperate) = I grab, they wait = I get immediate gain
        # (defect, defect) = both grab = both get lesser quality
        reward = 3.5
        temptation = reward + temptation_scale * 0.8
        sucker = sucker_penalty * 0.8
        punishment = 1.5

    elif scenario_type == "emotion_recognition":
        # Correct vs incorrect identification
        # (cooperate, cooperate) = both identify correctly = mutual understanding
        # (cooperate, defect) = I'm correct, they're wrong = asymmetric
        # (defect, cooperate) = I'm wrong, they're correct = learning opportunity
        # (defect, defect) = both wrong = confusion
        reward = 4.0
        temptation = reward + temptation_scale * 0.6
        sucker = sucker_penalty * 1.2
        punishment = 0.5

    elif scenario_type == "turn_taking":
        # Wait vs cut in line
        # (cooperate, cooperate) = both take turns = fair and orderly
        # (cooperate, defect) = I wait, they cut = unfair to me
        # (defect, cooperate) = I cut, they wait = unfair to them
        # (defect, defect) = both cut = conflict/chaos
        reward = 3.2
        temptation = reward + temptation_scale * 1.1
        sucker = sucker_penalty * 0.6
        punishment = 0.8

    elif scenario_type == "conflict_resolution":
        # De-escalate vs escalate
        # (cooperate, cooperate) = both de-escalate = peace
        # (cooperate, defect) = I de-escalate, they escalate = I'm vulnerable
        # (defect, cooperate) = I escalate, they de-escalate = I dominate
        # (defect, defect) = both escalate = mutual harm
        reward = 3.8
        temptation = reward + temptation_scale * 1.3
        sucker = sucker_penalty * 0.4
        punishment = 0.2

    else:
        raise ValueError(f"Unknown scenario type: {scenario_type}")

    # Construct payoff matrix (user's perspective)
    # Rows: user's action (0=cooperate, 1=defect)
    # Cols: AI's action (0=cooperate, 1=defect)
    matrix = np.array([
        [reward, sucker],       # User cooperates
        [temptation, punishment]  # User defects
    ], dtype=np.float32)

    return matrix


def compute_game_features(payoff_matrix: np.ndarray) -> np.ndarray:
    """Extract 5 heuristic game theory features from a 2x2 payoff matrix.

    These features correspond to the 5 game theory dimensions in the RL state vector.

    Args:
        payoff_matrix: 2x2 numpy array of payoffs

    Returns:
        5-dimensional numpy array with features:
          [cooperation_incentive, risk, fairness, trust, reciprocity]

    Example:
        >>> matrix = generate_payoff_matrix("sharing", 3)
        >>> features = compute_game_features(matrix)
        >>> features.shape
        (5,)
    """
    assert payoff_matrix.shape == (2, 2), f"Expected 2x2 matrix, got {payoff_matrix.shape}"

    # Extract payoffs (user's perspective)
    reward = payoff_matrix[0, 0]       # Both cooperate
    sucker = payoff_matrix[0, 1]       # I cooperate, they defect
    temptation = payoff_matrix[1, 0]   # I defect, they cooperate
    punishment = payoff_matrix[1, 1]   # Both defect

    # 1. Cooperation incentive: How much better is mutual cooperation than defection?
    # Normalized to [0, 1] where higher = stronger cooperation incentive
    cooperation_incentive = np.clip((reward - punishment) / (reward + 1e-6), 0, 1)

    # 2. Risk: How risky is cooperation? (temptation - reward) / reward
    # Higher = more temptation to defect
    risk = np.clip((temptation - reward) / (reward + 1e-6), 0, 1)

    # 3. Fairness: How symmetric is the cooperative outcome?
    # 1 - variance of cooperative payoffs (closer to 1 = fairer)
    fairness = 1.0 - np.clip(abs(reward - reward) / (reward + 1e-6), 0, 1)  # Always 1 for symmetric game

    # 4. Trust: How bad is being exploited? (reward - sucker) / reward
    # Higher trust = smaller penalty for being suckered
    trust_penalty = np.clip((reward - sucker) / (reward + 1e-6), 0, 1)
    trust = 1.0 - trust_penalty  # Invert so higher = more trustworthy

    # 5. Reciprocity: Difference between mutual cooperation and mutual defection
    # Normalized to [0, 1]
    max_payoff = max(reward, temptation, punishment, sucker)
    reciprocity = np.clip((reward - punishment) / (max_payoff + 1e-6), 0, 1)

    return np.array([
        cooperation_incentive,
        risk,
        fairness,
        trust,
        reciprocity
    ], dtype=np.float32)
