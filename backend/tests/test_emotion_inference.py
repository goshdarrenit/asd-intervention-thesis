"""Tests for emotion inference from behavioral telemetry.

"""
import pytest

from app.rl.emotion_inference import BehavioralTelemetry, EmotionalState, infer_emotion


class TestEmotionInference:
    """Test suite for emotion inference logic."""

    def test_high_frustration_from_many_pauses_retries_quit(self):
        """High frustration when user pauses frequently, retries, and quits early."""
        telemetry = BehavioralTelemetry(
            decision_time=5.0,
            num_pauses=5,
            num_retries=5,
            quit_early=True,
            completion_time=15.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert emotion.frustration >= 0.8, "Many pauses, retries, and quit should yield high frustration"
        assert 0.0 <= emotion.frustration <= 1.0, "Frustration must be in [0, 1]"

    def test_low_frustration_from_calm_behavior(self):
        """Low frustration when user shows calm, steady behavior."""
        telemetry = BehavioralTelemetry(
            decision_time=5.0,
            num_pauses=0,
            num_retries=0,
            quit_early=False,
            completion_time=25.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert emotion.frustration <= 0.1, "No pauses, retries, or quit should yield low frustration"
        assert 0.0 <= emotion.frustration <= 1.0, "Frustration must be in [0, 1]"

    def test_high_engagement_from_normal_completion_time(self):
        """High engagement when completion time is within expected range."""
        telemetry = BehavioralTelemetry(
            decision_time=5.0,
            num_pauses=0,
            num_retries=0,
            quit_early=False,
            completion_time=25.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert emotion.engagement >= 0.8, "Normal completion time should yield high engagement"
        assert 0.0 <= emotion.engagement <= 1.0, "Engagement must be in [0, 1]"

    def test_low_engagement_from_very_slow_completion(self):
        """Low engagement when completion takes much longer than expected."""
        telemetry = BehavioralTelemetry(
            decision_time=5.0,
            num_pauses=0,
            num_retries=0,
            quit_early=False,
            completion_time=90.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert emotion.engagement <= 0.5, "Very slow completion should yield low engagement"
        assert 0.0 <= emotion.engagement <= 1.0, "Engagement must be in [0, 1]"

    def test_guessing_detection_low_engagement(self):
        """Low engagement when completion is too fast (guessing)."""
        telemetry = BehavioralTelemetry(
            decision_time=1.0,
            num_pauses=0,
            num_retries=0,
            quit_early=False,
            completion_time=5.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert emotion.engagement <= 0.4, "Too fast completion (guessing) should yield low engagement"
        assert 0.0 <= emotion.engagement <= 1.0, "Engagement must be in [0, 1]"

    def test_high_confidence_from_fast_decisions(self):
        """High confidence when decisions are fast without hesitation."""
        telemetry = BehavioralTelemetry(
            decision_time=1.0,
            num_pauses=0,
            num_retries=0,
            quit_early=False,
            completion_time=25.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert emotion.confidence >= 0.7, "Fast decisive actions should yield high confidence"
        assert 0.0 <= emotion.confidence <= 1.0, "Confidence must be in [0, 1]"

    def test_low_confidence_from_slow_hesitant_decisions(self):
        """Low confidence when decisions are slow with many pauses/retries."""
        telemetry = BehavioralTelemetry(
            decision_time=9.0,
            num_pauses=3,
            num_retries=2,
            quit_early=False,
            completion_time=40.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert emotion.confidence <= 0.2, "Slow hesitant decisions should yield low confidence"
        assert 0.0 <= emotion.confidence <= 1.0, "Confidence must be in [0, 1]"

    def test_all_emotions_clamped_0_to_1(self):
        """All emotion values must be clamped to [0, 1] range."""
        # Test extreme values that could cause overflow
        extreme_telemetries = [
            BehavioralTelemetry(
                decision_time=100.0,
                num_pauses=50,
                num_retries=50,
                quit_early=True,
                completion_time=500.0,
                expected_decision_time=5.0,
                expected_completion_time=30.0
            ),
            BehavioralTelemetry(
                decision_time=0.1,
                num_pauses=0,
                num_retries=0,
                quit_early=False,
                completion_time=1.0,
                expected_decision_time=5.0,
                expected_completion_time=30.0
            ),
        ]

        for telemetry in extreme_telemetries:
            emotion = infer_emotion(telemetry)

            assert 0.0 <= emotion.frustration <= 1.0, f"Frustration out of range: {emotion.frustration}"
            assert 0.0 <= emotion.engagement <= 1.0, f"Engagement out of range: {emotion.engagement}"
            assert 0.0 <= emotion.confidence <= 1.0, f"Confidence out of range: {emotion.confidence}"

    def test_emotion_state_fields_are_floats(self):
        """Verify that all emotion state fields are float type."""
        telemetry = BehavioralTelemetry(
            decision_time=5.0,
            num_pauses=1,
            num_retries=1,
            quit_early=False,
            completion_time=25.0,
            expected_decision_time=5.0,
            expected_completion_time=30.0
        )

        emotion = infer_emotion(telemetry)

        assert isinstance(emotion.frustration, float), "Frustration must be float"
        assert isinstance(emotion.engagement, float), "Engagement must be float"
        assert isinstance(emotion.confidence, float), "Confidence must be float"
