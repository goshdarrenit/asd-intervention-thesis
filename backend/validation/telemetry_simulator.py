"""Deterministic per-persona behavioral telemetry generation.

Maps ASD persona traits to realistic behavioral signals that match what the
emotion_inference.py formulas expect:
  frustration = 0.3*min(1,pauses/3) + 0.3*min(1,retries/3) + 0.4*quit_early
  engagement  = f(completion_time / expected_completion_time)
  confidence  = decision_speed - hesitation_penalty
"""
import random
import math


# Base parameters per persona
# pause_base: mean pauses at difficulty 1
# pause_per_diff: added pauses per difficulty increment
# retry_base: mean retries at difficulty 1
# hesitation_ms: mean decision time in milliseconds
# quit_prob: base probability of quit_early per scenario
# quit_per_diff: additional quit probability per difficulty level
# success_prob: base probability of task success

_PERSONA_PARAMS: dict[str, dict] = {
    "low_verbal": {
        "pause_base": 5, "pause_per_diff": 0.8,
        "retry_base": 3,
        "hesitation_ms": 8000, "quit_prob": 0.20, "quit_per_diff": 0.04,
        "success_prob": 0.65,
    },
    "high_anxiety": {
        "pause_base": 7, "pause_per_diff": 0.9,
        "retry_base": 1,
        "hesitation_ms": 12000, "quit_prob": 0.08, "quit_per_diff": 0.10,
        "success_prob": 0.55,
    },
    "rigid_routine": {
        "pause_base": 3, "pause_per_diff": 0.5,
        "retry_base": 2,
        "hesitation_ms": 5000, "quit_prob": 0.10, "quit_per_diff": 0.06,
        "success_prob_familiar": 0.70, "success_prob_novel": 0.40,
        "success_prob": 0.65,  # fallback
    },
    "high_masking": {
        "pause_base": 2, "pause_per_diff": 0.3,
        "retry_base": 2,
        "hesitation_ms": 9000, "quit_prob": 0.05, "quit_per_diff": 0.03,
        "success_prob": 0.80,
    },
    "sensory_sensitive": {
        "pause_base": 2, "pause_per_diff": 0.4,
        "retry_base": 5,
        "hesitation_ms": 2000, "quit_prob": 0.30, "quit_per_diff": 0.08,
        "success_prob": 0.50,
    },
}

# Scenario-type multipliers applied on top of base values
# Keys: pause_mult, retry_mult, quit_mult, success_mult, hesitation_mult
# Default 1.0 for any omitted key
_SCENARIO_MODIFIERS: dict[str, dict[str, dict]] = {
    "sharing": {
        "low_verbal":        {"pause_mult": 1.3, "success_mult": 0.9},
        "high_anxiety":      {"pause_mult": 1.1},
        "rigid_routine":     {},  # familiar interaction type
        "sensory_sensitive": {"quit_mult": 1.5},
    },
    "patience": {
        "low_verbal":        {"pause_mult": 1.1},
        "high_anxiety":      {"pause_mult": 1.4, "quit_mult": 1.6},
        "rigid_routine":     {"success_mult": 1.1},  # predictable: slightly easier
        "sensory_sensitive": {"quit_mult": 2.0, "retry_mult": 1.3},
    },
    "emotion_recognition": {
        "low_verbal":        {"pause_mult": 1.5, "success_mult": 0.75},
        "high_anxiety":      {"pause_mult": 1.2, "hesitation_mult": 1.5},
        "rigid_routine":     {"success_mult": 0.85},
        "high_masking":      {"hesitation_mult": 1.4},
    },
    "turn_taking": {
        "high_anxiety":      {"pause_mult": 1.3, "quit_mult": 1.2},
        "rigid_routine":     {"success_mult": 1.2},  # structured = familiar
        "sensory_sensitive": {"retry_mult": 1.8, "quit_mult": 1.4},
    },
    "conflict_resolution": {
        "low_verbal":        {"success_mult": 0.8},
        "high_anxiety":      {"quit_mult": 1.8},
        "rigid_routine":     {"quit_mult": 2.0, "pause_mult": 1.6},
        "high_masking":      {"success_mult": 0.9},
        "sensory_sensitive": {"quit_mult": 1.7},
    },
}

# Target completion time in seconds per difficulty level (mirrors emotion_inference defaults)
_EXPECTED_COMPLETION_SECS = {1: 15.0, 2: 22.0, 3: 30.0, 4: 40.0, 5: 55.0}


