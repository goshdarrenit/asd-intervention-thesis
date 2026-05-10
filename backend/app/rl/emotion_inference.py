"""Emotion inference from behavioral telemetry.

Maps observable behavioral signals to emotional state proxies:
Increases with pauses, retries, quitting
Inversely related to completion time
Fast decisive actions without hesitation
"""
from dataclasses import dataclass


@dataclass
class BehavioralTelemetry:
    """Observable behavioral signals during task."""
    decision_time: float  # Seconds taken for decision
    num_pauses: int  # Number of pauses during task
    num_retries: int  # Number of retry attempts
    quit_early: bool  # Whether user quit before completion
    completion_time: float  # Total time to complete (or time until quit)

    # Baseline values for normalization
    expected_decision_time: float = 10.0  # Raised from 5.0 — ASD children naturally take longer to decide
    expected_completion_time: float = 30.0


@dataclass
class EmotionalState:
    """Inferred emotional proxies (0-1 normalized)."""
    frustration: float  # 0 = calm, 1 = highly frustrated
    engagement: float  # 0 = disengaged, 1 = highly engaged
    confidence: float  # 0 = uncertain, 1 = confident


def _clamp(value: float, min_val: float = 0.0, max_val: float = 1.0) -> float:
    """Clamp value to [min_val, max_val] range."""
    return max(min_val, min(max_val, value))


def infer_emotion(telemetry: BehavioralTelemetry) -> EmotionalState:
    """
    Infer emotional state from behavioral signals.

    Returns:
        EmotionalState with frustration, engagement, confidence in [0, 1]
    """
    # Frustration formula: Increases with pauses, retries, quitting early
    # Weight: 30% pauses, 30% retries, 40% quit
    frustration = _clamp(
        0.3 * min(1.0, telemetry.num_pauses / 3.0) +
        0.3 * min(1.0, telemetry.num_retries / 3.0) +
        0.4 * (1.0 if telemetry.quit_early else 0.0)
    )

    # Engagement formula: Inversely related to completion time ratio
    time_ratio = telemetry.completion_time / telemetry.expected_completion_time
    if time_ratio < 0.3:  # Too fast = guessing
        engagement = 0.3
    elif time_ratio <= 1.5:  # Normal range = high engagement
        engagement = 1.0
    else:  # Slow = declining engagement
        engagement = max(0.3, 1.5 / time_ratio)

    # Confidence formula: Fast decisive actions with few pauses and retries.
    # Weighted additive combination — avoids the subtractive formula going negative.
    # Denominators reflect realistic ASD behavioural ranges.
    decision_speed = 1.0 - min(1.0, telemetry.decision_time / (2 * telemetry.expected_decision_time))
    pause_score = 1.0 - min(1.0, telemetry.num_pauses / 10.0)
    retry_score = 1.0 - min(1.0, telemetry.num_retries / 8.0)
    quit_penalty = 0.3 if telemetry.quit_early else 0.0
    confidence = _clamp(0.4 * decision_speed + 0.3 * pause_score + 0.3 * retry_score - quit_penalty)

    return EmotionalState(
        frustration=float(frustration),
        engagement=float(engagement),
        confidence=float(confidence)
    )


def infer_confusion(telemetry: BehavioralTelemetry) -> float:
    """
    Infer confusion score from behavioral signals.

    Confusion is derived from
    hesitation (decision_time vs expected) and retries. This is a focused
    view of what frustration already captures, but specific to confusion.

    All inference is from behavioral signals only,
    no camera or facial recognition is used.

    Args:
        telemetry: Behavioral telemetry data

    Returns:
        Confusion score in range [0, 1], where 0 = clear understanding,
        1 = highly confused

    Formula:
        0.5 * min(1.0, num_retries / 3.0) +
        0.5 * min(1.0, max(0, decision_time - expected) / expected)
    """
    retry_component = min(1.0, telemetry.num_retries / 3.0)

    decision_delay = max(0, telemetry.decision_time - telemetry.expected_decision_time)
    delay_ratio = decision_delay / telemetry.expected_decision_time
    delay_component = min(1.0, delay_ratio)

    confusion = 0.5 * retry_component + 0.5 * delay_component

    return float(_clamp(confusion))


def infer_disengagement(telemetry: BehavioralTelemetry) -> float:
    """
    Infer disengagement score from behavioral signals.

    Disengagement is derived
    from inactivity (long completion time) and quit patterns.

    All inference is from behavioral signals only,
    no camera or facial recognition is used.

    Args:
        telemetry: Behavioral telemetry data

    Returns:
        Disengagement score in range [0, 1], where 0 = highly engaged,
        1 = disengaged

    Formula:
        0.6 * float(quit_early) +
        0.4 * min(1.0, max(0, completion_time - 1.5*expected) / (1.5*expected))
    """
    quit_component = 0.6 * float(telemetry.quit_early)

    # Inactivity: taking more than 150% of expected time
    threshold = telemetry.expected_completion_time * 1.5
    inactivity_delay = max(0, telemetry.completion_time - threshold)
    inactivity_ratio = inactivity_delay / threshold
    inactivity_component = 0.4 * min(1.0, inactivity_ratio)

    disengagement = quit_component + inactivity_component

    return float(_clamp(disengagement))
