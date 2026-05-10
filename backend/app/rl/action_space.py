"""Action space configuration for RL environment.

Defines the 225 discrete actions (5x5x3x3) shared between training and inference.
Action type: 5 core scenario types
Difficulty delta: -2, -1, 0, +1, +2
Reinforcement mode: positive, neutral, corrective
Complexity level: low, medium, high
"""

# 225 actions = 5 types x 5 difficulty deltas x 3 reinforcement modes x 3 complexity levels
ACTION_SPACE_CONFIG = {
    "n_actions": 225,
    "action_types": [
        "sharing",
        "patience",
        "emotion_recognition",
        "turn_taking",
        "conflict_resolution",
    ],
    "difficulty_deltas": [-2, -1, 0, 1, 2],  # Change in difficulty
    "reinforcement_modes": ["positive", "neutral", "corrective"],
    "complexity_levels": ["low", "medium", "high"],
}


def decode_action(action_index: int) -> dict:
    """Decode flat action index (0-224) into structured components.

    Args:
        action_index: Integer in range [0, 224]

    Returns:
        Dictionary with keys: action_type, difficulty_delta, reinforcement_mode, complexity_level

    Example:
        >>> decode_action(0)
        {'action_type': 'sharing', 'difficulty_delta': -2, 'reinforcement_mode': 'positive', 'complexity_level': 'low'}
        >>> decode_action(224)
        {'action_type': 'conflict_resolution', 'difficulty_delta': 2, 'reinforcement_mode': 'corrective', 'complexity_level': 'high'}
    """
    assert 0 <= action_index < 225, f"Invalid action index: {action_index}"

    # Decompose using integer division and modulo
    action_type_idx = action_index // 45
    remainder = action_index % 45
    difficulty_delta_idx = remainder // 9
    remainder = remainder % 9
    reinforcement_idx = remainder // 3
    complexity_idx = remainder % 3

    return {
        "action_type": ACTION_SPACE_CONFIG["action_types"][action_type_idx],
        "difficulty_delta": ACTION_SPACE_CONFIG["difficulty_deltas"][difficulty_delta_idx],
        "reinforcement_mode": ACTION_SPACE_CONFIG["reinforcement_modes"][reinforcement_idx],
        "complexity_level": ACTION_SPACE_CONFIG["complexity_levels"][complexity_idx],
    }


def encode_action(
    action_type_idx: int,
    difficulty_delta_idx: int,
    reinforcement_idx: int,
    complexity_idx: int,
) -> int:
    """Encode structured action components into flat index.

    Args:
        action_type_idx: Index into ACTION_SPACE_CONFIG["action_types"] (0-4)
        difficulty_delta_idx: Index into ACTION_SPACE_CONFIG["difficulty_deltas"] (0-4)
        reinforcement_idx: Index into ACTION_SPACE_CONFIG["reinforcement_modes"] (0-2)
        complexity_idx: Index into ACTION_SPACE_CONFIG["complexity_levels"] (0-2)

    Returns:
        Flat action index in range [0, 224]

    Example:
        >>> encode_action(0, 0, 0, 0)
        0
        >>> encode_action(4, 4, 2, 2)
        224
    """
    return (
        action_type_idx * 45
        + difficulty_delta_idx * 9
        + reinforcement_idx * 3
        + complexity_idx
    )
