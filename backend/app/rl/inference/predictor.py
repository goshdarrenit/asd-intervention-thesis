"""RLPredictor class for serving model predictions with latency tracking."""

import time
from typing import Any

import numpy as np
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import VecNormalize

from app.rl.action_space import decode_action


class RLPredictor:
    """Inference wrapper for trained PPO model with observation normalization.

    Handles:
    - Observation normalization using training statistics (VecNormalize)
    - Action prediction with trained PPO model
    - Action decoding to structured components (shared config)
    - Latency tracking for performance monitoring (<30ms target)

    Example:
        >>> predictor = RLPredictor(model, vec_normalize)
        >>> obs = np.random.randn(60).astype(np.float32)
        >>> result = predictor.predict(obs)
        >>> print(result)
        {
            'action_index': 42,
            'decoded_action': {
                'action_type': 'sharing',
                'difficulty_delta': 0,
                'reinforcement_mode': 'positive',
                'complexity_level': 'medium'
            },
            'latency_ms': 12.34
        }
    """

    def __init__(self, model: PPO, vec_normalize: VecNormalize):
        """Initialize predictor with trained model and normalization stats.

        Args:
            model: Trained PPO model loaded from model_store.
            vec_normalize: VecNormalize wrapper with training statistics.
        """
        self.model = model
        self.vec_normalize = vec_normalize

    def predict(
        self, observation: np.ndarray, deterministic: bool = True
    ) -> dict[str, Any]:
        """Predict action from raw 60-dim observation vector.

        This is the main inference method. It:
        1. Normalizes the observation using training statistics
        2. Runs the PPO model to get action prediction
        3. Decodes the action using shared action space config (shared config)
        4. Tracks prediction latency

        Args:
            observation: Raw 60-dimensional state vector (NOT pre-normalized).
                        Should be numpy array or list of 60 floats.
            deterministic: If True, use mean action (deterministic policy).
                          If False, sample from policy distribution.
                          Default: True (recommended for inference).

        Returns:
            Dictionary with keys:
            - action_index: int (0-224) - Flat action index
            - decoded_action: dict - Structured action components:
                - action_type: str - Scenario type
                - difficulty_delta: int - Difficulty adjustment
                - reinforcement_mode: str - Reinforcement strategy
                - complexity_level: str - Complexity level
            - latency_ms: float - Prediction time in milliseconds

        Example:
            >>> obs = np.array([...])  # 60-dim state vector
            >>> result = predictor.predict(obs)
            >>> assert result['latency_ms'] < 30
        """
        # Start timing
        start = time.perf_counter()

        # Convert to numpy array and reshape for batch processing
        obs = np.array(observation, dtype=np.float32).reshape(1, -1)

        # Normalize using training statistics (critical for correct predictions)
        normalized_obs = self.vec_normalize.normalize_obs(obs)

        # Get action from policy
        action, _states = self.model.predict(normalized_obs, deterministic=deterministic)

        # Extract action index (handle both scalar and array returns)
        action_idx = int(action[0]) if hasattr(action, "__len__") else int(action)

        # Calculate elapsed time in milliseconds
        elapsed_ms = (time.perf_counter() - start) * 1000

        # Decode action using shared config (training and inference use same decode)
        decoded = decode_action(action_idx)

        return {
            "action_index": action_idx,
            "decoded_action": decoded,
            "latency_ms": round(elapsed_ms, 2),
        }
