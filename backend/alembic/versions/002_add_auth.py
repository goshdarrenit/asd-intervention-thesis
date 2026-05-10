"""Add auth columns to users and create admin_accounts table.

Revision ID: 002
Revises: 001
Create Date: 2026-02-26 10:00:00.000000

Changes:
- ALTER TABLE users ADD COLUMN email VARCHAR UNIQUE (nullable)
- ALTER TABLE users ADD COLUMN hashed_password VARCHAR (nullable)
- CREATE TABLE admin_accounts
- CREATE INDEX idx_users_email
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add email column to users (nullable for existing rows)
    op.add_column(
        "users",
        sa.Column("email", sa.String(length=255), nullable=True),
    )
    op.create_unique_constraint("uq_users_email", "users", ["email"])
    op.create_index("idx_users_email", "users", ["email"], unique=False)

    # Add hashed_password column to users (nullable for existing rows)
    op.add_column(
        "users",
        sa.Column("hashed_password", sa.String(), nullable=True),
    )

    # Create admin_accounts table
    op.create_table(
        "admin_accounts",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("email", sa.String(), unique=True, nullable=False),
        sa.Column("hashed_password", sa.String(), nullable=False),
        sa.Column(
            "is_active",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_admin_accounts")),
        sa.UniqueConstraint("email", name=op.f("uq_admin_accounts_email")),
    )


def downgrade() -> None:
    op.drop_table("admin_accounts")
    op.drop_index("idx_users_email", table_name="users")
    op.drop_constraint("uq_users_email", "users", type_="unique")
    op.drop_column("users", "hashed_password")
    op.drop_column("users", "email")
