"""Tests for action space configuration and encoding/decoding."""
import pytest

from app.rl.action_space import ACTION_SPACE_CONFIG, decode_action, encode_action


def test_action_space_has_225_actions():
    """Verify action space has exactly 225 discrete actions."""
    assert ACTION_SPACE_CONFIG["n_actions"] == 225


def test_decode_action_valid_range():
    """Verify decode_action works for boundary values."""
    # Decode first action
    action_0 = decode_action(0)
    assert action_0["action_type"] == "sharing"
    assert action_0["difficulty_delta"] == -2
    assert action_0["reinforcement_mode"] == "positive"
    assert action_0["complexity_level"] == "low"

    # Decode last action
    action_224 = decode_action(224)
    assert action_224["action_type"] == "conflict_resolution"
    assert action_224["difficulty_delta"] == 2
    assert action_224["reinforcement_mode"] == "corrective"
    assert action_224["complexity_level"] == "high"


def test_encode_decode_bijective():
    """Verify encode/decode is bijective for all 225 actions."""
    for i in range(225):
        d = decode_action(i)
        at = ACTION_SPACE_CONFIG["action_types"].index(d["action_type"])
        dd = ACTION_SPACE_CONFIG["difficulty_deltas"].index(d["difficulty_delta"])
        rm = ACTION_SPACE_CONFIG["reinforcement_modes"].index(d["reinforcement_mode"])
        cl = ACTION_SPACE_CONFIG["complexity_levels"].index(d["complexity_level"])
        assert encode_action(at, dd, rm, cl) == i, f"Bijectivity failed at index {i}"


def test_decode_returns_correct_types():
    """Verify decoded action has correct types."""
    action = decode_action(100)
    assert isinstance(action["action_type"], str)
    assert isinstance(action["difficulty_delta"], int)
    assert isinstance(action["reinforcement_mode"], str)
    assert isinstance(action["complexity_level"], str)


def test_invalid_action_index_raises():
    """Verify invalid action indices raise AssertionError."""
    with pytest.raises(AssertionError):
        decode_action(225)

    with pytest.raises(AssertionError):
        decode_action(-1)
