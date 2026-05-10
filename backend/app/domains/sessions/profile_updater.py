"""Profile updater implementing EMA (Exponential Moving Average) updates.

Applies incremental EMA updates (alpha=0.3) to user profiles
after scenario completion.
"""
from uuid import UUID

import numpy as np
import redis.asyncio as redis
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified

from app.domains.sessions.models import ScenarioResult
from app.domains.users.models import UserProfile
from app.domains.sessions import repository
from app.rl.state_builder import (
    build_context_features,
    build_performance_features,
    build_emotion_features,
    build_game_theory_features,
    build_state_vector,
)


class ProfileUpdater:
    """Updates user profiles with EMA after scenario completion."""

    ALPHA = 0.3

    @staticmethod
    def update_with_ema(old_value: float, new_observation: float) -> float:
        """Apply exponential moving average update.

        Formula: new_value = ALPHA * new_observation + (1 - ALPHA) * old_value

        Args:
            old_value: Previous value
            new_observation: New observation

        Returns:
            Updated value using EMA formula
        """
        return ProfileUpdater.ALPHA * new_observation + (1 - ProfileUpdater.ALPHA) * old_value

    async def update_profile_after_scenario(
        self,
        db: AsyncSession,
        redis_client: redis.Redis,
        user_id: UUID,
        scenario_result: ScenarioResult,
    ) -> None:
        """Update user profile with EMA after scenario completion.

        Applies EMA to success rate and emotional metrics.
        Updates recent history arrays (last 5 scenarios/success rates).

        Args:
            db: Async database session
            redis_client: Async Redis client
            user_id: User UUID
            scenario_result: ScenarioResult containing completion data

        Raises:
            ValueError: If profile not found for user_id
        """
        # Load profile
        profile = await db.get(UserProfile, user_id)
        if profile is None:
            raise ValueError(f"Profile not found for user_id: {user_id}")

        # Apply EMA to overall success rate
        success_observation = 1.0 if scenario_result.completed else 0.0
        profile.overall_success_rate = self.update_with_ema(
            profile.overall_success_rate,
            success_observation,
        )

        # Increment scenarios completed
        profile.scenarios_completed += 1

        # Update last_5_scenarios (keep last 5 only)
        last_5_scenarios = profile.last_5_scenarios or []
        last_5_scenarios.append(scenario_result.scenario_type)
        profile.last_5_scenarios = last_5_scenarios[-5:]
        flag_modified(profile, "last_5_scenarios")

        # Update last_5_success_rates (keep last 5 only)
        last_5_success = profile.last_5_success_rates or []
        last_5_success.append(success_observation)
        profile.last_5_success_rates = last_5_success[-5:]
        flag_modified(profile, "last_5_success_rates")

        # Update emotional history with EMA if emotions available
        if scenario_result.emotions is not None:
            emotional_history = profile.emotional_history or {}

            # Apply EMA to frustration_mean
            if "frustration" in scenario_result.emotions:
                old_frustration = emotional_history.get("frustration_mean", 0.3)
                new_frustration = scenario_result.emotions["frustration"]
                emotional_history["frustration_mean"] = self.update_with_ema(
                    old_frustration,
                    new_frustration,
                )

            # Apply EMA to engagement_mean
            if "engagement" in scenario_result.emotions:
                old_engagement = emotional_history.get("engagement_mean", 0.7)
                new_engagement = scenario_result.emotions["engagement"]
                emotional_history["engagement_mean"] = self.update_with_ema(
                    old_engagement,
                    new_engagement,
                )

            # Apply EMA to confidence_mean
            if "confidence" in scenario_result.emotions:
                old_confidence = emotional_history.get("confidence_mean", 0.5)
                new_confidence = scenario_result.emotions["confidence"]
                emotional_history["confidence_mean"] = self.update_with_ema(
                    old_confidence,
                    new_confidence,
                )

            profile.emotional_history = emotional_history
            flag_modified(profile, "emotional_history")

        # Update current_difficulty to the difficulty of the scenario just played
        # (this value was computed by the RL model or fallback in /next)
        profile.current_difficulty = scenario_result.difficulty

        # Rebuild 60-dim state vector from updated profile data so RL model
        # sees fresh observations on the next /next call
        profile.state_vector = self._rebuild_state_vector(profile, scenario_result)
        flag_modified(profile, "state_vector")

        # Flush changes (caller handles commit for transaction atomicity)
        await db.flush()

        # Note: Cache invalidation is handled by the calling service after all updates
        # to avoid redundant invalidations in a loop

    def _rebuild_state_vector(
        self,
        profile: UserProfile,
        scenario_result: ScenarioResult,
    ) -> list[float]:
        """Rebuild the 60-dim state vector from current profile data.

        Uses the same state_builder functions used during RL training so the
        model receives observations in the expected format.

        Args:
            profile: Updated user profile
            scenario_result: Latest scenario result

        Returns:
            60-element list of floats for JSONB storage
        """
        # Profile features (20 dims): first 20 elements from existing state_vector
        # Preserve the original profile features (age, severity, etc.) that were
        # set at user creation; they don't change.
        existing_sv = profile.state_vector or [0.0] * 60
        profile_features = np.array(existing_sv[:20], dtype=np.float32)
        if profile_features.shape[0] < 20:
            profile_features = np.pad(
                profile_features, (0, 20 - profile_features.shape[0])
            )

        # Context features (15 dims): current difficulty, scenario type, etc.
        scenario_types = [
            "sharing", "patience", "emotion_recognition",
            "turn_taking", "conflict_resolution",
        ]
        scenario_type_idx = (
            scenario_types.index(scenario_result.scenario_type)
            if scenario_result.scenario_type in scenario_types
            else 0
        )
        complexity_levels = ["low", "medium", "high"]
        complexity_idx = (
            complexity_levels.index(scenario_result.complexity)
            if scenario_result.complexity in complexity_levels
            else 0
        )
        reinforcement_modes = ["positive", "neutral", "corrective"]
        reinforcement_idx = (
            reinforcement_modes.index(scenario_result.reinforcement_mode)
            if scenario_result.reinforcement_mode in reinforcement_modes
            else 0
        )

        context_features = build_context_features(
            difficulty=profile.current_difficulty,
            scenario_type_idx=scenario_type_idx,
            step=profile.scenarios_completed,
            session_time=0.0,  # Not tracked per-scenario
            reinforcement_idx=reinforcement_idx,
            complexity_idx=complexity_idx,
            last_action_idx=0,
        )

        # Performance features (10 dims)
        last_5_success = [
            bool(s) for s in (profile.last_5_success_rates or [])
        ]
        performance_features = build_performance_features(
            last_5_success=last_5_success,
            rolling_success=profile.overall_success_rate,
            avg_completion=0.0,  # Could be tracked in future
            scenarios_completed=profile.scenarios_completed,
            streak=self._calculate_streak(last_5_success),
            improvement=self._calculate_improvement(
                profile.last_5_success_rates or []
            ),
        )

        # Emotion features (10 dims)
        emotional_history = profile.emotional_history or {}
        frustration = emotional_history.get("frustration_mean", 0.3)
        engagement = emotional_history.get("engagement_mean", 0.7)
        confidence = emotional_history.get("confidence_mean", 0.5)

        # Use scenario emotions as "previous" to capture trend
        scenario_emotions = scenario_result.emotions or {}
        prev_frustration = scenario_emotions.get("frustration", frustration)
        prev_engagement = scenario_emotions.get("engagement", engagement)
        prev_confidence = scenario_emotions.get("confidence", confidence)

        emotion_features = build_emotion_features(
            frustration=frustration,
            engagement=engagement,
            confidence=confidence,
            prev_frustration=prev_frustration,
            prev_engagement=prev_engagement,
            prev_confidence=prev_confidence,
        )

        # Game theory features (5 dims): defaults for now
        game_theory_features = build_game_theory_features(
            cooperation=0.5,
            risk=0.5,
            fairness=0.5,
            trust=0.5,
            reciprocity=0.5,
        )

        state = build_state_vector(
            profile_features=profile_features,
            context_features=context_features,
            performance_features=performance_features,
            emotion_features=emotion_features,
            game_theory_features=game_theory_features,
        )

        return state.tolist()

    @staticmethod
    def _calculate_streak(last_5_success: list[bool]) -> int:
        """Calculate current streak from recent results."""
        if not last_5_success:
            return 0
        streak = 0
        last_val = last_5_success[-1]
        for val in reversed(last_5_success):
            if val == last_val:
                streak += 1
            else:
                break
        return streak if last_val else -streak

    @staticmethod
    def _calculate_improvement(last_5_rates: list[float]) -> float:
        """Calculate improvement trend from recent success rates."""
        if len(last_5_rates) < 2:
            return 0.0
        # Simple: compare second half to first half
        mid = len(last_5_rates) // 2
        first_half = sum(last_5_rates[:mid]) / max(mid, 1)
        second_half = sum(last_5_rates[mid:]) / max(len(last_5_rates) - mid, 1)
        return second_half - first_half
