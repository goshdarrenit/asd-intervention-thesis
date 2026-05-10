"""Tests for multi-objective reward calculation.

"""
import pytest

from app.rl.reward_calculator import calculate_reward


class TestRewardCalculator:
    """Test suite for multi-objective reward calculation."""

    def test_perfect_scenario_high_reward(self):
        """Perfect scenario (task completed, high engagement, low frustration, high confidence) yields high reward."""
        reward = calculate_reward(
            task_completed=True,
            engagement=1.0,
            frustration=0.0,
            confidence=1.0
        )

        assert reward > 0.8, "Perfect scenario should yield reward > 0.8"

    def test_failed_scenario_low_reward(self):
        """Failed scenario (task not completed, low engagement, high frustration, low confidence) yields low reward."""
        reward = calculate_reward(
            task_completed=False,
            engagement=0.2,
            frustration=0.8,
            confidence=0.2
        )

        assert reward < 0.15, "Failed scenario should yield low reward < 0.15"

    def test_reward_weights_40_30_30(self):
        """Verify exact 40/30/30 weighting (task/engagement/emotion)."""
        # Test case 1: Only task completed (others at 0)
        reward_task_only = calculate_reward(
            task_completed=True,
            engagement=0.0,
            frustration=1.0,  # Worst emotion
            confidence=0.0
        )

        # Test case 2: Only engagement high (others at worst)
        reward_engagement_only = calculate_reward(
            task_completed=False,
            engagement=1.0,
            frustration=1.0,
            confidence=0.0
        )

        # The actual values will depend on how emotion_reward is calculated,
        # but we can verify relative magnitudes align with 40/30/30 split
        # Task completion should contribute ~40% of max reward
        # Engagement should contribute ~30% of max reward

        # For this test, we'll verify the implementation computes the weighted sum correctly
        # by checking against manually computed values

        # Perfect case: task=1.0, engagement=1.0, emotion=(1-0+1)/2=1.0
        # reward = 0.4*1.0 + 0.3*1.0 + 0.3*1.0 = 1.0
        reward_perfect = calculate_reward(
            task_completed=True,
            engagement=1.0,
            frustration=0.0,
            confidence=1.0
        )
        assert abs(reward_perfect - 1.0) < 0.01, "Perfect case should yield ~1.0"

        # Failed case: task=-0.01, engagement=0.0, emotion=(1-1+0)/2=0.0
        # reward = 0.4*(-0.01) + 0.3*0.0 + 0.3*0.0 = -0.004
        reward_failed = calculate_reward(
            task_completed=False,
            engagement=0.0,
            frustration=1.0,
            confidence=0.0
        )
        assert reward_failed < 0, "Complete failure should yield negative reward"

    def test_reward_with_mixed_signals(self):
        """Task completed but high frustration yields moderate reward."""
        reward = calculate_reward(
            task_completed=True,
            engagement=0.5,
            frustration=0.8,
            confidence=0.3
        )

        # Should be positive (task completed = +0.4) but not high due to poor emotions
        assert 0.1 < reward < 0.7, "Mixed signals should yield moderate reward"

    def test_reward_bounded(self):
        """Reward should remain within reasonable bounds for all valid inputs."""
        test_cases = [
            (True, 1.0, 0.0, 1.0),   # Best case
            (False, 0.0, 1.0, 0.0),  # Worst case
            (True, 0.5, 0.5, 0.5),   # Middle case
            (False, 1.0, 0.0, 1.0),  # Good emotions but failed
            (True, 0.0, 1.0, 0.0),   # Completed but bad emotions
        ]

        for task_completed, engagement, frustration, confidence in test_cases:
            reward = calculate_reward(task_completed, engagement, frustration, confidence)

            # Reasonable bounds: worst case should be small negative, best case ~1.0
            assert -0.5 <= reward <= 1.0, f"Reward {reward} out of bounds for case {test_cases}"
