import sys
from pathlib import Path

import pytest
import numpy as np
import pandas as pd
import scipy.stats

# Add scripts directory and backend root to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from scripts.run_evaluation import (
    RandomAgent,
    StaticDifficultyAgent,
    FixedCurriculumAgent,
    run_evaluation,
    generate_plots,
)
from app.domains.analytics.metrics import compute_metrics

def test_baselines():
    obs = np.zeros(60, dtype=np.float32)

    # RandomAgent
    rand_agent = RandomAgent(seed=0)
    action = rand_agent.predict(obs)
    assert isinstance(action, (int, np.integer)), f"Expected int, got {type(action)}"
    assert 0 <= action <= 224, f"Action {action} out of range [0, 224]"

    actions = [rand_agent.predict(obs) for _ in range(100)]
    assert len(set(actions)) >= 2, "RandomAgent should produce varied actions over 100 calls"

    # StaticDifficultyAgent
    static_agent = StaticDifficultyAgent(seed=0)
    action = static_agent.predict(obs)
    assert isinstance(action, (int, np.integer)), f"Expected int, got {type(action)}"
    assert 0 <= action <= 224, f"Action {action} out of range [0, 224]"

    # FixedCurriculumAgent
    curr_agent = FixedCurriculumAgent()
    action = curr_agent.predict(obs)
    assert isinstance(action, (int, np.integer)), f"Expected int, got {type(action)}"
    assert 0 <= action <= 224, f"Action {action} out of range [0, 224]"

    # Test reset
    curr_agent.step = 10
    curr_agent.reset()
    assert curr_agent.step == 0, f"Expected step=0 after reset, got {curr_agent.step}"


def test_metrics():
    # Create small mock DataFrame with required columns
    n = 20
    rng = np.random.default_rng(42)
    df = pd.DataFrame({
        "agent": ["test"] * n,
        "user_id": ["user_000"] * n,
        "split": ["train"] * n,
        "step": list(range(n)),
        "action_idx": rng.integers(0, 225, n),
        "scenario_type": ["sharing", "patience"] * (n // 2),
        "difficulty": rng.integers(1, 6, n),
        "task_completed": rng.choice([True, False], n).tolist(),
        "reward": rng.uniform(-1, 2, n),
        "frustration": rng.uniform(0, 1, n),
        "engagement": rng.uniform(0, 1, n),
        "confidence": rng.uniform(0, 1, n),
        "cooperation": rng.uniform(0, 1, n),
        "fairness": rng.uniform(0, 1, n),
        "num_retries": rng.integers(0, 4, n),
        "completion_time": rng.uniform(5, 30, n),
    })

    result = compute_metrics(df)

    required_keys = {
        "cci", "hesitation_reduction", "cooperation_rate", "fairness_index",
        "out_of_turn_rate", "repair_attempts", "engagement_stability", "emotional_stability"
    }
    assert set(result.keys()) == required_keys, (
        f"Missing keys: {required_keys - set(result.keys())}, "
        f"Extra keys: {set(result.keys()) - required_keys}"
    )

    for key, val in result.items():
        assert isinstance(val, float), f"Metric {key} should be float, got {type(val)}"
        assert 0.0 <= val <= 1.0, f"Metric {key}={val} out of [0, 1]"


def test_full_run(tmp_path):
    combined = run_evaluation(str(tmp_path), n_steps=3)

    expected_csvs = [
        "rl_agent_results.csv",
        "random_baseline_results.csv",
        "static_difficulty_results.csv",
        "fixed_curriculum_results.csv",
    ]
    for csv_name in expected_csvs:
        csv_path = tmp_path / csv_name
        assert csv_path.exists(), f"Expected CSV not found: {csv_name}"
        df = pd.read_csv(csv_path)
        assert len(df) > 0, f"CSV is empty: {csv_name}"

        required_cols = {"agent", "user_id", "split", "step", "reward", "task_completed",
                         "frustration", "engagement", "confidence"}
        assert required_cols.issubset(set(df.columns)), (
            f"Missing columns in {csv_name}: {required_cols - set(df.columns)}"
        )

    assert combined is not None
    assert len(combined) > 0

def test_metric_targets(tmp_path):
    from scripts.run_evaluation import PPORLAgent
    from app.synthetic_users.generator import load_all_profiles

    profiles = load_all_profiles("data/synthetic_users", split="test")[:5]
    agent = PPORLAgent()

    # Run a small simulation to compute metrics
    from scripts.run_evaluation import run_agent
    df = run_agent(agent, "rl_agent", profiles, n_steps=5, seed=42)

    assert len(df) > 0, "Expected non-empty DataFrame from RL agent run"
    success_rate = df["task_completed"].mean()
    assert success_rate > 0.4, f"RL agent success rate {success_rate:.2f} below 0.4 threshold"


def test_stats(tmp_path):
    rng = np.random.default_rng(42)
    rl_rewards = rng.normal(loc=1.5, scale=0.3, size=100)
    random_rewards = rng.normal(loc=0.5, scale=0.3, size=100)

    t_stat, p_value = scipy.stats.ttest_ind(rl_rewards, random_rewards)
    assert p_value < 0.05, f"Expected p < 0.05 for well-separated data, got p={p_value:.6f}"


def test_plots(tmp_path):
    rng = np.random.default_rng(42)
    n = 40
    agents = ["rl_agent", "random_baseline"] * (n // 2)
    df = pd.DataFrame({
        "agent": agents,
        "user_id": [f"user_{i:03d}" for i in range(n)],
        "split": ["train"] * n,
        "step": list(range(10)) * 4,
        "reward": rng.uniform(-0.5, 2.0, n),
        "task_completed": rng.choice([True, False], n).tolist(),
        "frustration": rng.uniform(0, 1, n),
        "engagement": rng.uniform(0, 1, n),
        "confidence": rng.uniform(0, 1, n),
    })

    generate_plots(df, str(tmp_path))

    figures_dir = tmp_path / "figures"
    learning_curves = figures_dir / "learning_curves.png"
    baseline_comparison = figures_dir / "baseline_comparison.png"

    assert learning_curves.exists(), "learning_curves.png not found"
    assert baseline_comparison.exists(), "baseline_comparison.png not found"
    assert learning_curves.stat().st_size > 1024, f"learning_curves.png too small: {learning_curves.stat().st_size} bytes"
    assert baseline_comparison.stat().st_size > 1024, f"baseline_comparison.png too small: {baseline_comparison.stat().st_size} bytes"
