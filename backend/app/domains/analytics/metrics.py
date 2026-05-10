"""8 metric computations from simulation DataFrame.

Each metric returns a float in [0.0, 1.0].
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def compute_metrics(df: pd.DataFrame) -> dict[str, float]:
    """Compute all 8 progression metrics from a simulation DataFrame.

    Args:
        df: DataFrame with columns produced by run_agent():
            task_completed, difficulty, frustration, engagement, confidence,
            cooperation, fairness, num_retries, completion_time, scenario_type.

    Returns:
        dict with exactly 8 keys:
            cci, hesitation_reduction, cooperation_rate, fairness_index,
            out_of_turn_rate, repair_attempts, engagement_stability,
            emotional_stability.
        All values are float in [0.0, 1.0].
    """
    metrics: dict[str, float] = {}

    # 1. CCI — Challenge-Completion Index
    # Fraction of steps where the task was completed (appropriate difficulty proxy).
    if "task_completed" in df.columns and len(df) > 0:
        metrics["cci"] = float(df["task_completed"].mean())
    else:
        metrics["cci"] = 0.0

    # 2. Hesitation Reduction
    # 1.0 - (mean completion time in last 5 steps / mean completion time in first 5 steps)
    # Positive value means the user became faster (less hesitation) over the session.
    if "completion_time" in df.columns and len(df) >= 2:
        first_5 = df["completion_time"].iloc[:5].mean()
        last_5 = df["completion_time"].iloc[-5:].mean()
        if first_5 > 0:
            hesitation_reduction = 1.0 - (last_5 / first_5)
        else:
            hesitation_reduction = 0.5
        metrics["hesitation_reduction"] = float(np.clip(hesitation_reduction, 0.0, 1.0))
    else:
        metrics["hesitation_reduction"] = 0.5

    # 3. Cooperation Rate — mean cooperation score (0-1)
    if "cooperation" in df.columns and len(df) > 0:
        metrics["cooperation_rate"] = float(np.clip(df["cooperation"].mean(), 0.0, 1.0))
    else:
        metrics["cooperation_rate"] = 0.5

    # 4. Fairness Index — mean fairness score (0-1)
    if "fairness" in df.columns and len(df) > 0:
        metrics["fairness_index"] = float(np.clip(df["fairness"].mean(), 0.0, 1.0))
    else:
        metrics["fairness_index"] = 0.5

    # 5. Out-of-Turn Rate
    # Fraction of consecutive steps where the same scenario_type repeated 3+ times.
    if "scenario_type" in df.columns and len(df) > 0:
        scenario_types = df["scenario_type"].tolist()
        n_out_of_turn = 0
        run_len = 1
        for i in range(1, len(scenario_types)):
            if scenario_types[i] == scenario_types[i - 1]:
                run_len += 1
                if run_len == 3:
                    # Count the step that just extended the run to 3 as out-of-turn
                    n_out_of_turn += 1
                elif run_len > 3:
                    # Every additional repeat beyond 3 is also out-of-turn
                    n_out_of_turn += 1
            else:
                run_len = 1
        out_of_turn_rate = n_out_of_turn / len(scenario_types) if len(scenario_types) > 0 else 0.0
        metrics["out_of_turn_rate"] = float(np.clip(out_of_turn_rate, 0.0, 1.0))
    else:
        metrics["out_of_turn_rate"] = 0.0

    # 6. Repair Attempts
    # Mean num_retries normalized by 3 (max reasonable retries), clamped [0, 1].
    if "num_retries" in df.columns and len(df) > 0:
        metrics["repair_attempts"] = float(np.clip(df["num_retries"].mean() / 3.0, 0.0, 1.0))
    else:
        metrics["repair_attempts"] = 0.0

    # 7. Engagement Stability — 1.0 - std(engagement), clamped [0, 1].
    if "engagement" in df.columns and len(df) > 1:
        eng_std = float(df["engagement"].std())
        metrics["engagement_stability"] = float(np.clip(1.0 - eng_std, 0.0, 1.0))
    elif "engagement" in df.columns and len(df) == 1:
        metrics["engagement_stability"] = 1.0
    else:
        metrics["engagement_stability"] = 0.5

    # 8. Emotional Stability — fraction of steps where frustration < 0.7.
    if "frustration" in df.columns and len(df) > 0:
        metrics["emotional_stability"] = float((df["frustration"] < 0.7).mean())
    else:
        metrics["emotional_stability"] = 0.5

    return metrics
