"""PPO hyperparameter configuration for RL training.

Conservative hyperparameters for stable training.
"""

# Number of parallel environments for training
N_ENVS = 8


def get_ppo_config() -> dict:
    """Get conservative PPO hyperparameter configuration.

    These hyperparameters are designed for stable, reliable training
    following standard RL best practices

    Returns:
        Dictionary containing PPO hyperparameters:
        - learning_rate: 3e-4 (conservative learning rate)
        - n_steps: 128 (rollout buffer size per environment)
        - batch_size: 64 (minibatch size for SGD)
        - n_epochs: 3 (number of epochs when optimizing)
        - clip_range: 0.2 (PPO clipping parameter)
        - gamma: 0.99 (discount factor)
        - gae_lambda: 0.95 (GAE lambda parameter)
        - ent_coef: 0.01 (entropy coefficient for exploration)
        - vf_coef: 0.5 (value function coefficient)
        - max_grad_norm: 0.5 (gradient clipping)
        - seed: 42 (random seed for reproducibility)
        - n_envs: 8 (number of parallel environments)
        - total_timesteps: 100,000 (total training steps)
        - checkpoint_freq: 10,000 (save checkpoint every N steps)
        - eval_freq: 5,000 (evaluate every N steps)
        - n_eval_episodes: 10 (number of evaluation episodes)
    """
    return {
        "learning_rate": 3e-4,
        "n_steps": 128,
        "batch_size": 64,
        "n_epochs": 3,
        "clip_range": 0.2,
        "gamma": 0.99,
        "gae_lambda": 0.95,
        "ent_coef": 0.01,
        "vf_coef": 0.5,
        "max_grad_norm": 0.5,
        "seed": 42,
        "n_envs": N_ENVS,
        "total_timesteps": 100_000,
        "checkpoint_freq": 10_000,
        "eval_freq": 5_000,
        "n_eval_episodes": 10,
    }
