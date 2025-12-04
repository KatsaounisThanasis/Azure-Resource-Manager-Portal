"""
Database Models and Configuration for Multi-Cloud Infrastructure Management

This module defines the database schema for tracking deployments, state, and history.
"""

from sqlalchemy import create_engine, Column, String, DateTime, Text, JSON, Enum as SQLEnum
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime
import enum
import os

# Database URL from environment or default to SQLite for development
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/cloud_manager"
)

# For SQLite fallback in development
if not DATABASE_URL.startswith("postgresql"):
    DATABASE_URL = "sqlite:///./cloud_manager.db"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class DeploymentStatus(str, enum.Enum):
    """Deployment status enumeration"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Deployment(Base):
    """
    Deployment tracking model

    Stores information about infrastructure deployments across all cloud providers.
    """
    __tablename__ = "deployments"

    # Primary key
    deployment_id = Column(String(50), primary_key=True, index=True)

    # Deployment metadata
    provider_type = Column(String(50), nullable=False, index=True)
    cloud_provider = Column(String(20), nullable=False, index=True)
    template_name = Column(String(200), nullable=False)
    resource_group = Column(String(200), nullable=True, index=True)

    # Status tracking
    status = Column(SQLEnum(DeploymentStatus), default=DeploymentStatus.PENDING, index=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    # Deployment data
    parameters = Column(JSON, nullable=True)
    outputs = Column(JSON, nullable=True)

    # Tags for organization and filtering
    tags = Column(JSON, nullable=True, default=list)  # List of tag strings

    # State and logs
    state_location = Column(String(500), nullable=True)  # For Terraform state
    error_message = Column(Text, nullable=True)
    logs = Column(Text, nullable=True)

    # Celery task tracking
    celery_task_id = Column(String(100), nullable=True, index=True)

    def to_dict(self):
        """Convert to dictionary for API responses"""
        return {
            "deployment_id": self.deployment_id,
            "provider_type": self.provider_type,
            "cloud_provider": self.cloud_provider,
            "template_name": self.template_name,
            "resource_group": self.resource_group,
            "status": self.status.value if isinstance(self.status, DeploymentStatus) else self.status,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "parameters": self.parameters,
            "outputs": self.outputs,
            "tags": self.tags or [],
            "error_message": self.error_message,
            "celery_task_id": self.celery_task_id
        }


class TerraformState(Base):
    """
    Terraform state tracking

    Stores metadata about Terraform state files for state management.
    """
    __tablename__ = "terraform_states"

    # Primary key - links to deployment
    deployment_id = Column(String(50), primary_key=True, index=True)

    # State backend configuration
    backend_type = Column(String(20), nullable=False)  # s3, azurerm, gcs
    backend_config = Column(JSON, nullable=False)

    # State metadata
    state_version = Column(String(20), nullable=True)
    last_modified = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Workspace info
    workspace = Column(String(100), default="default", nullable=False)

    def to_dict(self):
        """Convert to dictionary for API responses"""
        return {
            "deployment_id": self.deployment_id,
            "backend_type": self.backend_type,
            "backend_config": self.backend_config,
            "state_version": self.state_version,
            "last_modified": self.last_modified.isoformat() if self.last_modified else None,
            "workspace": self.workspace
        }


def get_db():
    """
    Database session dependency for FastAPI

    Usage in FastAPI endpoints:
        @app.get("/deployments")
        def get_deployments(db: Session = Depends(get_db)):
            return db.query(Deployment).all()
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Initialize database tables"""
    Base.metadata.create_all(bind=engine)


def drop_all():
    """Drop all tables (use with caution!)"""
    Base.metadata.drop_all(bind=engine)
