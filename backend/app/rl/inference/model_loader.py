"""Model and VecNormalize loading functions for inference."""

import os
import pickle
from pathlib import Path
from typing import Optional

import numpy as np
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize

from app.rl.environment import ASDInterventionEnv
from app.synthetic_users.profile import SyntheticUserProfile


def load_model(model_path: str = "model_store/ppo_asd_final") -> PPO:
    """Load trained PPO model from model_store.

    Args:
        model_path: Path to saved model (without .zip extension).
                   Default: "model_store/ppo_asd_final"

    Returns:
        Loaded PPO model ready for inference.

    Raises:
        FileNotFoundError: If model file doesn't exist at specified path.

    Example:
        >>> model = load_model("model_store/ppo_asd_final")
        >>> # Model ready for prediction
    """
    zip_path = f"{model_path}.zip"

    if not os.path.exists(zip_path):
        raise FileNotFoundError(
            f"Model file not found at {zip_path}. "
            "Please ensure the model has been trained and saved."
        )

    # Load model
    model = PPO.load(model_path)
    return model


def load_vec_normalize(
    stats_path: str = "model_store/vec_normalize.pkl",
    env: Optional[DummyVecEnv] = None,
) -> VecNormalize:
    """Load VecNormalize statistics for observation normalization.

    Args:
        stats_path: Path to saved VecNormalize pickle file.
                   Default: "model_store/vec_normalize.pkl"
        env: Optional DummyVecEnv to wrap. If None, creates a minimal
             dummy environment just for VecNormalize shape compatibility.

    Returns:
        VecNormalize wrapper configured for inference (training=False, norm_reward=False).

    Raises:
        FileNotFoundError: If stats file doesn't exist at specified path.

    Example:
        >>> vec_norm = load_vec_normalize("model_store/vec_normalize.pkl")
        >>> normalized_obs = vec_norm.normalize_obs(raw_obs)
    """
    if not os.path.exists(stats_path):
        raise FileNotFoundError(
            f"VecNormalize stats file not found at {stats_path}. "
            "Please ensure the model has been trained and statistics saved."
        )

    # Create minimal dummy environment if not provided
    if env is None:
        # Load a single synthetic user profile for env shape
        train_dir = Path("data/synthetic_users/train")
        if train_dir.exists():
            # Use first available profile
            profile_files = sorted(train_dir.glob("user_*.pkl"))
            if profile_files:
                with open(profile_files[0], "rb") as f:
                    profile = pickle.load(f)
            else:
                # Fallback: create minimal profile for shape only
                profile = _create_minimal_profile()
        else:
            # Fallback: create minimal profile for shape only
            profile = _create_minimal_profile()

        # Create dummy env (only needed for VecNormalize shape)
        def make_env():
            # Don't pass rng - environment will create its own
            return ASDInterventionEnv(profile=profile, seed=42)

        env = DummyVecEnv([make_env])

    # Load VecNormalize with saved statistics
    vec_normalize = VecNormalize.load(stats_path, env)

    # Critical: set to inference mode
    vec_normalize.training = False
    vec_normalize.norm_reward = False

    return vec_normalize


def _create_minimal_profile() -> SyntheticUserProfile:
    """Create minimal synthetic user profile for VecNormalize shape compatibility.

    This is only used if no training profiles are available. The profile
    just needs to have the right fields for environment initialization.

    Returns:
        Minimal SyntheticUserProfile with required fields.
    """
    # Create a minimal profile with default values
    profile = SyntheticUserProfile(
        user_id="dummy_000",
        age=8,
        asd_severity=0.5,
        attention_span=0.5,
        frustration_tolerance=0.5,
        social_responsiveness=0.5,
    )
    return profile
