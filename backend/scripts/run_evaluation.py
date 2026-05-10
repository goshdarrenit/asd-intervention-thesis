"""Batch evaluation runner for ASD Intervention RL system.

Runs 50 users x 20 scenarios for 4 agents (RL, Random, StaticDifficulty,
FixedCurriculum) and produces 4 CSV files plus comparison plots.

Also provides run_comparison_study() for the agent comparison study:
  - 10 test profiles x 5 episodes each x 4 agents (PPO, Random, RuleBased, Curriculum)
  - Outputs CSVs + figures to data/evaluation/comparison/

3 baseline agents
batch simulation + CSV export
learning_curves.png + baseline_comparison.png
RL agent target metrics
"""
from __future__ import annotations

import sys
from pathlib import Path

# Allow script to be run directly OR imported as a module.
sys.path.insert(0, str(Path(__file__).parent.parent))

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # Non-interactive backend for headless use
import matplotlib.pyplot as plt
import seaborn as sns
from tqdm import tqdm

from app.rl.action_space import encode_action, ACTION_SPACE_CONFIG
from app.rl.environment import ASDInterventionEnv
from app.synthetic_users.generator import load_all_profiles
from scripts.agents.rule_based_agent import RuleBasedAdaptiveAgent


# ---------------------------------------------------------------------------
# Baseline agents
# ---------------------------------------------------------------------------

class RandomAgent:
    """uniformly random action from [0, 224]."""

    def __init__(self, seed: int = 0) -> None:
        self._rng = np.random.default_rng(seed)

    def predict(self, obs: np.ndarray) -> int:
        return int(self._rng.integers(0, 225))


class StaticDifficultyAgent:
    """random scenario type, fixed mid difficulty (index 2 = delta 0),
    positive reinforcement (index 0), medium complexity (index 1)."""

    def __init__(self, seed: int = 0) -> None:
        self._rng = np.random.default_rng(seed)

    def predict(self, obs: np.ndarray) -> int:
        type_idx = int(self._rng.integers(0, 5))
        return int(encode_action(type_idx, 2, 0, 1))


