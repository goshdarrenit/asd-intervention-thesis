"""RL training pipeline for PPO agent training.

Provides hyperparameter configuration, training loop with parallel environments,
VecNormalize, checkpointing, and evaluation callbacks.
"""

from app.rl.training.hyperparameters import get_ppo_config, N_ENVS
from app.rl.training.train_ppo import train_ppo

__all__ = [
    "get_ppo_config",
    "N_ENVS",
    "train_ppo",
]
