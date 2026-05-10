"""PPO training pipeline with parallel environments and callbacks.

Training loop with VecNormalize,
checkpointing, evaluation, and TensorBoard logging.
"""
from pathlib import Path

from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize
from stable_baselines3.common.callbacks import CheckpointCallback, EvalCallback, CallbackList

from app.rl.environment import ASDInterventionEnv
from app.synthetic_users.generator import load_all_profiles
from app.rl.training.hyperparameters import get_ppo_config


def train_ppo(
    output_dir: str = "model_store",
    data_dir: str = "data/synthetic_users",
    seed: int = 42,
) -> str:
    """Train PPO agent with parallel environments, normalization, and callbacks.

    Creates 8 parallel training environments using the first 8 train profiles,
    wraps with VecNormalize for observation and reward normalization, and trains
    with checkpointing and evaluation callbacks.

    Args:
        output_dir: Directory to save models and checkpoints (default "model_store")
        data_dir: Directory containing synthetic user profiles (default "data/synthetic_users")
        seed: Random seed for reproducibility (default 42)

    Returns:
        Path to the final trained model

    Example:
        >>> model_path = train_ppo(output_dir="model_store", seed=42)
        >>> print(f"Model saved to: {model_path}")
    """
    # Load hyperparameters
    config = get_ppo_config()

    # Load profiles
    train_profiles = load_all_profiles(data_dir, split="train")
    test_profiles = load_all_profiles(data_dir, split="test")

    print(f"Loaded {len(train_profiles)} train profiles, {len(test_profiles)} test profiles")

    # Create parallel training environments (one per profile, up to n_envs)
    n_train_envs = min(config["n_envs"], len(train_profiles))
    train_env_fns = []
    for i in range(n_train_envs):
        profile = train_profiles[i]
        seed_offset = seed + i
        # Use lambda with default arguments to avoid late binding closure issues
        train_env_fns.append(lambda p=profile, s=seed_offset: ASDInterventionEnv(p, seed=s))

    train_env = DummyVecEnv(train_env_fns)

    # Wrap with VecNormalize for observation and reward normalization
    train_env = VecNormalize(
        train_env,
        norm_obs=True,
        norm_reward=True,
        clip_obs=10.0,
    )

    # Create evaluation environment (up to 10 test profiles)
    n_eval_envs = min(10, len(test_profiles))
    eval_env_fns = []
    for i in range(n_eval_envs):
        profile = test_profiles[i]
        seed_offset = seed + 1000 + i  # Different seed space for eval
        eval_env_fns.append(lambda p=profile, s=seed_offset: ASDInterventionEnv(p, seed=s))

    eval_env = DummyVecEnv(eval_env_fns)

    # Wrap eval env with VecNormalize (training=False to use running stats, not update them)
    eval_env = VecNormalize(
        eval_env,
        norm_obs=True,
        norm_reward=True,
        clip_obs=10.0,
        training=False,
    )

    # Create output directories
    output_path = Path(output_dir)
    checkpoint_dir = output_path / "checkpoints"
    best_model_dir = output_path / "best"
    tensorboard_dir = output_path / "tensorboard"

    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    best_model_dir.mkdir(parents=True, exist_ok=True)
    tensorboard_dir.mkdir(parents=True, exist_ok=True)

    # Create callbacks
    checkpoint_callback = CheckpointCallback(
        save_freq=config["checkpoint_freq"] // config["n_envs"],
        save_path=str(checkpoint_dir),
        name_prefix="ppo_asd",
    )

    eval_callback = EvalCallback(
        eval_env,
        best_model_save_path=str(best_model_dir),
        eval_freq=config["eval_freq"] // config["n_envs"],
        n_eval_episodes=config["n_eval_episodes"],
        deterministic=True,
    )

    callbacks = CallbackList([checkpoint_callback, eval_callback])

    # Create PPO model
    print("Creating PPO model...")
    model = PPO(
        policy="MlpPolicy",
        env=train_env,
        learning_rate=config["learning_rate"],
        n_steps=config["n_steps"],
        batch_size=config["batch_size"],
        n_epochs=config["n_epochs"],
        gamma=config["gamma"],
        gae_lambda=config["gae_lambda"],
        clip_range=config["clip_range"],
        ent_coef=config["ent_coef"],
        vf_coef=config["vf_coef"],
        max_grad_norm=config["max_grad_norm"],
        seed=config["seed"],
        tensorboard_log=str(tensorboard_dir),
        verbose=1,
    )

    # Train the model
    print(f"Starting training for {config['total_timesteps']} timesteps...")
    model.learn(
        total_timesteps=config["total_timesteps"],
        callback=callbacks,
        tb_log_name="ppo_asd",
    )

    # Save final model and normalization stats
    final_model_path = output_path / "ppo_asd_final"
    vec_normalize_path = output_path / "vec_normalize.pkl"

    print(f"Saving final model to {final_model_path}...")
    model.save(str(final_model_path))

    print(f"Saving VecNormalize stats to {vec_normalize_path}...")
    train_env.save(str(vec_normalize_path))

    print("Training complete!")
    print(f"Final model: {final_model_path}.zip")
    print(f"Best model: {best_model_dir}/best_model.zip")
    print(f"VecNormalize stats: {vec_normalize_path}")

    return str(final_model_path)
