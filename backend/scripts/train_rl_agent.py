#!/usr/bin/env python3
"""CLI script for training the RL agent with PPO.

Usage:
    cd backend
    uv run python scripts/train_rl_agent.py --output-dir model_store --data-dir data/synthetic_users --seed 42 --timesteps 100000
"""
import argparse
import sys
from pathlib import Path

# Ensure the backend root is on sys.path so `app` package is importable
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.rl.training.train_ppo import train_ppo
from app.rl.training.hyperparameters import get_ppo_config


def main():
    """Main CLI entry point for RL training."""
    parser = argparse.ArgumentParser(
        description="Train PPO agent for ASD intervention scenario selection"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="model_store",
        help="Directory to save models and checkpoints (default: model_store)",
    )
    parser.add_argument(
        "--data-dir",
        type=str,
        default="data/synthetic_users",
        help="Directory containing synthetic user profiles (default: data/synthetic_users)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)",
    )
    parser.add_argument(
        "--timesteps",
        type=int,
        default=None,
        help="Total training timesteps (default: from config, 100,000)",
    )

    args = parser.parse_args()

    # Print configuration
    print("=" * 60)
    print("PPO Training Configuration")
    print("=" * 60)
    print(f"Output directory: {args.output_dir}")
    print(f"Data directory: {args.data_dir}")
    print(f"Random seed: {args.seed}")

    config = get_ppo_config()
    timesteps = args.timesteps if args.timesteps is not None else config["total_timesteps"]
    print(f"Total timesteps: {timesteps}")
    print(f"Parallel environments: {config['n_envs']}")
    print(f"Learning rate: {config['learning_rate']}")
    print(f"Checkpoint frequency: {config['checkpoint_freq']}")
    print(f"Evaluation frequency: {config['eval_freq']}")
    print("=" * 60)
    print()

    # Verify data directory exists
    data_path = Path(args.data_dir)
    if not data_path.exists():
        print(f"ERROR: Data directory not found: {data_path}")
        print("Please run the synthetic user generation script first:")
        print("  python -m app.synthetic_users.generator")
        return 1

    # Train the agent
    try:
        model_path = train_ppo(
            output_dir=args.output_dir,
            data_dir=args.data_dir,
            seed=args.seed,
        )

        # Print summary
        print()
        print("=" * 60)
        print("Training Summary")
        print("=" * 60)
        print(f"Model saved to: {model_path}.zip")
        print(f"Best model: {args.output_dir}/best/best_model.zip")
        print(f"Checkpoints: {args.output_dir}/checkpoints/")
        print(f"TensorBoard logs: {args.output_dir}/tensorboard/")
        print()
        print("View training progress with TensorBoard:")
        print(f"  tensorboard --logdir {args.output_dir}/tensorboard")
        print("=" * 60)

        return 0

    except Exception as e:
        print(f"ERROR: Training failed with exception: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit(main())
