"""Generate diverse synthetic user profiles for RL training.

50 profiles (40 train, 10 test) with varied characteristics.
"""
import json
import pickle
from pathlib import Path

import numpy as np

from app.synthetic_users.profile import SyntheticUserProfile


def generate_profiles(n_train: int = 40, n_test: int = 10, seed: int = 42) -> list[SyntheticUserProfile]:
    """Generate diverse synthetic user profiles with reproducible randomness.

    Args:
        n_train: Number of training profiles (default 40)
        n_test: Number of test profiles (default 10)
        seed: Random seed for reproducibility (default 42)

    Returns:
        List of SyntheticUserProfile objects
    """
    rng = np.random.default_rng(seed)
    n_total = n_train + n_test
    profiles = []

    for i in range(n_total):
        # Determine split
        split = "train" if i < n_train else "test"

        # Generate diverse characteristics using uniform distributions
        age = rng.uniform(6.0, 12.0)
        severity = rng.choice([1, 2, 3])
        learning_rate = rng.uniform(0.1, 1.0)
        frustration_tolerance = rng.uniform(0.1, 1.0)

        # Behavioral parameters
        avg_decision_time = rng.uniform(1.0, 10.0)
        pause_probability = rng.uniform(0.0, 0.3)
        retry_probability = rng.uniform(0.3, 0.9)

        profile = SyntheticUserProfile(
            id=f"user_{i:03d}",
            split=split,
            age=age,
            severity=severity,
            learning_rate=learning_rate,
            frustration_tolerance=frustration_tolerance,
            avg_decision_time=avg_decision_time,
            pause_probability=pause_probability,
            retry_probability=retry_probability,
        )
        profiles.append(profile)

    return profiles


def save_profiles(profiles: list[SyntheticUserProfile], data_dir: str = "data/synthetic_users"):
    """Save profiles to .pkl files and create manifest.

    Args:
        profiles: List of SyntheticUserProfile objects
        data_dir: Base directory for saving profiles (default "data/synthetic_users")
    """
    data_path = Path(data_dir)
    train_dir = data_path / "train"
    test_dir = data_path / "test"

    # Create directories
    train_dir.mkdir(parents=True, exist_ok=True)
    test_dir.mkdir(parents=True, exist_ok=True)

    # Save each profile
    manifest = []
    for profile in profiles:
        # Determine output directory
        output_dir = train_dir if profile.split == "train" else test_dir
        output_path = output_dir / f"{profile.id}.pkl"

        # Save as pickle
        with open(output_path, "wb") as f:
            pickle.dump(profile, f)

        # Add to manifest (convert numpy types to Python native types)
        manifest.append({
            "id": profile.id,
            "split": profile.split,
            "age": float(profile.age),
            "severity": int(profile.severity),
        })

    # Save manifest
    manifest_path = data_path / "manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"Saved {len(profiles)} profiles to {data_dir}")
    print(f"Train: {sum(1 for p in profiles if p.split == 'train')}")
    print(f"Test: {sum(1 for p in profiles if p.split == 'test')}")


def load_profile(profile_id: str, data_dir: str = "data/synthetic_users", split: str = "train") -> SyntheticUserProfile:
    """Load a single profile by ID.

    Args:
        profile_id: Profile ID (e.g., "user_000")
        data_dir: Base directory for profiles
        split: Dataset split ("train" or "test")

    Returns:
        SyntheticUserProfile object
    """
    data_path = Path(data_dir) / split / f"{profile_id}.pkl"
    with open(data_path, "rb") as f:
        return pickle.load(f)


def load_all_profiles(data_dir: str = "data/synthetic_users", split: str = "train") -> list[SyntheticUserProfile]:
    """Load all profiles from a split.

    Args:
        data_dir: Base directory for profiles
        split: Dataset split ("train" or "test")

    Returns:
        List of SyntheticUserProfile objects
    """
    data_path = Path(data_dir) / split
    profiles = []
    for pkl_file in sorted(data_path.glob("*.pkl")):
        with open(pkl_file, "rb") as f:
            profiles.append(pickle.load(f))
    return profiles


if __name__ == "__main__":
    # Generate and save profiles
    profiles = generate_profiles(n_train=40, n_test=10, seed=42)
    save_profiles(profiles)
    print(f"Generated {len(profiles)} profiles")
