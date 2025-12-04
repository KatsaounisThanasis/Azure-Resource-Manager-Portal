"""
Celery Tasks for Async Infrastructure Deployment

This module contains all background tasks for infrastructure deployment and management.
"""

from celery import Task
from backend.tasks.celery_app import celery_app
from backend.core.database import SessionLocal, Deployment, DeploymentStatus, TerraformState
from backend.providers.factory import ProviderFactory
from backend.providers.base import DeploymentError, ProviderConfigurationError
from backend.services.state_backend_manager import StateBackendManager
from datetime import datetime
import logging
import traceback
import uuid
import json

logger = logging.getLogger(__name__)


def log_entry(level: str, message: str, phase: str = None, details: dict = None) -> str:
    """
    Create a structured log entry with timestamp, level, phase, and message.

    Args:
        level: Log level (INFO, WARNING, ERROR, DEBUG)
        message: Log message
        phase: Current deployment phase (optional)
        details: Additional structured data (optional)

    Returns:
        Formatted log entry string
    """
    timestamp = datetime.utcnow().isoformat()

    # Build log entry
    log_parts = [f"[{timestamp}]", f"[{level}]"]

    if phase:
        log_parts.append(f"[{phase.upper()}]")

    log_parts.append(message)

    # Add details as JSON if provided
    if details:
        log_parts.append(f"- {json.dumps(details)}")

    return " ".join(log_parts) + "\n"


class DatabaseTask(Task):
    """Base task with database session management"""
    _db = None

    @property
    def db(self):
        if self._db is None:
            self._db = SessionLocal()
        return self._db

    def after_return(self, *args, **kwargs):
        if self._db is not None:
            self._db.close()
            self._db = None


