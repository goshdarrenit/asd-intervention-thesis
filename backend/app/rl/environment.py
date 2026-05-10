"""
Custom Gymnasium environment for ASD intervention training.

This environment integrates:
- Synthetic user profiles with behavioral models
- Emotion inference from behavioral signals
- Reward calculation based on task success and emotional state
- 60-dimensional state space (profile + context + performance + emotion + game theory)
- 225-dimensional discrete action space (scenario × difficulty × reinforcement × complexity)
"""

import numpy as np
import gymnasium as gym
from gymnasium import spaces

from app.synthetic_users.profile import SyntheticUserProfile
from app.synthetic_users.behavioral_model import simulate_user_response
from app.rl.emotion_inference import infer_emotion, BehavioralTelemetry
from app.rl.reward_calculator import calculate_reward
from app.rl.action_space import decode_action, ACTION_SPACE_CONFIG
from app.rl.state_builder import (
    build_state_vector,
    build_context_features,
    build_performance_features,
    build_emotion_features,
    build_game_theory_features,
)


class ASDInterventionEnv(gym.Env):
    """
    Gymnasium environment for training RL agents to select optimal scenarios.

    The agent selects actions (scenario + difficulty + reinforcement + complexity)
    and receives observations (60-dim state vector) and rewards based on synthetic
    user responses and emotional states.
    """

    metadata = {"render_modes": ["human"], "render_fps": 4}

    def __init__(
        self,
        profile: SyntheticUserProfile,
        render_mode: str = None,
        max_steps: int = 100,
        seed: int = None,
    ):
        """
        Initialize the environment with a synthetic user profile.

        Args:
            profile: The synthetic user profile to simulate
            render_mode: Rendering mode (only "human" supported)
            max_steps: Maximum steps per episode before truncation
            seed: Random seed for reproducibility
        """
        super().__init__()
        self.profile = profile
        self.render_mode = render_mode
        self._max_steps = max_steps

        # Define action and observation spaces
        self.action_space = spaces.Discrete(ACTION_SPACE_CONFIG["n_actions"])
        self.observation_space = spaces.Box(
            low=-np.inf,
            high=np.inf,
            shape=(60,),
            dtype=np.float32,
        )

        # Internal RNG for reproducibility
        self._rng = np.random.default_rng(seed)

        # Episode state (initialized in reset())
        self._step_count = 0
        self._current_difficulty = 3
        self._current_scenario_idx = 0
        self._last_action_type_idx = 0
        self._session_time = 0.0
        self._last_5_success = []
        self._total_scenarios_completed = 0
        self._rolling_success_rate = 0.0
        self._avg_completion_time = 10.0
        self._current_streak = 0
        self._improvement_trend = 0.0

        # Emotion state
        self._frustration = 0.3
        self._engagement = 0.7
        self._confidence = 0.5
        self._prev_frustration = 0.3
        self._prev_engagement = 0.7
        self._prev_confidence = 0.5

        # Game theory features (initialized to neutral)
        self._cooperation = 0.5
        self._risk = 0.5
        self._fairness = 0.5
        self._trust = 0.5
        self._reciprocity = 0.5

        # Cumulative reward tracking
        self._total_reward = 0.0

    def reset(self, seed: int = None, options: dict = None):
        """
        Reset the environment to initial state.

        Args:
            seed: Random seed for reproducibility
            options: Additional options (unused)

        Returns:
            (observation, info) tuple per Gymnasium API
        """
        # Reset RNG if seed provided
        super().reset(seed=seed)
        if seed is not None:
            self._rng = np.random.default_rng(seed)

        # Reset episode state
        self._step_count = 0
        self._current_difficulty = 3  # Start mid-range
        self._current_scenario_idx = 0
        self._last_action_type_idx = 0
        self._session_time = 0.0
        self._last_5_success = []
        self._total_scenarios_completed = 0
        self._rolling_success_rate = 0.0
        self._avg_completion_time = 10.0
        self._current_streak = 0
        self._improvement_trend = 0.0

        # Reset emotions to neutral
        self._frustration = 0.3
        self._engagement = 0.7
        self._confidence = 0.5
        self._prev_frustration = 0.3
        self._prev_engagement = 0.7
        self._prev_confidence = 0.5

        # Reset game theory features
        self._cooperation = 0.5
        self._risk = 0.5
        self._fairness = 0.5
        self._trust = 0.5
        self._reciprocity = 0.5

        # Reset cumulative reward
        self._total_reward = 0.0

        # Build initial observation
        observation = self._get_obs()

        info = {
            "step_count": self._step_count,
            "profile_id": self.profile.id,
            "cumulative_reward": self._total_reward,
        }

        return observation, info

    def step(self, action: int):
        """
        Execute one step in the environment.

        Args:
            action: Integer action in [0, 224]

        Returns:
            (observation, reward, terminated, truncated, info) tuple
        """
        # Decode action
        decoded = decode_action(action)

        # Update difficulty based on action
        new_difficulty = self._current_difficulty + decoded["difficulty_delta"]
        self._current_difficulty = int(np.clip(new_difficulty, 1, 5))

        # Update scenario type index (map from action type string to index)
        action_types = ACTION_SPACE_CONFIG["action_types"]
        self._current_scenario_idx = action_types.index(decoded["action_type"])

        # Update last action type index
        self._last_action_type_idx = self._current_scenario_idx

        # Simulate user response
        response = simulate_user_response(
            profile=self.profile,
            action=decoded,
            current_difficulty=self._current_difficulty,
            step_in_episode=self._step_count,
            rng=self._rng,
        )

        # Build behavioral telemetry from response
        # Map response keys to BehavioralTelemetry fields
        telemetry = BehavioralTelemetry(
            decision_time=response["decision_time"],
            num_pauses=response["num_pauses"],
            num_retries=response["num_retries"],
            quit_early=response["quit_early"],
            completion_time=response["completion_time"],
            expected_decision_time=self.profile.avg_decision_time,
            expected_completion_time=25.0,  # Expected time for medium complexity
        )

        # Infer emotional state
        emotion_state = infer_emotion(telemetry)
        self._prev_frustration = self._frustration
        self._prev_engagement = self._engagement
        self._prev_confidence = self._confidence
        self._frustration = emotion_state.frustration
        self._engagement = emotion_state.engagement
        self._confidence = emotion_state.confidence

        # Calculate reward
        task_completed = response["task_completed"]
        reward = calculate_reward(
            task_completed=task_completed,
            engagement=self._engagement,
            frustration=self._frustration,
            confidence=self._confidence,
        )

        # Update performance history
        self._last_5_success.append(task_completed)
        if len(self._last_5_success) > 5:
            self._last_5_success.pop(0)

        if task_completed:
            self._total_scenarios_completed += 1
            self._current_streak = max(0, self._current_streak) + 1
        else:
            self._current_streak = min(0, self._current_streak) - 1

        # Update rolling success rate
        if len(self._last_5_success) > 0:
            self._rolling_success_rate = sum(self._last_5_success) / len(self._last_5_success)

        # Update average completion time (exponential moving average)
        alpha = 0.3
        self._avg_completion_time = (
            alpha * response["completion_time"] + (1 - alpha) * self._avg_completion_time
        )

        # Update improvement trend (simplified: positive if recent success rate improving)
        if len(self._last_5_success) >= 3:
            recent_success = sum(self._last_5_success[-3:]) / 3.0
            older_success = self._rolling_success_rate
            self._improvement_trend = np.clip(recent_success - older_success, -1.0, 1.0)

        # Update game theory features (simplified: evolve based on interactions)
        # These would be more sophisticated in a full implementation
        if task_completed:
            self._cooperation = min(1.0, self._cooperation + 0.01)
            self._trust = min(1.0, self._trust + 0.01)
            self._confidence = min(1.0, self._confidence + 0.02)
        else:
            self._risk = max(0.0, self._risk - 0.01)

        # Update session time (approximate 10s per step)
        self._session_time += 10.0

        # Increment step counter
        self._step_count += 1

        # Update cumulative reward
        self._total_reward += reward

        # Build new observation
        observation = self._get_obs()

        # Determine episode termination
        # For synthetic users, episodes don't naturally "complete" - they run until truncation
        terminated = False

        # Truncate at max steps
        truncated = self._step_count >= self._max_steps

        # Build info dict
        info = {
            "step_count": self._step_count,
            "profile_id": self.profile.id,
            "decoded_action": decoded,
            "task_completed": task_completed,
            "emotions": {
                "frustration": float(self._frustration),
                "engagement": float(self._engagement),
                "confidence": float(self._confidence),
            },
            "cumulative_reward": float(self._total_reward),
        }

        return observation, float(reward), terminated, truncated, info

    def _get_obs(self) -> np.ndarray:
        """
        Build the 60-dimensional observation vector.

        Returns:
            60-dimensional numpy array (float32)
        """
        # Profile features (20 dims)
        profile_features = self.profile.to_profile_features()

        # Context features (15 dims)
        context_features = build_context_features(
            difficulty=self._current_difficulty,
            scenario_type_idx=self._current_scenario_idx,
            step=self._step_count,
            session_time=self._session_time,
            reinforcement_idx=0,  # Simplified for now
            complexity_idx=0,  # Simplified for now
            last_action_idx=self._last_action_type_idx,
            max_steps=self._max_steps,
        )

        # Performance features (10 dims)
        performance_features = build_performance_features(
            last_5_success=self._last_5_success,
            rolling_success=self._rolling_success_rate,
            avg_completion=self._avg_completion_time,
            scenarios_completed=self._total_scenarios_completed,
            streak=self._current_streak,
            improvement=self._improvement_trend,
        )

        # Emotion features (10 dims)
        emotion_features = build_emotion_features(
            frustration=self._frustration,
            engagement=self._engagement,
            confidence=self._confidence,
            prev_frustration=self._prev_frustration,
            prev_engagement=self._prev_engagement,
            prev_confidence=self._prev_confidence,
        )

        # Game theory features (5 dims)
        game_theory_features = build_game_theory_features(
            cooperation=self._cooperation,
            risk=self._risk,
            fairness=self._fairness,
            trust=self._trust,
            reciprocity=self._reciprocity,
        )

        # Build full state vector
        state = build_state_vector(
            profile_features=profile_features,
            context_features=context_features,
            performance_features=performance_features,
            emotion_features=emotion_features,
            game_theory_features=game_theory_features,
        )

        return state

    def render(self):
        """Render the environment (minimal implementation)."""
        if self.render_mode == "human":
            print(f"Step: {self._step_count}, Difficulty: {self._current_difficulty}, "
                  f"Frustration: {self._frustration:.2f}, Engagement: {self._engagement:.2f}")

    def close(self):
        """Clean up resources."""
        pass
