"""Initial schema with all 5 tables

Revision ID: 001
Revises:
Create Date: 2026-02-09 10:00:00.000000

Creates:
- users table: Basic demographic information
- user_profiles table: Learning characteristics, JSONB state vectors
- sessions table: User session tracking
- scenario_results table: Individual scenario outcomes with RL data
- rl_training_logs table: Training metrics

Indexes:
- GIN indexes on user_profiles JSONB fields (state_vector, emotional_history)
- B-tree indexes on scenario_results for query performance
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create users table
    op.create_table('users',
    sa.Column('user_id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
    sa.Column('age', sa.Integer(), nullable=False),
    sa.Column('severity_level', sa.Integer(), nullable=False),
    sa.Column('guardian_email', sa.String(length=255), nullable=True),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('age >= 4 AND age <= 18', name='age_range'),
    sa.CheckConstraint('severity_level BETWEEN 1 AND 3', name='severity_range'),
    sa.PrimaryKeyConstraint('user_id', name=op.f('pk_users'))
    )

    # Create user_profiles table
    op.create_table('user_profiles',
    sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column('overall_success_rate', sa.Float(), server_default=sa.text('0.5'), nullable=False),
    sa.Column('scenarios_completed', sa.Integer(), server_default=sa.text('0'), nullable=False),
    sa.Column('total_session_time', sa.Integer(), server_default=sa.text('0'), nullable=False),
    sa.Column('current_difficulty', sa.Integer(), server_default=sa.text('2'), nullable=False),
    sa.Column('learning_rate', sa.Float(), server_default=sa.text('0.5'), nullable=False),
    sa.Column('frustration_tolerance', sa.Float(), server_default=sa.text('0.5'), nullable=False),
    sa.Column('preferred_scenarios', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("""'{"sharing": 0.2, "patience": 0.2, "emotion_recognition": 0.2, "turn_taking": 0.2, "conflict_resolution": 0.2}'::jsonb"""), nullable=False),
    sa.Column('last_5_scenarios', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'[]'::jsonb"), nullable=False),
    sa.Column('last_5_success_rates', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'[]'::jsonb"), nullable=False),
    sa.Column('emotional_history', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("""'{"frustration_mean": 0.3, "engagement_mean": 0.7, "confidence_mean": 0.5}'::jsonb"""), nullable=False),
    sa.Column('state_vector', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('current_difficulty BETWEEN 1 AND 5', name='difficulty_range'),
    sa.ForeignKeyConstraint(['user_id'], ['users.user_id'], name=op.f('fk_user_profiles_user_id_users')),
    sa.PrimaryKeyConstraint('user_id', name=op.f('pk_user_profiles'))
    )

    # Create GIN indexes on JSONB fields for efficient querying
    op.create_index('idx_user_profiles_state_vector', 'user_profiles', ['state_vector'], unique=False, postgresql_using='gin')
    op.create_index('idx_user_profiles_emotional_history', 'user_profiles', ['emotional_history'], unique=False, postgresql_using='gin')

    # Create sessions table
    op.create_table('sessions',
    sa.Column('session_id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
    sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column('started_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
    sa.Column('ended_at', sa.DateTime(), nullable=True),
    sa.Column('scenarios_completed', sa.Integer(), server_default=sa.text('0'), nullable=False),
    sa.Column('total_reward', sa.Float(), server_default=sa.text('0.0'), nullable=False),
    sa.Column('average_frustration', sa.Float(), nullable=True),
    sa.Column('ended_reason', sa.String(length=50), nullable=True),
    sa.ForeignKeyConstraint(['user_id'], ['users.user_id'], name=op.f('fk_sessions_user_id_users')),
    sa.PrimaryKeyConstraint('session_id', name=op.f('pk_sessions'))
    )

    # Create rl_training_logs table
    op.create_table('rl_training_logs',
    sa.Column('log_id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
    sa.Column('training_run_name', sa.String(length=100), nullable=True),
    sa.Column('episode', sa.Integer(), nullable=True),
    sa.Column('timestep', sa.Integer(), nullable=True),
    sa.Column('mean_reward', sa.Float(), nullable=True),
    sa.Column('policy_loss', sa.Float(), nullable=True),
    sa.Column('value_loss', sa.Float(), nullable=True),
    sa.Column('entropy', sa.Float(), nullable=True),
    sa.Column('timestamp', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('log_id', name=op.f('pk_rl_training_logs'))
    )

    # Create scenario_results table (depends on sessions, so created after)
    op.create_table('scenario_results',
    sa.Column('result_id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
    sa.Column('session_id', postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
    sa.Column('scenario_type', sa.String(length=50), nullable=False),
    sa.Column('difficulty', sa.Integer(), nullable=False),
    sa.Column('complexity', sa.String(length=10), nullable=False),
    sa.Column('reinforcement_mode', sa.String(length=20), nullable=False),
    sa.Column('user_choice', sa.String(length=100), nullable=True),
    sa.Column('ai_response', sa.String(length=100), nullable=True),
    sa.Column('outcome_type', sa.String(length=50), nullable=True),
    sa.Column('decision_time_ms', sa.Integer(), nullable=True),
    sa.Column('num_pauses', sa.Integer(), server_default=sa.text('0'), nullable=False),
    sa.Column('num_retries', sa.Integer(), server_default=sa.text('0'), nullable=False),
    sa.Column('completed', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('quit_early', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('emotions', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('state_vector', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('action_taken', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('reward', sa.Float(), nullable=True),
    sa.Column('next_state_vector', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('timestamp', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['session_id'], ['sessions.session_id'], name=op.f('fk_scenario_results_session_id_sessions')),
    sa.ForeignKeyConstraint(['user_id'], ['users.user_id'], name=op.f('fk_scenario_results_user_id_users')),
    sa.PrimaryKeyConstraint('result_id', name=op.f('pk_scenario_results'))
    )

    op.create_index('idx_scenario_user', 'scenario_results', ['user_id'], unique=False)
    op.create_index('idx_scenario_session', 'scenario_results', ['session_id'], unique=False)
    op.create_index('idx_scenario_type', 'scenario_results', ['scenario_type'], unique=False)
    op.create_index('idx_scenario_timestamp', 'scenario_results', ['timestamp'], unique=False)


def downgrade() -> None:
    # Drop tables in reverse order to handle foreign key dependencies
    op.drop_index('idx_scenario_timestamp', table_name='scenario_results')
    op.drop_index('idx_scenario_type', table_name='scenario_results')
    op.drop_index('idx_scenario_session', table_name='scenario_results')
    op.drop_index('idx_scenario_user', table_name='scenario_results')
    op.drop_table('scenario_results')
    op.drop_table('rl_training_logs')
    op.drop_table('sessions')
    op.drop_index('idx_user_profiles_emotional_history', table_name='user_profiles', postgresql_using='gin')
    op.drop_index('idx_user_profiles_state_vector', table_name='user_profiles', postgresql_using='gin')
    op.drop_table('user_profiles')
    op.drop_table('users')
