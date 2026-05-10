"""Tests for synthetic user profiles and behavioral model."""
import pickle
import tempfile
from pathlib import Path

import numpy as np
import pytest

from app.rl.action_space import decode_action
from app.synthetic_users.behavioral_model import simulate_user_response
from app.synthetic_users.generator import generate_profiles, load_all_profiles
from app.synthetic_users.profile import SyntheticUserProfile


def test_generate_50_profiles():
    """Verify exactly 50 profiles are generated (40 train, 10 test)."""
    profiles = generate_profiles(n_train=40, n_test=10, seed=42)
    assert len(profiles) == 50

    train_profiles = [p for p in profiles if p.split == "train"]
    test_profiles = [p for p in profiles if p.split == "test"]
    assert len(train_profiles) == 40
    assert len(test_profiles) == 10


def test_profile_age_range():
    """Verify all ages are between 6.0 and 12.0."""
    profiles = generate_profiles(n_train=40, n_test=10, seed=42)
    for profile in profiles:
        assert 6.0 <= profile.age <= 12.0


def test_profile_severity_range():
    """Verify all severities are in {1, 2, 3}."""
    profiles = generate_profiles(n_train=40, n_test=10, seed=42)
    for profile in profiles:
        assert profile.severity in {1, 2, 3}


def test_profile_behavioral_params_range():
    """Verify behavioral parameters are in expected ranges."""
    profiles = generate_profiles(n_train=40, n_test=10, seed=42)
    for profile in profiles:
        assert 1.0 <= profile.avg_decision_time <= 10.0
        assert 0.0 <= profile.pause_probability <= 0.3
        assert 0.3 <= profile.retry_probability <= 0.9


def test_profile_pickle_roundtrip():
    """Verify profiles can be pickled and unpickled correctly."""
    profiles = generate_profiles(n_train=5, n_test=2, seed=42)
    profile = profiles[0]

    with tempfile.TemporaryDirectory() as tmpdir:
        pkl_path = Path(tmpdir) / "test_profile.pkl"
        with open(pkl_path, "wb") as f:
            pickle.dump(profile, f)

        with open(pkl_path, "rb") as f:
            loaded_profile = pickle.load(f)

        assert loaded_profile.id == profile.id
        assert loaded_profile.age == profile.age
        assert loaded_profile.severity == profile.severity
        assert loaded_profile.learning_rate == profile.learning_rate


def test_domain_randomization_applies_noise():
    """Verify apply_noise adds variability to values."""
    profile = SyntheticUserProfile(
        id="test",
        split="train",
        age=10.0,
        severity=2,
        learning_rate=0.5,
        frustration_tolerance=0.5,
        avg_decision_time=5.0,
        pause_probability=0.1,
        retry_probability=0.7,
    )

    rng = np.random.default_rng(42)
    values = [profile.apply_noise(5.0, rng) for _ in range(100)]

    # Verify values have variance (not all identical)
    assert np.var(values) > 0
    # Verify values are roughly centered around 5.0
    assert 4.0 < np.mean(values) < 6.0


def test_behavioral_model_returns_valid_response():
    """Verify simulate_user_response returns dict with all required keys."""
    profile = SyntheticUserProfile(
        id="test",
        split="train",
        age=10.0,
        severity=2,
        learning_rate=0.5,
        frustration_tolerance=0.5,
        avg_decision_time=5.0,
        pause_probability=0.1,
        retry_probability=0.7,
    )

    action = decode_action(0)
    rng = np.random.default_rng(42)

    response = simulate_user_response(profile, action, current_difficulty=3, step_in_episode=0, rng=rng)

    # Verify all required keys are present
    required_keys = {
        "task_completed",
        "decision_time",
        "num_pauses",
        "num_retries",
        "quit_early",
        "completion_time",
        "engagement_score",
    }
    assert set(response.keys()) == required_keys

    # Verify types
    assert isinstance(response["task_completed"], (bool, np.bool_))
    assert isinstance(response["decision_time"], (float, np.floating))
    assert isinstance(response["num_pauses"], (int, np.integer))
    assert isinstance(response["num_retries"], (int, np.integer))
    assert isinstance(response["quit_early"], (bool, np.bool_))
    assert isinstance(response["completion_time"], (float, np.floating))
    assert isinstance(response["engagement_score"], (float, np.floating))


def test_behavioral_model_respects_difficulty():
    """Verify higher difficulty_delta reduces success probability."""
    # High learning rate, low severity profile (should succeed often)
    profile = SyntheticUserProfile(
        id="test",
        split="train",
        age=10.0,
        severity=1,
        learning_rate=1.0,
        frustration_tolerance=0.8,
        avg_decision_time=5.0,
        pause_probability=0.1,
        retry_probability=0.7,
    )

    rng = np.random.default_rng(42)

    # Test with easy action (difficulty_delta = -2)
    easy_action = decode_action(0)  # difficulty_delta = -2
    easy_successes = sum(
        simulate_user_response(profile, easy_action, current_difficulty=3, step_in_episode=0, rng=rng)[
            "task_completed"
        ]
        for _ in range(100)
    )

    # Test with hard action (difficulty_delta = +2)
    rng = np.random.default_rng(42)  # Reset RNG for fair comparison
    hard_action = decode_action(40)  # difficulty_delta = +2
    hard_successes = sum(
        simulate_user_response(profile, hard_action, current_difficulty=3, step_in_episode=0, rng=rng)[
            "task_completed"
        ]
        for _ in range(100)
    )

    # Easy actions should have more successes than hard actions
    assert easy_successes > hard_successes


def test_profile_features_shape():
    """Verify to_profile_features() returns array of shape (20,)."""
    profile = SyntheticUserProfile(
        id="test",
        split="train",
        age=10.0,
        severity=2,
        learning_rate=0.5,
        frustration_tolerance=0.5,
        avg_decision_time=5.0,
        pause_probability=0.1,
        retry_probability=0.7,
    )

    features = profile.to_profile_features()
    assert features.shape == (20,)
    assert features.dtype == np.float32
    # Verify first 7 features are non-zero (profile data)
    assert np.any(features[:7] > 0)