def _get_mod(persona: str, scenario_type: str, key: str, default: float = 1.0) -> float:
    return _SCENARIO_MODIFIERS.get(scenario_type, {}).get(persona, {}).get(key, default)


def generate_telemetry(
    persona_name: str,
    scenario_type: str,
    difficulty: int,
    complexity: str,
    scenario_position: int,
    session_history: list[str] | None = None,
    seed: int | None = None,
) -> dict:
    """Generate realistic behavioral telemetry for a given persona and scenario.

    Returns a dict matching the submit endpoint's telemetry format plus
    `success` and `completion_time_ms` at the top level.

    Args:
        persona_name: One of the 5 persona names.
        scenario_type: One of the 5 game types.
        difficulty: 1–5.
        complexity: "low", "medium", or "high".
        scenario_position: 0-indexed position within the session (0–4).
        session_history: List of previous scenario_types this session (for rigid_routine novelty).
        seed: RNG seed for reproducibility. Defaults to hash of inputs.
    """
    if persona_name not in _PERSONA_PARAMS:
        raise ValueError(f"Unknown persona: {persona_name}")

    if seed is None:
        seed = hash((persona_name, scenario_type, difficulty, scenario_position)) % (2**31)

    rng = random.Random(seed)
    p = _PERSONA_PARAMS[persona_name]

    # --- Pause count ---
    pause_mean = p["pause_base"] + p["pause_per_diff"] * (difficulty - 1)
    pause_mean *= _get_mod(persona_name, scenario_type, "pause_mult")
    # Fatigue: later scenarios add extra pauses
    pause_mean += min(2, scenario_position // 2)
    pause_count = max(0, round(rng.gauss(pause_mean, pause_mean * 0.3)))

    # --- Retry count ---
    retry_mean = p["retry_base"] * _get_mod(persona_name, scenario_type, "retry_mult")
    retry_count = max(0, round(rng.gauss(retry_mean, retry_mean * 0.4)))

    # --- Quit probability ---
    quit_prob = p["quit_prob"] + p.get("quit_per_diff", 0.0) * (difficulty - 1)
    quit_prob *= _get_mod(persona_name, scenario_type, "quit_mult")
    quit_prob = min(0.95, quit_prob)
    quit_attempts = 1 if rng.random() < quit_prob else 0
    quit_early = quit_attempts > 0

    # --- Success probability ---
    if persona_name == "rigid_routine" and session_history is not None:
        recent = session_history[-3:] if len(session_history) >= 3 else session_history
        is_familiar = scenario_type in recent
        success_prob = (
            p.get("success_prob_familiar", 0.70) if is_familiar
            else p.get("success_prob_novel", 0.40)
        )
    else:
        success_prob = p["success_prob"]

    success_prob *= _get_mod(persona_name, scenario_type, "success_mult")
    # Fatigue reduces success probability slightly
    success_prob *= (1.0 - 0.05 * scenario_position)
    # Harder difficulty reduces success
    success_prob *= max(0.3, 1.0 - 0.07 * (difficulty - 1))
    success_prob = max(0.05, min(0.95, success_prob))

    # Force failure on quit (can't succeed if you quit early)
    success = (not quit_early) and (rng.random() < success_prob)

    # --- Hesitation / decision time ---
    hesitation_ms = p["hesitation_ms"] * _get_mod(persona_name, scenario_type, "hesitation_mult")
    hesitation_ms = max(500, round(rng.gauss(hesitation_ms, hesitation_ms * 0.25)))

    # --- Completion time ---
    expected_secs = _EXPECTED_COMPLETION_SECS.get(difficulty, 30.0)
    complexity_mult = {"low": 0.8, "medium": 1.0, "high": 1.3}.get(complexity, 1.0)
    if success:
        # Completed: somewhere around expected time
        completion_secs = rng.gauss(expected_secs * complexity_mult, expected_secs * 0.2)
    elif quit_early:
        # Quit: shorter than expected
        completion_secs = rng.gauss(expected_secs * 0.4, expected_secs * 0.1)
    else:
        # Failed without quitting: took longer (struggled through)
        completion_secs = rng.gauss(expected_secs * 1.6, expected_secs * 0.3)
    completion_time_ms = max(2000, round(completion_secs * 1000))

    return {
        "success": success,
        "completion_time_ms": completion_time_ms,
        "pause_count": pause_count,
        "retry_count": retry_count,
        "hesitation_pattern": hesitation_ms,
        "quit_attempts": quit_attempts,
        "action_counts": {},
        "decision_timestamps_ms": [],
    }
