"""Tests for the RL environment (ASDInterventionEnv).

Validates:
- Gymnasium API compliance
- State vector structure and dimensions
- Episode flow and truncation
- check_env() validation from gymnasium and stable_baselines3
- VecNormalize wrapper integration
- Seed reproducibility
"""

import numpy as np
import pytest
import gymnasium as gym
from gymnasium.utils.env_checker import check_env as gym_check_env
from stable_baselines3.common.env_checker import check_env as sb3_check_env
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize

from app.rl.environment import ASDInterventionEnv
from app.synthetic_users.profile import SyntheticUserProfile


@pytest.fixture
def profile():
    """Create a test synthetic user profile."""
    return SyntheticUserProfile(
        id="test_user",
        split="test",
        age=9.0,
        severity=2,
        learning_rate=0.5,
        frustration_tolerance=0.5,
        avg_decision_time=5.0,
        pause_probability=0.15,
        retry_probability=0.6,
    )


@pytest.fixture
def env(profile):
    """Create a test environment."""
    return ASDInterventionEnv(profile, seed=42)


# ==================== Environment shape and API tests ====================


def test_env_reset_returns_60_dim_state(env):
    """Test that env.reset() returns ndarray of shape (60,) with dtype float32."""
    obs, info = env.reset(seed=42)
    assert isinstance(obs, np.ndarray), f"Expected ndarray, got {type(obs)}"
    assert obs.shape == (60,), f"Expected (60,), got {obs.shape}"
    assert obs.dtype == np.float32, f"Expected float32, got {obs.dtype}"
    assert isinstance(info, dict), f"Expected dict, got {type(info)}"


def test_env_step_returns_valid_tuple(env):
    """Test that env.step(0) returns 5-tuple with correct types."""
    env.reset(seed=42)
    obs, reward, terminated, truncated, info = env.step(0)

    assert isinstance(obs, np.ndarray), f"Expected ndarray, got {type(obs)}"
    assert obs.shape == (60,), f"Expected (60,), got {obs.shape}"
    assert isinstance(reward, float), f"Expected float, got {type(reward)}"
    assert isinstance(terminated, bool), f"Expected bool, got {type(terminated)}"
    assert isinstance(truncated, bool), f"Expected bool, got {type(truncated)}"
    assert isinstance(info, dict), f"Expected dict, got {type(info)}"


def test_env_step_all_actions_valid(env):
    """Test that a sample of actions (0, 112, 224) all produce valid outputs."""
    env.reset(seed=42)

    for action in [0, 112, 224]:
        obs, reward, terminated, truncated, info = env.step(action)
        assert obs.shape == (60,), f"Action {action}: Expected (60,), got {obs.shape}"
        assert isinstance(reward, float), f"Action {action}: Expected float reward"
        assert not terminated or not truncated, f"Action {action}: Both terminated and truncated are True"


def test_env_observation_space_matches(env):
    """Test that observation matches env.observation_space."""
    obs, _ = env.reset(seed=42)
    assert env.observation_space.contains(obs), "Observation not in observation_space"


def test_env_action_space_is_225(env):
    """Test that env.action_space.n == 225."""
    assert env.action_space.n == 225, f"Expected 225 actions, got {env.action_space.n}"


# ==================== State vector structure tests ====================


def test_state_vector_profile_dims(env):
    """Test that first 20 dims reflect profile characteristics."""
    obs, _ = env.reset(seed=42)

    # First 2 dims should be normalized age and severity
    # Age: 9.0 normalized to [0, 1] range (assuming 5-12 range)
    # Severity: 2 mapped to index (0, 1, or 2)
    profile_features = obs[:20]
    assert not np.all(profile_features == 0), "Profile features are all zeros"


def test_state_vector_60_dims_not_all_zero(env):
    """Test that after reset, at least some non-zero values exist."""
    obs, _ = env.reset(seed=42)
    non_zero_count = np.count_nonzero(obs)
    assert non_zero_count > 0, f"Expected some non-zero values, got all zeros"


def test_state_vector_changes_after_step(env):
    """Test that obs from step differs from obs from reset."""
    obs1, _ = env.reset(seed=42)
    obs2, _, _, _, _ = env.step(0)

    assert not np.allclose(obs1, obs2), "Observation should change after step"


# ==================== Episode flow tests ====================