class FixedCurriculumAgent:
    """cycles scenario types 0-4, difficulty delta increases
    +1 every 5 steps (capped at index 4)."""

    def __init__(self) -> None:
        self.step: int = 0

    def reset(self) -> None:
        """Reset step counter between users."""
        self.step = 0

    def predict(self, obs: np.ndarray) -> int:
        type_idx = self.step % 5
        # difficulty_delta_idx: increase by +1 every 5 steps, capped at index 4 (delta +2)
        difficulty_delta_idx = min(self.step // 5, 4)
        action = int(encode_action(type_idx, difficulty_delta_idx, 0, 1))
        self.step += 1
        return action


# ---------------------------------------------------------------------------
# PPO RL agent wrapper
# ---------------------------------------------------------------------------

class PPORLAgent:
    """RL agent wrapping trained PPO model via RLPredictor."""

    def __init__(
        self,
        model_path: str = "model_store/ppo_asd_final",
        stats_path: str = "model_store/vec_normalize.pkl",
    ) -> None:
        from app.rl.inference.model_loader import load_model, load_vec_normalize
        from app.rl.inference.predictor import RLPredictor

        model = load_model(model_path)
        vec_normalize = load_vec_normalize(stats_path)
        self._predictor = RLPredictor(model, vec_normalize)

    def predict(self, obs: np.ndarray) -> int:
        result = self._predictor.predict(obs, deterministic=True)
        return int(result["action_index"])


# ---------------------------------------------------------------------------
# Simulation runner
# ---------------------------------------------------------------------------

def run_agent(
    agent,
    agent_name: str,
    profiles: list,
    n_steps: int = 20,
    n_episodes: int = 1,
    seed: int = 42,
) -> pd.DataFrame:
    """Run one agent across all profiles and return a DataFrame of step-level data.

    Args:
        agent: Agent with .predict(obs) -> int method.
        agent_name: Human-readable agent name (stored in 'agent' column).
        profiles: List of SyntheticUserProfile objects.
        n_steps: Number of environment steps per episode.
        n_episodes: Number of episodes to run per profile (seeds vary per episode).
        seed: Base random seed; episode i uses seed+i for reproducibility.

    Returns:
        pd.DataFrame with one row per step.
    """
    rows = []

    for profile in tqdm(profiles, desc=agent_name):
        for episode in range(n_episodes):
            episode_seed = seed + episode
            env = ASDInterventionEnv(profile, seed=episode_seed)
            obs, _ = env.reset(seed=episode_seed)

            # Reset stateful agents between episodes
            if hasattr(agent, "reset"):
                agent.reset()

            for step_idx in range(n_steps):
                action_idx = agent.predict(obs)
                obs, reward, terminated, truncated, info = env.step(action_idx)

                decoded = info.get("decoded_action", {})
                emotions = info.get("emotions", {})

                rows.append({
                    "agent": agent_name,
                    "user_id": profile.id,
                    "split": profile.split,
                    "severity": int(profile.severity),
                    "episode": episode,
                    "step": step_idx,
                    "action_idx": action_idx,
                    "scenario_type": decoded.get("action_type", ""),
                    "difficulty": env._current_difficulty,
                    "task_completed": bool(info.get("task_completed", False)),
                    "reward": float(reward),
                    "frustration": float(emotions.get("frustration", 0.0)),
                    "engagement": float(emotions.get("engagement", 0.0)),
                    "confidence": float(emotions.get("confidence", 0.0)),
                    "cooperation": float(env._cooperation),
                    "fairness": float(env._fairness),
                    "num_retries": int(info.get("num_retries", 0)),
                    "completion_time": float(env._avg_completion_time),
                })

                if terminated or truncated:
                    break

    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Plot generation
# ---------------------------------------------------------------------------

def generate_plots(df: pd.DataFrame, output_dir: str) -> None:
    """Generate evaluation comparison plots.

    Creates:
    - figures/learning_curves.png: seaborn lineplot reward over steps per agent.
    - figures/baseline_comparison.png: barplot mean task_completed per agent.

    Args:
        df: Combined DataFrame from run_evaluation() or mock data.
        output_dir: Directory where figures/ subdirectory will be created.
    """
    figures_dir = Path(output_dir) / "figures"
    figures_dir.mkdir(parents=True, exist_ok=True)

    sns.set_theme(style="whitegrid")

    # 1. Learning curves: reward over steps per agent
    fig, ax = plt.subplots(figsize=(10, 6))
    sns.lineplot(
        data=df,
        x="step",
        y="reward",
        hue="agent",
        errorbar=("ci", 95),
        ax=ax,
    )
    ax.set_title("Learning Curves: Reward Over Steps by Agent")
    ax.set_xlabel("Step")
    ax.set_ylabel("Reward")
    fig.tight_layout()
    fig.savefig(figures_dir / "learning_curves.png", dpi=100)
    plt.close(fig)

    # 2. Baseline comparison: mean task completion per agent
    fig, ax = plt.subplots(figsize=(8, 5))
    sns.barplot(
        data=df,
        x="agent",
        y="task_completed",
        ax=ax,
        order=sorted(df["agent"].unique()),
    )
    ax.set_title("Baseline Comparison: Mean Task Completion Rate per Agent")
    ax.set_xlabel("Agent")
    ax.set_ylabel("Mean Task Completed")
    ax.set_ylim(0, 1)
    fig.tight_layout()
    fig.savefig(figures_dir / "baseline_comparison.png", dpi=100)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Comparison study entry point (thesis agent comparison study)
# ---------------------------------------------------------------------------

def run_comparison_study(
    output_dir: str = "data/evaluation/comparison",
    n_steps: int = 20,
    n_episodes: int = 5,
) -> pd.DataFrame:
    """Run the agent comparison study for the thesis.

    Evaluates 4 agents on the 10 held-out test profiles across n_episodes each:
      - PPO RL agent (trained adaptive agent)
      - Random baseline (lower bound)
      - Rule-based adaptive (heuristic difficulty scaling)
      - Fixed curriculum (static progression)

    Args:
        output_dir: Directory for CSV output files and figures.
        n_steps: Number of simulation steps per episode (default 20).
        n_episodes: Number of episodes per profile (default 5).

    Returns:
        Combined DataFrame of all agents' results.
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Load only the 10 held-out test profiles
    test_profiles = load_all_profiles("data/synthetic_users", split="test")
    print(f"Loaded {len(test_profiles)} test profiles")
    print(f"Severity distribution: { {s: sum(1 for p in test_profiles if p.severity == s) for s in [1,2,3]} }")

    # Define agents for comparison study
    agents = [
        (PPORLAgent(), "PPO (RL Agent)", "results_ppo.csv"),
        (RandomAgent(seed=42), "Random", "results_random.csv"),
        (RuleBasedAdaptiveAgent(), "Rule-Based Adaptive", "results_rule_based.csv"),
        (FixedCurriculumAgent(), "Fixed Curriculum", "results_curriculum.csv"),
    ]

    all_dfs = []
    for agent, agent_name, csv_name in agents:
        print(f"\nRunning {agent_name} ({n_episodes} episodes × {len(test_profiles)} profiles)...")
        df = run_agent(
            agent, agent_name, test_profiles,
            n_steps=n_steps, n_episodes=n_episodes, seed=42
        )
        df.to_csv(output_path / csv_name, index=False)
        mean_reward = df["reward"].mean()
        mean_task = df["task_completed"].mean()
        print(f"  Saved {len(df)} rows -> mean_reward={mean_reward:.4f}, task_rate={mean_task:.3f}")
        all_dfs.append(df)

    combined = pd.concat(all_dfs, ignore_index=True)
    combined.to_csv(output_path / "results_combined.csv", index=False)
    print(f"\nCombined CSV: {len(combined)} total rows -> {output_dir}/results_combined.csv")

    # Summary table
    summary = combined.groupby("agent").agg(
        mean_reward=("reward", "mean"),
        std_reward=("reward", "std"),
        task_rate=("task_completed", "mean"),
        mean_frustration=("frustration", "mean"),
        mean_engagement=("engagement", "mean"),
        mean_confidence=("confidence", "mean"),
        n_rows=("reward", "count"),
    ).round(4)
    summary.to_csv(output_path / "summary_table.csv")
    print("\nSummary table:")
    print(summary.to_string())

    return combined


# ---------------------------------------------------------------------------
# Full evaluation entry point
# ---------------------------------------------------------------------------

def run_evaluation(output_dir: str = "data/evaluation", n_steps: int = 20) -> pd.DataFrame:
    """Run full evaluation: 50 users x n_steps for all 4 agents.

    Args:
        output_dir: Directory for CSV output files.
        n_steps: Number of simulation steps per user per agent (default 20).

    Returns:
        Combined DataFrame of all agents' results.
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Load all 50 profiles
    train_profiles = load_all_profiles("data/synthetic_users", split="train")
    test_profiles = load_all_profiles("data/synthetic_users", split="test")
    all_profiles = train_profiles + test_profiles

    # Define agents
    agents = [
        (PPORLAgent(), "rl_agent", "rl_agent_results.csv"),
        (RandomAgent(seed=42), "random", "random_results.csv"),
        (StaticDifficultyAgent(seed=42), "static_difficulty", "static_difficulty_results.csv"),
        (FixedCurriculumAgent(), "fixed_curriculum", "fixed_curriculum_results.csv"),
    ]

    all_dfs = []
    for agent, agent_name, csv_name in agents:
        print(f"\nRunning {agent_name}...")
        df = run_agent(agent, agent_name, all_profiles, n_steps=n_steps, seed=42)
        df.to_csv(output_path / csv_name, index=False)
        print(f"  Saved {len(df)} rows to {csv_name}")
        all_dfs.append(df)

    combined = pd.concat(all_dfs, ignore_index=True)

    # Generate plots
    print("\nGenerating plots...")
    generate_plots(combined, output_dir)
    print("  Plots saved to figures/")

    return combined


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run ASD Intervention evaluation")
    parser.add_argument(
        "--mode",
        choices=["full", "comparison"],
        default="full",
        help="'full' runs all 50 profiles x 1 episode; 'comparison' runs 10 test profiles x 5 episodes",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Output directory (defaults differ by mode)",
    )
    parser.add_argument(
        "--n-steps",
        type=int,
        default=20,
        help="Number of simulation steps per episode (default: 20)",
    )
    parser.add_argument(
        "--n-episodes",
        type=int,
        default=5,
        help="Episodes per profile for comparison mode (default: 5)",
    )
    args = parser.parse_args()

    if args.mode == "comparison":
        out = args.output_dir or "data/evaluation/comparison"
        print(f"Running comparison study: output_dir={out}, n_steps={args.n_steps}, n_episodes={args.n_episodes}")
        combined = run_comparison_study(out, args.n_steps, args.n_episodes)
        print(f"\nDone. {len(combined)} total rows, {combined['agent'].nunique()} agents.")
    else:
        out = args.output_dir or "data/evaluation"
        print(f"Running full evaluation: output_dir={out}, n_steps={args.n_steps}")
        combined = run_evaluation(out, args.n_steps)
        print(f"\nDone. Combined DataFrame: {len(combined)} total rows.")
        print(f"Agents: {combined['agent'].unique().tolist()}")
        print(f"Users: {combined['user_id'].nunique()}")
