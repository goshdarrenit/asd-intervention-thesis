"""Synthetic user profile dataclass.

"""
from dataclasses import dataclass

import numpy as np


@dataclass
class SyntheticUserProfile:
    """Synthetic user profile with diverse characteristics for RL training.

    Attributes:
        id: Unique identifier (e.g., "user_000")
        split: Dataset split ("train" or "test")
        age: Child's age in years (6.0 to 12.0)
        severity: ASD severity level (1=mild, 2=moderate, 3=severe)
        learning_rate: How quickly user improves (0.1 to 1.0)
        frustration_tolerance: Patience with difficult tasks (0.1 to 1.0)
        avg_decision_time: Average time to make decisions (1.0 to 10.0 seconds)
        pause_probability: Probability of pausing during task (0.0 to 0.3)
        retry_probability: Probability of retrying failed tasks (0.3 to 0.9)
        noise_std: Standard deviation for domain randomization (default 0.1 = ±10%)
    """

    # Identifiers
    id: str  # "user_000" to "user_049"
    split: str  # "train" or "test"

    # Core characteristics
    age: float  # 6.0 to 12.0
    severity: int  # 1, 2, or 3
    learning_rate: float  # 0.1 to 1.0
    frustration_tolerance: float  # 0.1 to 1.0

    # Behavioral parameters
    avg_decision_time: float  # 1.0 to 10.0 seconds
    pause_probability: float  # 0.0 to 0.3
    retry_probability: float  # 0.3 to 0.9

    # Domain randomization
    noise_std: float = 0.1  # ±10% noise

    def apply_noise(self, value: float, rng: np.random.Generator) -> float:
        """Apply ±10% domain randomization noise.

        Args:
            value: Base value to add noise to
            rng: Numpy random generator (passed externally to avoid pickle issues)

        Returns:
            Value with Gaussian noise added
        """
        noise = rng.normal(0, self.noise_std * abs(value))
        return value + noise

    def to_profile_features(self) -> np.ndarray:
        """Convert profile to normalized feature array for state vector.

        Returns first 20 dimensions of the 60-dim state vector.
        Remaining dimensions are for session-specific data (task history, emotional state).

        Returns:
            Array of shape (20,) with normalized features in [0, 1] range
        """
        features = np.zeros(20, dtype=np.float32)
        features[0] = (self.age - 6.0) / 6.0  # age normalized to [0, 1]
        features[1] = (self.severity - 1) / 2.0  # severity normalized to [0, 1]
        features[2] = self.learning_rate  # already [0.1, 1.0]
        features[3] = self.frustration_tolerance  # already [0.1, 1.0]
        features[4] = self.avg_decision_time / 10.0  # normalized to [0.1, 1.0]
        features[5] = self.pause_probability / 0.3  # normalized to [0, 1]
        features[6] = self.retry_probability  # already [0.3, 0.9]
        # Remaining 13 dims reserved for additional profile features (initialized to 0)
        return features
