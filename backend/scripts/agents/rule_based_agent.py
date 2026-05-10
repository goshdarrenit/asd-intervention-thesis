"""Rule-based adaptive agent baseline for the agent comparison study.

Implements a heuristic that adjusts difficulty based on the child's rolling
success rate observed from the state vector — the strongest non-RL baseline
("couldn't you just use a simple rule?").

Decision logic:
  - rolling_success >= 0.8  -> increase difficulty (+1 delta)
  - rolling_success <  0.4  -> decrease difficulty (-1 delta)
  - otherwise               -> hold difficulty ( 0 delta)

Scenario type cycles 0-4 in fixed order (no personalisation).
Always uses positive reinforcement and medium complexity.

Observation indices (from state_builder.py layout):
  Dims  0-19: profile features
  Dims 20-34: context features
    [20] = (difficulty - 1) / 4.0
  Dims 35-44: performance features
    [40] = rolling success rate  (35 + 5)
  Dims 45-54: emotion features
  Dims 55-59: game theory features
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

import numpy as np

from app.rl.action_space import encode_action


# Observation vector indices
_OBS_ROLLING_SUCCESS = 40   # performance feature: rolling success rate
_OBS_DIFFICULTY_NORM = 20   # context feature: (difficulty-1)/4


class RuleBasedAdaptiveAgent:
    """Heuristic adaptive agent that uses rolling success rate to adjust difficulty.

    Acts as the key comparison baseline: it adapts difficulty intelligently but
    has no personalisation, no emotional awareness, and no scenario selection
    logic beyond a fixed cycle.
    """

    # Difficulty delta index mapping
    _DELTA_DOWN = 1   # difficulty_delta = -1
    _DELTA_HOLD = 2   # difficulty_delta =  0
    _DELTA_UP   = 3   # difficulty_delta = +1

    # Fixed reinforcement and complexity choices
    _REINFORCEMENT_POSITIVE = 0
    _COMPLEXITY_MEDIUM      = 1

    # Thresholds
    _THRESHOLD_UP   = 0.8
    _THRESHOLD_DOWN = 0.4

    def __init__(self) -> None:
        self._scenario_step: int = 0

    def reset(self) -> None:
        """Reset scenario cycle counter between users/episodes."""
        self._scenario_step = 0

    def predict(self, obs: np.ndarray) -> int:
        """Select next action based on rolling success rate heuristic.

        Args:
            obs: 60-dimensional observation vector.

        Returns:
            Flat action index in [0, 224].
        """
        rolling_success = float(obs[_OBS_ROLLING_SUCCESS])

        if rolling_success >= self._THRESHOLD_UP:
            difficulty_delta_idx = self._DELTA_UP
        elif rolling_success < self._THRESHOLD_DOWN:
            difficulty_delta_idx = self._DELTA_DOWN
        else:
            difficulty_delta_idx = self._DELTA_HOLD

        scenario_type_idx = self._scenario_step % 5
        self._scenario_step += 1

        return int(encode_action(
            scenario_type_idx,
            difficulty_delta_idx,
            self._REINFORCEMENT_POSITIVE,
            self._COMPLEXITY_MEDIUM,
        ))