@celery_app.task(bind=True, base=DatabaseTask, name="backend.tasks.deploy_infrastructure")
def deploy_infrastructure(
    self,
    deployment_id: str,
    provider_type: str,
    template_path: str,
    parameters: dict,
    resource_group: str = None,
    provider_config: dict = None
):
    """
    Deploy infrastructure asynchronously

    Args:
        deployment_id: Unique deployment identifier
        provider_type: Provider type (azure, terraform-aws, terraform-gcp, etc.)
        template_path: Path to template file
        parameters: Template parameters
        resource_group: Resource group name (for Azure)
        provider_config: Additional provider configuration (credentials, regions, etc.)

    Returns:
        dict: Deployment result with status and outputs
    """
    db = self.db
    deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()

    try:
        # Update deployment status to RUNNING
        if deployment:
            deployment.status = DeploymentStatus.RUNNING
            deployment.started_at = datetime.utcnow()
            deployment.celery_task_id = self.request.id
            deployment.logs = log_entry("INFO", f"Starting deployment {deployment_id}", phase="initialization")
            db.commit()

        logger.info(f"Starting deployment {deployment_id} with provider {provider_type}")

        # Update task state
        self.update_state(
            state="RUNNING",
            meta={
                "deployment_id": deployment_id,
                "status": "initializing",
                "progress": 10
            }
        )

        # Create provider instance
        # Map template format to cloud provider type
        provider_type_mapping = {
            "bicep": "azure",
            "arm": "azure",
            "terraform-azure": "terraform-azure",
            "terraform-aws": "terraform-aws",
            "terraform-gcp": "terraform-gcp"
        }
        actual_provider_type = provider_type_mapping.get(provider_type, provider_type)

        # Append log
        if deployment:
            deployment.logs += log_entry("INFO", f"Initializing {actual_provider_type} provider", phase="initialization")
            db.commit()

        provider_config = provider_config or {}
        provider = ProviderFactory.create_provider(actual_provider_type, **provider_config)

        logger.info(f"Provider {provider_type} initialized for deployment {deployment_id}")

        # Append log
        if deployment:
            deployment.logs += log_entry("INFO", "Provider initialized successfully", phase="initialization")
            db.commit()

        # Get location/region from provider_config
        location = provider_config.get("region", "us-east-1")

        # Append log
        if deployment:
            deployment.logs += log_entry("INFO", f"Starting deployment to {location}", phase="initialization",
                                        details={"location": location, "resource_group": resource_group})
            deployment.logs += log_entry("INFO", f"Resource group: {resource_group}", phase="initialization")
            deployment.logs += log_entry("INFO", f"Template: {template_path}", phase="initialization")
            db.commit()

        # PHASE 1: Validation
        self.update_state(
            state="RUNNING",
            meta={
                "deployment_id": deployment_id,
                "phase": "validating",
                "status": "Validating template configuration",
                "progress": 25
            }
        )
        if deployment:
            deployment.logs += "\n" + log_entry("INFO", "=== PHASE 1: VALIDATION ===", phase="validating")
            deployment.logs += log_entry("INFO", "Validating template syntax and parameters...", phase="validating")
            db.commit()

        # PHASE 2: Planning
        self.update_state(
            state="RUNNING",
            meta={
                "deployment_id": deployment_id,
                "phase": "planning",
                "status": "Generating execution plan",
                "progress": 40
            }
        )
        if deployment:
            deployment.logs += "\n" + log_entry("INFO", "=== PHASE 2: PLANNING ===", phase="planning")
            deployment.logs += log_entry("INFO", "Calculating infrastructure changes...", phase="planning")
            db.commit()

        # PHASE 3: Applying
        self.update_state(
            state="RUNNING",
            meta={
                "deployment_id": deployment_id,
                "phase": "applying",
                "status": "Applying infrastructure changes",
                "progress": 60
            }
        )
        if deployment:
            deployment.logs += "\n" + log_entry("INFO", "=== PHASE 3: APPLYING ===", phase="applying")
            deployment.logs += log_entry("INFO", "Provisioning cloud resources...", phase="applying")
            db.commit()

        # Merge provider_config values into parameters for Terraform
        # Terraform templates expect these as variables
        deployment_parameters = parameters.copy()
        
        # Provider-specific parameter handling
        if "azure" in actual_provider_type:
            deployment_parameters['subscription_id'] = provider_config.get('subscription_id')
            deployment_parameters['resource_group_name'] = resource_group
        
        elif "gcp" in actual_provider_type:
            # GCP uses 'labels' instead of 'tags'
            if 'tags' in deployment_parameters:
                deployment_parameters['labels'] = deployment_parameters.pop('tags')
            
            # Handle project_id (camelCase from frontend vs snake_case for Terraform)
            if 'projectId' in deployment_parameters and 'project_id' not in deployment_parameters:
                deployment_parameters['project_id'] = deployment_parameters.pop('projectId')
            
            # If project_id is still missing, try to get it from provider_config
            if 'project_id' not in deployment_parameters and 'project_id' in provider_config:
                deployment_parameters['project_id'] = provider_config['project_id']

            # Ensure we don't send resource_group_name to GCP
            if 'resource_group_name' in deployment_parameters:
                del deployment_parameters['resource_group_name']

        deployment_parameters['location'] = location

        logger.info(f"Deployment parameters (including merged values): {deployment_parameters}")

        # Use asyncio to run the async deploy method
        import asyncio
        result = asyncio.run(provider.deploy(
            template_path=template_path,
            resource_group=resource_group,
            parameters=deployment_parameters,
            location=location,
            deployment_id=deployment_id  # Pass deployment_id for remote state
        ))

        logger.info(f"Deployment {deployment_id} completed successfully")

        # Append log
        if deployment:
            deployment.logs += log_entry("INFO", "Deployment execution completed", phase="applying")
            db.commit()

        # PHASE 4: Finalizing
        self.update_state(
            state="RUNNING",
            meta={
                "deployment_id": deployment_id,
                "phase": "finalizing",
                "status": "Retrieving outputs and finalizing",
                "progress": 90
            }
        )
        if deployment:
            deployment.logs += "\n" + log_entry("INFO", "=== PHASE 4: FINALIZING ===", phase="finalizing")
            deployment.logs += log_entry("INFO", "Collecting deployment outputs...", phase="finalizing")
            db.commit()

        # Update deployment record
        if deployment:
            deployment.status = DeploymentStatus.COMPLETED
            deployment.completed_at = datetime.utcnow()
            deployment.outputs = result.outputs if hasattr(result, 'outputs') else {}
            deployment.logs += log_entry("INFO", "✓ Deployment completed successfully", phase="completed")
            if hasattr(result, 'outputs') and result.outputs:
                deployment.logs += log_entry("INFO", "Outputs collected", phase="completed",
                                             details={"output_count": len(result.outputs)})
            db.commit()

        logger.info(f"Deployment {deployment_id} recorded as completed")

        # Update final task state
        self.update_state(
            state="SUCCESS",
            meta={
                "deployment_id": deployment_id,
                "phase": "completed",
                "status": "Deployment completed successfully",
                "progress": 100
            }
        )

        return {
            "deployment_id": deployment_id,
            "status": "completed",
            "phase": "completed",
            "outputs": result.outputs if hasattr(result, 'outputs') else {},
            "message": "Deployment completed successfully"
        }

    except (DeploymentError, ProviderConfigurationError) as e:
        logger.error(f"Deployment {deployment_id} failed: {str(e)}")

        # Update deployment record with error
        if deployment:
            deployment.status = DeploymentStatus.FAILED
            deployment.completed_at = datetime.utcnow()
            deployment.error_message = str(e)
            deployment.logs += "\n" + log_entry("ERROR", "✗ Deployment failed", phase="failed",
                                               details={"error_type": type(e).__name__})
            deployment.logs += log_entry("ERROR", str(e), phase="failed")
            deployment.logs += f"\n--- Full Traceback ---\n{traceback.format_exc()}"
            db.commit()

        # Update task state
        self.update_state(
            state="FAILURE",
            meta={
                "deployment_id": deployment_id,
                "phase": "failed",
                "error": str(e),
                "traceback": traceback.format_exc()
            }
        )

        raise

    except Exception as e:
        logger.error(f"Unexpected error in deployment {deployment_id}: {str(e)}")

        # Update deployment record
        if deployment:
            deployment.status = DeploymentStatus.FAILED
            deployment.completed_at = datetime.utcnow()
            deployment.error_message = f"Unexpected error: {str(e)}"
            deployment.logs += "\n" + log_entry("ERROR", "✗ Unexpected error occurred", phase="failed",
                                               details={"error_type": type(e).__name__})
            deployment.logs += log_entry("ERROR", f"Error: {str(e)}", phase="failed")
            deployment.logs += f"\n--- Full Traceback ---\n{traceback.format_exc()}"
            db.commit()

        # Update task state
        self.update_state(
            state="FAILURE",
            meta={
                "deployment_id": deployment_id,
                "phase": "failed",
                "error": str(e),
                "traceback": traceback.format_exc()
            }
        )

        raise