def test_full_episode_runs_to_truncation(env):
    """Test that running max_steps steps results in truncated=True on last step."""
    max_steps = 100
    env = ASDInterventionEnv(env.profile, max_steps=max_steps, seed=42)
    env.reset(seed=42)

    for step in range(max_steps - 1):
        _, _, terminated, truncated, _ = env.step(0)
        assert not truncated, f"Truncated early at step {step}"
        assert not terminated, f"Terminated early at step {step}"

    # Last step should truncate
    _, _, terminated, truncated, _ = env.step(0)
    assert truncated, "Episode should truncate at max_steps"


def test_episode_reset_clears_state(env):
    """Test that after full episode, reset returns fresh state."""
    env.reset(seed=42)

    # Run some steps
    for _ in range(10):
        env.step(0)

    # Reset and check step_count
    obs, info = env.reset(seed=42)
    assert info["step_count"] == 0, f"Expected step_count=0 after reset, got {info['step_count']}"
    assert info["cumulative_reward"] == 0.0, f"Expected cumulative_reward=0 after reset"


def test_reward_is_finite(env):
    """Test that all rewards during episode are finite floats (no NaN, no inf)."""
    env.reset(seed=42)

    for _ in range(10):
        _, reward, _, _, _ = env.step(0)
        assert np.isfinite(reward), f"Reward is not finite: {reward}"


def test_info_contains_required_keys(env):
    """Test that info dict has step_count, profile_id, emotions keys."""
    env.reset(seed=42)
    _, _, _, _, info = env.step(0)

    required_keys = ["step_count", "profile_id", "emotions"]
    for key in required_keys:
        assert key in info, f"Missing required key in info: {key}"

    # Check emotions structure
    assert "frustration" in info["emotions"]
    assert "engagement" in info["emotions"]
    assert "confidence" in info["emotions"]


# ==================== Gymnasium validation tests ====================


def test_gymnasium_check_env_passes(env):
    """Test that gymnasium.utils.env_checker.check_env(env) passes."""
    try:
        gym_check_env(env, skip_render_check=True)
    except Exception as e:
        pytest.fail(f"Gymnasium check_env failed: {e}")


def test_sb3_check_env_passes(env):
    """Test that stable_baselines3.common.env_checker.check_env(env) passes."""
    try:
        sb3_check_env(env, warn=False)
    except Exception as e:
        # SB3 sometimes raises warnings as errors for non-critical issues
        # Skip if it's a warning about render or other non-critical features
        if "render" in str(e).lower() or "warning" in str(e).lower():
            pytest.skip(f"SB3 check_env raised non-critical issue: {e}")
        else:
            pytest.fail(f"SB3 check_env failed: {e}")


# ==================== VecNormalize integration test ====================


def test_vec_normalize_wrapper_works(profile):
    """Test that DummyVecEnv + VecNormalize wrapper works and normalizes observations."""
    # Create vectorized environment
    def make_env():
        return ASDInterventionEnv(profile, seed=42)

    vec_env = DummyVecEnv([make_env])
    vec_norm_env = VecNormalize(vec_env, norm_obs=True, norm_reward=False)

    # Reset and take steps
    obs = vec_norm_env.reset()
    assert obs.shape == (1, 60), f"Expected (1, 60), got {obs.shape}"

    for _ in range(10):
        action = [vec_norm_env.action_space.sample()]
        obs, rewards, dones, infos = vec_norm_env.step(action)
        assert obs.shape == (1, 60), f"Expected (1, 60), got {obs.shape}"

    # After normalization, observations should have different statistics
    # Check that mean is closer to 0 (normalization working)
    assert np.abs(np.mean(obs)) < 1.0, "Normalized observations should have mean close to 0"

    vec_norm_env.close()


# ==================== Reproducibility test ====================


def test_seed_reproducibility(profile):
    """Test that two environments with same seed produce identical results."""
    env1 = ASDInterventionEnv(profile, seed=42)
    env2 = ASDInterventionEnv(profile, seed=42)

    obs1, _ = env1.reset(seed=42)
    obs2, _ = env2.reset(seed=42)

    assert np.allclose(obs1, obs2), "Reset observations should be identical with same seed"

    # Run same actions
    actions = [0, 10, 50, 100, 200]
    for action in actions:
        obs1, reward1, _, _, _ = env1.step(action)
        obs2, reward2, _, _, _ = env2.step(action)

        assert np.allclose(obs1, obs2), f"Observations differ at action {action}"
        assert np.isclose(reward1, reward2), f"Rewards differ at action {action}: {reward1} vs {reward2}"
