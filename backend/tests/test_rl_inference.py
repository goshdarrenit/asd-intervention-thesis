"""Tests for RL inference pipeline (pure Python tests, no httpx).

These tests verify the inference pipeline without requiring the FastAPI app.
They test model loading, prediction correctness, latency, determinism, and
config sharing between training and inference.
"""

import os

import numpy as np
import pytest

from app.rl.action_space import ACTION_SPACE_CONFIG
from app.rl.inference import RLPredictor, load_model, load_vec_normalize

# Skip all tests in this file if trained model doesn't exist
MODELS_EXIST = os.path.exists("model_store/ppo_asd_final.zip")
pytestmark = pytest.mark.skipif(not MODELS_EXIST, reason="Trained model not found")


@pytest.fixture(scope="module")
def predictor() -> RLPredictor:
    """Load model and create predictor once for all tests in module.

    Using module scope to avoid reloading the model for every test,
    which would be slow and unnecessary.

    Returns:
        RLPredictor instance with trained model.
    """
    model = load_model("model_store/ppo_asd_final")
    vec_normalize = load_vec_normalize("model_store/vec_normalize.pkl")
    return RLPredictor(model, vec_normalize)


def test_predictor_returns_valid_action(predictor: RLPredictor):
    """Test that predictor returns valid action index in range [0, 224]."""
    # Create random 60-dim observation
    obs = np.random.randn(60).astype(np.float32)

    # Predict
    result = predictor.predict(obs)

    # Verify action index is in valid range
    assert "action_index" in result
    assert isinstance(result["action_index"], int)
    assert 0 <= result["action_index"] <= 224, (
        f"Action index {result['action_index']} out of valid range [0, 224]"
    )


def test_predictor_latency_under_30ms(predictor: RLPredictor):
    """Test that all predictions complete in under 30ms.

    Runs 10 predictions with random observations to verify consistent
    performance. This is the key latency requirement for real-time inference.
    """
    latencies = []

    for _ in range(10):
        obs = np.random.randn(60).astype(np.float32)
        result = predictor.predict(obs)
        latencies.append(result["latency_ms"])

    # All predictions should be under 30ms
    for i, latency in enumerate(latencies):
        assert latency < 30, (
            f"Prediction {i+1} took {latency}ms, exceeding 30ms requirement"
        )

    # Print stats for monitoring
    avg_latency = np.mean(latencies)
    max_latency = np.max(latencies)
    print(f"\nLatency stats over 10 predictions:")
    print(f"  Average: {avg_latency:.2f}ms")
    print(f"  Maximum: {max_latency:.2f}ms")
    print(f"  All under 30ms: ✓")


def test_predictor_deterministic(predictor: RLPredictor):
    """Test that deterministic predictions return same action for same observation.

    When deterministic=True (the default), the policy should always return
    the mean action, not sample from the distribution. This ensures
    reproducibility for the same input.
    """
    # Create fixed observation
    obs = np.array([0.5] * 60, dtype=np.float32)

    # Predict twice with same observation
    result1 = predictor.predict(obs, deterministic=True)
    result2 = predictor.predict(obs, deterministic=True)

    # Should get same action both times
    assert result1["action_index"] == result2["action_index"], (
        f"Deterministic predictions differ: {result1['action_index']} vs {result2['action_index']}"
    )


def test_predictor_decoded_action_matches_config(predictor: RLPredictor):
    """Test that decoded action has all expected keys from ACTION_SPACE_CONFIG.

    Verifies that the decode_action function properly extracts all components
    of the action space: type, difficulty, reinforcement, and complexity.
    """
    obs = np.random.randn(60).astype(np.float32)
    result = predictor.predict(obs)

    # Check decoded_action has all required keys
    decoded = result["decoded_action"]
    assert "action_type" in decoded
    assert "difficulty_delta" in decoded
    assert "reinforcement_mode" in decoded
    assert "complexity_level" in decoded

    # Verify types
    assert isinstance(decoded["action_type"], str)
    assert isinstance(decoded["difficulty_delta"], int)
    assert isinstance(decoded["reinforcement_mode"], str)
    assert isinstance(decoded["complexity_level"], str)


def test_predictor_uses_shared_action_space(predictor: RLPredictor):
    """Test that decoded action_type is from shared ACTION_SPACE_CONFIG.

    This verifies that training and inference use the same action space
    configuration, which is critical for consistency. The action_type should
    be one of the 5 core scenario types defined in ACTION_SPACE_CONFIG.
    """
    obs = np.random.randn(60).astype(np.float32)
    result = predictor.predict(obs)

    decoded = result["decoded_action"]

    # Verify action_type is from config
    valid_action_types = ACTION_SPACE_CONFIG["action_types"]
    assert decoded["action_type"] in valid_action_types, (
        f"Action type '{decoded['action_type']}' not in valid types: {valid_action_types}"
    )

    # Verify difficulty_delta is from config
    valid_difficulty_deltas = ACTION_SPACE_CONFIG["difficulty_deltas"]
    assert decoded["difficulty_delta"] in valid_difficulty_deltas, (
        f"Difficulty delta {decoded['difficulty_delta']} not in valid deltas: {valid_difficulty_deltas}"
    )

    # Verify reinforcement_mode is from config
    valid_reinforcement_modes = ACTION_SPACE_CONFIG["reinforcement_modes"]
    assert decoded["reinforcement_mode"] in valid_reinforcement_modes, (
        f"Reinforcement mode '{decoded['reinforcement_mode']}' not in valid modes: {valid_reinforcement_modes}"
    )

    # Verify complexity_level is from config
    valid_complexity_levels = ACTION_SPACE_CONFIG["complexity_levels"]
    assert decoded["complexity_level"] in valid_complexity_levels, (
        f"Complexity level '{decoded['complexity_level']}' not in valid levels: {valid_complexity_levels}"
    )