@celery_app.task(name="backend.tasks.cleanup_deployment")
def cleanup_deployment(deployment_id: str):
    """
    Clean up deployment resources

    Args:
        deployment_id: Deployment ID to clean up
    """
    db = SessionLocal()
    try:
        deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()
        if not deployment:
            logger.warning(f"Deployment {deployment_id} not found for cleanup")
            return

        logger.info(f"Cleaning up deployment {deployment_id}")

        # Clean up Terraform state if applicable
        if deployment.provider_type.startswith("terraform"):
            tf_state = db.query(TerraformState).filter_by(deployment_id=deployment_id).first()
            if tf_state:
                # Here you could add logic to clean up remote state
                logger.info(f"Terraform state found for {deployment_id}")

        # Mark as cleaned up (you might want a separate status for this)
        logger.info(f"Cleanup completed for deployment {deployment_id}")

    finally:
        db.close()


@celery_app.task(name="backend.tasks.cleanup_old_deployments")
def cleanup_old_deployments(days: int = 30):
    """
    Periodic task to clean up old deployments

    Args:
        days: Number of days to keep deployments
    """
    from datetime import timedelta

    db = SessionLocal()
    try:
        cutoff_date = datetime.utcnow() - timedelta(days=days)

        old_deployments = db.query(Deployment).filter(
            Deployment.completed_at < cutoff_date,
            Deployment.status.in_([DeploymentStatus.COMPLETED, DeploymentStatus.FAILED])
        ).all()

        logger.info(f"Found {len(old_deployments)} old deployments to clean up")

        for deployment in old_deployments:
            # Optionally delete or archive
            logger.info(f"Archiving old deployment {deployment.deployment_id}")

        db.commit()

    finally:
        db.close()


@celery_app.task(bind=True, name="backend.tasks.get_deployment_status")
def get_deployment_status(self, deployment_id: str):
    """
    Get deployment status

    Args:
        deployment_id: Deployment ID to check

    Returns:
        dict: Deployment status information
    """
    db = SessionLocal()
    try:
        deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()

        if not deployment:
            return {
                "deployment_id": deployment_id,
                "status": "not_found",
                "error": "Deployment not found"
            }

        return deployment.to_dict()

    finally:
        db.close()
