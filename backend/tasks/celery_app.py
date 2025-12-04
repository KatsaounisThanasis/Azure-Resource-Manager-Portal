"""
Celery Configuration for Async Task Processing

This module configures Celery for handling long-running deployment tasks.
"""

from celery import Celery
import os

# Redis connection
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Create Celery app
celery_app = Celery(
    "cloud_manager",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["backend.tasks.deployment_tasks"]
)

# Celery configuration
celery_app.conf.update(
    # Task settings
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,

    # Result backend settings
    result_expires=3600 * 24 * 7,  # 7 days
    result_backend_transport_options={
        "master_name": "mymaster",
        "visibility_timeout": 3600,
    },

    # Task execution settings
    task_track_started=True,
    task_time_limit=3600 * 2,  # 2 hours max
    task_soft_time_limit=3600,  # 1 hour soft limit

    # Worker settings
    worker_prefetch_multiplier=1,
    worker_max_tasks_per_child=100,

    # Retry settings
    task_acks_late=True,
    task_reject_on_worker_lost=True,

    # Routing
    # Note: Using default 'celery' queue for all tasks for simplicity
    # task_routes={
    #     "backend.tasks.deployment_tasks.deploy_infrastructure": {"queue": "deployments"},
    #     "backend.tasks.deployment_tasks.cleanup_deployment": {"queue": "maintenance"},
    # },
)

# Optional: Beat schedule for periodic tasks
celery_app.conf.beat_schedule = {
    "cleanup-old-deployments": {
        "task": "backend.tasks.deployment_tasks.cleanup_old_deployments",
        "schedule": 3600.0 * 24,  # Daily
    },
}
