"""
Production-Ready REST API for Multi-Cloud Infrastructure Management

This is the main REST API application with proper structure,
documentation, and production-ready features.
"""

from fastapi import FastAPI, HTTPException, Query, Depends, status, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from typing import Dict, Any, Optional, List
import os
import logging
from datetime import datetime
import asyncio
import json

# Import our provider abstraction
from backend.providers import get_provider, ProviderFactory, ProviderType
from backend.providers.base import DeploymentError, ProviderConfigurationError, DeploymentStatus
from backend.services.template_manager import TemplateManager

# Import database and tasks
from backend.core.database import get_db, init_db, Deployment, DeploymentStatus as DBDeploymentStatus, DATABASE_URL
from backend.tasks.deployment_tasks import deploy_infrastructure as deploy_task, get_deployment_status as get_status_task
from sqlalchemy.orm import Session
from sqlalchemy import text
import uuid

# Import security and authentication
from backend.core.auth import (
    UserCreate, UserLogin, UserResponse, TokenResponse, UserUpdate,
    UserRole, create_user, authenticate_user, get_current_user as get_jwt_user,
    create_access_token, get_all_users, update_user, delete_user,
    has_permission, initialize_default_users
)
from backend.core.security import (
    SecurityHeadersMiddleware,
    RequestLoggingMiddleware,
    get_cors_config,
    get_trusted_hosts,
    validate_deployment_parameters,
    mask_sensitive_data,
    security_config
)

# Import parameter parser
from backend.services.parameter_parser import TemplateParameterParser

# Import cost estimator
from backend.core.cost_estimator import estimate_deployment_cost

# Import exceptions
from backend.core.exceptions import (
    MultiCloudException,
    TemplateNotFoundError,
    DeploymentNotFoundError,
    ProviderNotFoundError,
    AuthenticationError,
    ValidationError,
    InvalidParameterError,
    MissingParameterError,
    InternalServerError
)

# Import validators
from backend.utils.validators import DeploymentRequestValidator, ParameterValidator

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI with metadata
app = FastAPI(
    title="Multi-Cloud Infrastructure Management API",
    description="""
    Production-ready REST API for deploying and managing cloud infrastructure
    across Azure and Google Cloud Platform.

    ## Features
    * **Multi-Cloud Support**: Deploy to Azure or GCP with one API
    * **Multiple Formats**: Bicep for Azure, Terraform for GCP
    * **Provider Abstraction**: Unified interface across clouds
    * **Template Management**: Automatic template discovery
    * **Real-time Status**: Track deployment progress
    * **Async Deployments**: Background task processing with Celery
    * **Persistent State**: PostgreSQL database and Terraform remote state
    * **Security**: API key authentication, rate limiting, security headers

    ## Authentication
    API key authentication is available for production use.
    Set `API_AUTH_ENABLED=true` and provide `API_KEY` environment variable.

    Include the API key in request headers:
    ```
    X-API-Key: your-api-key-here
    ```

    For cloud operations, cloud provider credentials are required:
    - **Azure**: Azure CLI authentication (`az login`) or service principal
    - **GCP**: Service account JSON key file or gcloud CLI authentication
    """,
    version="3.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
    contact={
        "name": "GitHub Repository",
        "url": "https://github.com/KatsaounisThanasis/Azure-Resource-Manager-Portal"
    },
    license_info={
        "name": "MIT License",
        "url": "https://opensource.org/licenses/MIT"
    }
)

# Security Middleware (order matters - applied in reverse order)
# 1. Security Headers (applied last to all responses)
app.add_middleware(SecurityHeadersMiddleware)

# 2. Request Logging (applied second)
app.add_middleware(RequestLoggingMiddleware)

# 3. CORS configuration (applied first)
cors_config = get_cors_config()
app.add_middleware(CORSMiddleware, **cors_config)


# ================================================================
# Global Exception Handlers
# ================================================================

@app.exception_handler(MultiCloudException)
async def multicloud_exception_handler(request: Request, exc: MultiCloudException):
    """
    Handle all MultiCloudException instances with consistent format.
    """
    logger.error(f"MultiCloudException: {exc.code} - {exc.message}", exc_info=True)
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "success": False,
            "message": exc.message,
            "error": exc.to_dict(),
            "timestamp": datetime.utcnow().isoformat()
        }
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """
    Handle FastAPI HTTPException with consistent format.
    """
    logger.warning(f"HTTPException: {exc.status_code} - {exc.detail}")
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "success": False,
            "message": exc.detail,
            "error": {
                "code": f"HTTP_{exc.status_code}",
                "message": exc.detail
            },
            "timestamp": datetime.utcnow().isoformat()
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """
    Catch-all handler for unexpected exceptions.
    """
    logger.exception(f"Unhandled exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "message": "An unexpected error occurred",
            "error": {
                "code": "INTERNAL_SERVER_ERROR",
                "message": "An unexpected error occurred",
                "details": str(exc) if os.getenv("ENVIRONMENT") == "development" else None
            },
            "timestamp": datetime.utcnow().isoformat()
        }
    )


# Initialize Template Manager
TEMPLATES_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "templates"))
template_manager = TemplateManager(TEMPLATES_DIR)

# Initialize database on startup
@app.on_event("startup")
async def startup_event():
    """Initialize database tables and log startup info"""
    init_db()
    logger.info("Database initialized")
    logger.info(f"API v3.0.0 starting in {security_config.environment} mode")
    logger.info(f"Authentication: {'Enabled' if security_config.auth_enabled else 'Disabled (Development)'}")
    logger.info(f"Rate Limiting: {'Enabled' if security_config.rate_limit_enabled else 'Disabled'}")

    # Initialize default users for RBAC
    initialize_default_users()

# ==================== Request/Response Models ====================

class StandardResponse(BaseModel):
    """Standard API response format."""
    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None
    error: Optional[Dict[str, Any]] = None
    timestamp: str = Field(default_factory=lambda: datetime.utcnow().isoformat())


class DeploymentRequest(BaseModel):
    """Request model for deployments."""
    template_name: str = Field(..., description="Name of the template to deploy")
    provider_type: str = Field(..., description="Cloud provider: 'azure' or 'gcp'")
    subscription_id: Optional[str] = Field(None, description="Cloud subscription/account/project ID (auto-populated from env if not provided)")
    resource_group: str = Field(..., description="Resource group/stack name")
    location: str = Field(..., description="Deployment region/location")
    parameters: Dict[str, Any] = Field(default_factory=dict, description="Template parameters")
    tags: List[str] = Field(default_factory=list, description="Tags for organizing deployments")

    class Config:
        json_schema_extra = {
            "example": {
                "template_name": "storage-bucket",
                "provider_type": "gcp",
                "subscription_id": "my-gcp-project-id",
                "resource_group": "my-resources",
                "location": "us-central1",
                "parameters": {
                    "bucket_name": "my-unique-bucket-name"
                }
            }
        }


class ResourceGroupCreateRequest(BaseModel):
    """Request model for creating resource groups."""
    name: str = Field(..., description="Resource group/stack name")
    location: str = Field(..., description="Region/location")
    subscription_id: str = Field(..., description="Subscription/account/project ID")
    provider_type: str = Field(default="azure", description="Cloud provider")
    tags: Optional[Dict[str, str]] = Field(default=None, description="Tags/labels")


# ==================== Helper Functions ====================

def create_success_response(message: str, data: Any = None) -> StandardResponse:
    """Create standardized success response."""
    return StandardResponse(
        success=True,
        message=message,
        data=data if isinstance(data, dict) else {"result": data}
    )


def create_error_response(message: str, details: Any = None, status_code: int = 500) -> JSONResponse:
    """Create standardized error response."""
    response = StandardResponse(
        success=False,
        message=message,
        error={"details": details, "status_code": status_code}
    )
    return JSONResponse(
        status_code=status_code,
        content=response.dict()
    )


# ==================== API Endpoints ====================

# ==================== Authentication & User Management Endpoints ====================

@app.post("/auth/register",
    summary="Register New User",
    response_model=StandardResponse,
    tags=["Authentication"],
    status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate):
    """
    Register a new user account.

    - **email**: Valid email address (unique)
    - **password**: Password (min 6 characters)
    - **username**: Display name
    - **role**: User role (admin, user, viewer) - defaults to 'user'

    Returns user information and success message.
    """
    try:
        user = create_user(user_data)
        return create_success_response(
            message=f"User '{user.username}' registered successfully",
            data={"user": user.dict()}
        )
    except HTTPException as e:
        raise e
    except Exception as e:
        logger.error(f"Registration error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/auth/login",
    summary="Login",
    response_model=StandardResponse,
    tags=["Authentication"])
async def login(credentials: UserLogin):
    """
    Authenticate user and get access token.

    - **email**: User email
    - **password**: User password

    Returns JWT access token and user information.
    """
    user = authenticate_user(credentials.email, credentials.password)

    if not user:
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password"
        )

    # Create access token
    access_token = create_access_token(data={"sub": user['email']})

    # Get user permissions based on role
    from backend.core.auth import ROLE_PERMISSIONS
    user_permissions = ROLE_PERMISSIONS.get(user['role'], [])

    # Prepare user data (without password hash)
    user_data = {
        "id": user['id'],
        "email": user['email'],
        "username": user['username'],
        "role": user['role'],
        "permissions": user_permissions
    }

    return create_success_response(
        message="Login successful",
        data={
            "access_token": access_token,
            "token_type": "bearer",
            "user": user_data
        }
    )


@app.get("/auth/me",
    summary="Get Current User",
    response_model=StandardResponse,
    tags=["Authentication"])
async def get_me(current_user: dict = Depends(get_jwt_user)):
    """
    Get current authenticated user information.

    Requires valid JWT token in Authorization header:
    `Authorization: Bearer <token>`
    """
    user_data = {
        "id": current_user['id'],
        "email": current_user['email'],
        "username": current_user['username'],
        "role": current_user['role'],
        "created_at": current_user['created_at'].isoformat()
    }

    permissions = []
    if has_permission(current_user, 'read'):
        permissions.append('read')
    if has_permission(current_user, 'write'):
        permissions.append('write')
    if has_permission(current_user, 'delete'):
        permissions.append('delete')
    if has_permission(current_user, 'manage_users'):
        permissions.append('manage_users')

    return create_success_response(
        message="User information retrieved",
        data={
            "user": user_data,
            "permissions": permissions
        }
    )


@app.get("/auth/users",
    summary="List All Users",
    response_model=StandardResponse,
    tags=["Authentication", "Admin"])
async def list_users(current_user: dict = Depends(get_jwt_user)):
    """
    List all registered users.

    **Admin only** - Requires 'manage_users' permission.
    """
    if not has_permission(current_user, 'manage_users'):
        raise HTTPException(
            status_code=403,
            detail="Access denied. Admin privileges required."
        )

    users = get_all_users()

    return create_success_response(
        message=f"Retrieved {len(users)} users",
        data={
            "users": [u.dict() for u in users],
            "total": len(users)
        }
    )


@app.put("/auth/users/{email}",
    summary="Update User",
    response_model=StandardResponse,
    tags=["Authentication", "Admin"])
async def update_user_endpoint(
    email: str,
    update_data: UserUpdate,
    current_user: dict = Depends(get_jwt_user)
):
    """
    Update user information.

    **Admin only** - Requires 'manage_users' permission.
    Users can also update their own information.
    """
    # Check if user is updating themselves or is admin
    is_self = current_user['email'] == email
    is_admin = has_permission(current_user, 'manage_users')

    if not is_self and not is_admin:
        raise HTTPException(
            status_code=403,
            detail="Access denied. You can only update your own profile or need admin privileges."
        )

    # Only admins can change roles
    if update_data.role and not is_admin:
        raise HTTPException(
            status_code=403,
            detail="Only admins can change user roles"
        )

    try:
        updated_user = update_user(email, update_data)
        return create_success_response(
            message=f"User '{updated_user.username}' updated successfully",
            data={"user": updated_user.dict()}
        )
    except HTTPException as e:
        raise e
    except Exception as e:
        logger.error(f"Error updating user: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/auth/users/{email}",
    summary="Delete User",
    response_model=StandardResponse,
    tags=["Authentication", "Admin"])
async def delete_user_endpoint(
    email: str,
    current_user: dict = Depends(get_jwt_user)
):
    """
    Delete a user account.

    **Admin only** - Requires 'manage_users' permission.
    """
    if not has_permission(current_user, 'manage_users'):
        raise HTTPException(
            status_code=403,
            detail="Access denied. Admin privileges required."
        )

    # Prevent deleting yourself
    if current_user['email'] == email:
        raise HTTPException(
            status_code=400,
            detail="Cannot delete your own account"
        )

    success = delete_user(email)

    if not success:
        raise HTTPException(status_code=404, detail="User not found")

    return create_success_response(
        message=f"User '{email}' deleted successfully",
        data={"deleted_email": email}
    )


# ==================== Main API Endpoints ====================

@app.get("/",
    summary="API Health Check",
    response_model=StandardResponse,
    tags=["Health"])
async def root():
    """
    Health check endpoint to verify API is running.

    Returns basic information about the API and available providers.
    """
    return create_success_response(
        message="Multi-Cloud Infrastructure Management API is running",
        data={
            "version": "3.0.0",
            "status": "healthy",
            "environment": security_config.environment,
            "authentication_enabled": security_config.auth_enabled,
            "rate_limiting_enabled": security_config.rate_limit_enabled,
            "available_providers": ProviderFactory.get_available_providers(),
            "docs_url": "/docs"
        }
    )


@app.get("/health",
    summary="Detailed Health Status",
    response_model=StandardResponse,
    tags=["Health"])
async def health_check(db: Session = Depends(get_db)):
    """
    Comprehensive health check with system status, database, and Celery connectivity.

    Returns:
    - API version and status
    - Database connectivity
    - Celery worker status
    - Provider and template information
    - Security configuration
    """
    health_data = {
        "api_version": "3.0.0",
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "providers": template_manager.get_providers_summary(),
        "security": {
            "authentication": security_config.auth_enabled,
            "rate_limiting": security_config.rate_limit_enabled,
            "environment": security_config.environment
        }
    }

    # Check database connectivity
    try:
        db.execute(text("SELECT 1"))
        health_data["database"] = {"status": "connected", "message": "Database is accessible"}
    except Exception as e:
        health_data["database"] = {"status": "error", "message": str(e)}
        health_data["status"] = "degraded"

    # Check Celery worker status
    try:
        from backend.tasks.celery_app import celery_app
        inspect = celery_app.control.inspect()
        active_workers = inspect.active()

        if active_workers:
            worker_count = len(active_workers)
            health_data["celery"] = {
                "status": "connected",
                "workers": worker_count,
                "message": f"{worker_count} worker(s) active"
            }
        else:
            health_data["celery"] = {
                "status": "warning",
                "workers": 0,
                "message": "No active workers detected"
            }
            health_data["status"] = "degraded"
    except Exception as e:
        health_data["celery"] = {"status": "error", "message": str(e)}
        health_data["status"] = "degraded"

    return create_success_response(
        message=f"System {health_data['status']}",
        data=health_data
    )


@app.get("/providers",
    summary="List Cloud Providers",
    response_model=StandardResponse,
    tags=["Providers"])
async def list_providers():
    """
    Get list of available cloud providers with template counts.

    Returns information about each supported cloud provider including:
    - Provider ID and name
    - Supported format (Bicep, Terraform)
    - Cloud platform (Azure, GCP)
    - Number of available templates
    """
    providers_info = template_manager.get_providers_summary()
    return create_success_response(
        message=f"Found {len(providers_info['providers'])} providers",
        data=providers_info
    )


@app.get("/templates",
    summary="List Templates",
    response_model=StandardResponse,
    tags=["Templates"])
async def list_templates(
    provider_type: Optional[str] = Query(None, description="Filter by provider type"),
    cloud: Optional[str] = Query(None, description="Filter by cloud (azure, gcp)")
):
    """
    List available deployment templates.

    Can be filtered by:
    - **provider_type**: Specific provider (e.g., "bicep", "terraform")
    - **cloud**: Cloud platform (azure, gcp)

    Returns template metadata including name, format, cloud, and path.
    """
    templates = template_manager.list_templates(
        provider_type=provider_type,
        cloud=cloud
    )

    return create_success_response(
        message=f"Found {len(templates)} templates",
        data={"templates": templates, "count": len(templates)}
    )


@app.get("/templates/{provider_type}/{template_name}",
    summary="Get Template Details",
    response_model=StandardResponse,
    tags=["Templates"])
async def get_template(provider_type: str, template_name: str):
    """
    Get detailed information about a specific template.

    Returns template metadata and optionally the template content.
    """
    template = template_manager.get_template(template_name, provider_type)

    if not template:
        raise TemplateNotFoundError(template_name, provider_type)

    return create_success_response(
        message="Template found",
        data=template.to_dict()
    )


@app.get("/templates/{provider_type}/{template_name}/content",
    summary="Get Template Content",
    tags=["Templates"])
async def get_template_content(provider_type: str, template_name: str):
    """
    Get the raw content of a template file.

    Returns the template as plain text (Bicep, Terraform, etc.).
    """
    content = template_manager.get_template_content(template_name, provider_type)

    if not content:
        raise HTTPException(
            status_code=404,
            detail=f"Template '{template_name}' not found"
        )

    return JSONResponse(
        content={"content": content},
        media_type="application/json"
    )


@app.get("/templates/{provider_type}/{template_name}/metadata",
    summary="Get Template Metadata",
    response_model=StandardResponse,
    tags=["Templates"])
async def get_template_metadata(provider_type: str, template_name: str):
    """
    Get comprehensive metadata for a template including cost estimates, validation rules, and examples.

    Returns:
    - Template information (name, description, version)
    - All parameters with validation rules and examples
    - Cost estimation hints
    - Prerequisites
    - Related templates
    - Documentation links
    """
    try:
        # Get template path
        template_path = template_manager.get_template_path(template_name, provider_type)

        if not template_path:
            raise TemplateNotFoundError(template_name, provider_type)

        # Check for metadata.json file
        from pathlib import Path
        template_file = Path(template_path)
        metadata_file = template_file.parent / f"{template_name}.metadata.json"

        if metadata_file.exists():
            with open(metadata_file, 'r') as f:
                metadata = json.load(f)

            return create_success_response(
                message="Template metadata loaded",
                data={
                    "template_name": template_name,
                    "provider_type": provider_type,
                    "has_metadata": True,
                    "metadata": metadata
                }
            )
        else:
            # Return basic info if no metadata file exists
            return create_success_response(
                message="No metadata file found, using defaults",
                data={
                    "template_name": template_name,
                    "provider_type": provider_type,
                    "has_metadata": False,
                    "metadata": {
                        "name": template_name,
                        "displayName": template_name.replace("-", " ").title(),
                        "description": f"{template_name} deployment template",
                        "provider": provider_type
                    }
                }
            )

    except TemplateNotFoundError:
        raise
    except Exception as e:
        logger.exception(f"Error loading template metadata: {e}")
        raise InternalServerError(f"Failed to load template metadata: {str(e)}")


@app.post("/templates/{provider_type}/{template_name}/estimate-cost",
    summary="Estimate Deployment Cost",
    response_model=StandardResponse,
    tags=["Templates"])
async def estimate_cost(
    provider_type: str,
    template_name: str,
    parameters: Dict[str, Any]
):
    """
    Estimate the monthly cost of a deployment based on template parameters.

    Provides a cost breakdown and notes about the estimate.
    """
    try:
        # Validate template exists
        template_path = template_manager.get_template_path(template_name, provider_type)

        if not template_path:
            raise TemplateNotFoundError(template_name, provider_type)

        # Calculate cost estimate (now with real-time pricing!)
        cost_estimate = await estimate_deployment_cost(
            template_name=template_name,
            provider_type=provider_type,
            parameters=parameters
        )

        return create_success_response(
            message="Cost estimate calculated",
            data=cost_estimate
        )

    except TemplateNotFoundError:
        raise
    except Exception as e:
        logger.exception(f"Error estimating cost: {e}")
        raise InternalServerError(f"Failed to estimate cost: {str(e)}")


# ==================== Dynamic Cloud Resource Options ====================

@app.get("/api/azure/vm-sizes",
    summary="Get Available Azure VM Sizes",
    response_model=StandardResponse,
    tags=["Azure", "Dynamic Options"])
async def get_azure_vm_sizes(location: str = Query(..., description="Azure location (e.g., eastus, westeurope)")):
    """
    Get available VM sizes for a specific Azure region from Azure Management API.

    Returns a list of available VM sizes with their specifications.
    Falls back to static list if credentials are not available.
    """
    # Fallback static VM sizes (common sizes available in most regions)
    FALLBACK_VM_SIZES = [
        {"name": "Standard_B1s", "vcpus": 1, "memory_gb": 1, "description": "1 vCPU, 1 GB RAM (Burstable)"},
        {"name": "Standard_B2s", "vcpus": 2, "memory_gb": 4, "description": "2 vCPUs, 4 GB RAM (Burstable)"},
        {"name": "Standard_B2ms", "vcpus": 2, "memory_gb": 8, "description": "2 vCPUs, 8 GB RAM (Burstable)"},
        {"name": "Standard_D2s_v3", "vcpus": 2, "memory_gb": 8, "description": "2 vCPUs, 8 GB RAM (General Purpose)"},
        {"name": "Standard_D4s_v3", "vcpus": 4, "memory_gb": 16, "description": "4 vCPUs, 16 GB RAM (General Purpose)"},
        {"name": "Standard_E2s_v3", "vcpus": 2, "memory_gb": 16, "description": "2 vCPUs, 16 GB RAM (Memory Optimized)"},
        {"name": "Standard_F2s_v2", "vcpus": 2, "memory_gb": 4, "description": "2 vCPUs, 4 GB RAM (Compute Optimized)"},
    ]

    try:
        from backend.services.azure_api_client import AzureAPIClient

        subscription_id = os.getenv("AZURE_SUBSCRIPTION_ID")
        # Check if we have valid credentials (not placeholder)
        if not subscription_id or subscription_id.startswith("00000000"):
            logger.info(f"Using fallback VM sizes for {location} (no valid credentials)")
            return create_success_response(
                message=f"Available VM sizes for {location} (fallback)",
                data={"location": location, "vm_sizes": FALLBACK_VM_SIZES, "count": len(FALLBACK_VM_SIZES)}
            )

        # Create Azure API client (will auto-authenticate)
        azure_client = AzureAPIClient(subscription_id=subscription_id)

        # Call Azure Management API to get REAL VM sizes
        vm_sizes_raw = await azure_client.get_vm_sizes_for_region(location)

        # Format for frontend
        vm_sizes = []
        for vm in vm_sizes_raw:
            memory_gb = vm.get("memory_in_mb", 0) / 1024
            vcpus = vm.get("number_of_cores", 0)
            vm_sizes.append({
                "name": vm.get("name"),
                "vcpus": vcpus,
                "memory_gb": round(memory_gb, 1),
                "description": f"{vcpus} vCPU{'s' if vcpus != 1 else ''}, {round(memory_gb, 1)} GB RAM"
            })

        await azure_client.close()

        # If API returned empty, use fallback
        if not vm_sizes:
            logger.warning(f"Azure API returned empty VM sizes for {location}, using fallback")
            vm_sizes = FALLBACK_VM_SIZES

        logger.info(f"Fetched {len(vm_sizes)} VM sizes for {location}")

        return create_success_response(
            message=f"Available VM sizes for {location}",
            data={"location": location, "vm_sizes": vm_sizes, "count": len(vm_sizes)}
        )

    except Exception as e:
        logger.warning(f"Error fetching Azure VM sizes for {location}, using fallback: {e}")
        return create_success_response(
            message=f"Available VM sizes for {location} (fallback)",
            data={"location": location, "vm_sizes": FALLBACK_VM_SIZES, "count": len(FALLBACK_VM_SIZES)}
        )


@app.get("/api/azure/resource-groups",
    summary="Get Azure Resource Groups",
    response_model=StandardResponse,
    tags=["Azure", "Dynamic Options"])
async def get_azure_resource_groups():
    """
    Get all Resource Groups in the Azure subscription.

    Returns list of existing resource groups that can be used for deployments.
    """
    try:
        import aiohttp
        from azure.identity import ClientSecretCredential

        subscription_id = os.getenv("AZURE_SUBSCRIPTION_ID")
        tenant_id = os.getenv("AZURE_TENANT_ID")
        client_id = os.getenv("AZURE_CLIENT_ID")
        client_secret = os.getenv("AZURE_CLIENT_SECRET")

        # Check for valid credentials
        if not all([subscription_id, tenant_id, client_id, client_secret]) or subscription_id.startswith("00000000"):
            logger.info("No valid Azure credentials for resource groups")
            return create_success_response(
                message="Azure credentials not configured",
                data={"resource_groups": [], "count": 0, "can_create_new": True}
            )

        # Get access token
        credential = ClientSecretCredential(
            tenant_id=tenant_id,
            client_id=client_id,
            client_secret=client_secret
        )
        token = credential.get_token("https://management.azure.com/.default")

        # Call Azure Management API
        url = f"https://management.azure.com/subscriptions/{subscription_id}/resourcegroups?api-version=2021-04-01"
        headers = {"Authorization": f"Bearer {token.token}"}

        async with aiohttp.ClientSession() as session:
            async with session.get(url, headers=headers) as response:
                if response.status == 200:
                    data = await response.json()
                    resource_groups = [
                        {
                            "name": rg.get("name"),
                            "location": rg.get("location"),
                            "display_name": f"{rg.get('name')} ({rg.get('location')})"
                        }
                        for rg in data.get("value", [])
                    ]
                    logger.info(f"Fetched {len(resource_groups)} Azure resource groups")
                    return create_success_response(
                        message="Azure resource groups",
                        data={"resource_groups": resource_groups, "count": len(resource_groups), "can_create_new": True}
                    )
                else:
                    logger.warning(f"Azure API returned {response.status}")
                    return create_success_response(
                        message="Could not fetch resource groups",
                        data={"resource_groups": [], "count": 0, "can_create_new": True}
                    )

    except Exception as e:
        logger.warning(f"Error fetching Azure resource groups: {e}")
        return create_success_response(
            message="Error fetching resource groups",
            data={"resource_groups": [], "count": 0, "can_create_new": True}
        )


@app.get("/api/gcp/projects",
    summary="Get GCP Projects",
    response_model=StandardResponse,
    tags=["GCP", "Dynamic Options"])
async def get_gcp_projects():
    """
    Get available GCP projects.

    For GCP, the project acts similar to Azure's resource group.
    """
    try:
        project_id = os.getenv("GOOGLE_PROJECT_ID")

        if not project_id or project_id.startswith("your-"):
            return create_success_response(
                message="GCP project not configured",
                data={"projects": [], "count": 0}
            )

        # Return configured project
        projects = [
            {
                "name": project_id,
                "display_name": project_id
            }
        ]

        return create_success_response(
            message="GCP projects",
            data={"projects": projects, "count": len(projects)}
        )

    except Exception as e:
        logger.warning(f"Error fetching GCP projects: {e}")
        return create_success_response(
            message="Error fetching projects",
            data={"projects": [], "count": 0}
        )


@app.get("/api/azure/locations",
    summary="Get Available Azure Locations",
    response_model=StandardResponse,
    tags=["Azure", "Dynamic Options"])
async def get_azure_locations():
    """
    Get all available Azure locations/regions from Azure Management API.

    Returns a comprehensive list of ALL Azure regions where resources can be deployed.
    Falls back to static list if credentials are not available.
    """
    # Fallback static locations (student-compatible regions)
    FALLBACK_LOCATIONS = [
        {"name": "norwayeast", "display_name": "Norway East", "description": "Norway East"},
        {"name": "swedencentral", "display_name": "Sweden Central", "description": "Sweden Central"},
        {"name": "polandcentral", "display_name": "Poland Central", "description": "Poland Central"},
        {"name": "francecentral", "display_name": "France Central", "description": "France Central"},
        {"name": "spaincentral", "display_name": "Spain Central", "description": "Spain Central"},
        {"name": "westeurope", "display_name": "West Europe", "description": "West Europe"},
        {"name": "northeurope", "display_name": "North Europe", "description": "North Europe"},
        {"name": "eastus", "display_name": "East US", "description": "East US"},
        {"name": "eastus2", "display_name": "East US 2", "description": "East US 2"},
        {"name": "westus", "display_name": "West US", "description": "West US"},
        {"name": "westus2", "display_name": "West US 2", "description": "West US 2"},
        {"name": "centralus", "display_name": "Central US", "description": "Central US"},
    ]

    try:
        from backend.services.azure_api_client import AzureAPIClient

        subscription_id = os.getenv("AZURE_SUBSCRIPTION_ID")
        # Check if we have valid credentials (not placeholder)
        if not subscription_id or subscription_id.startswith("00000000"):
            logger.info("Using fallback Azure locations (no valid credentials)")
            return create_success_response(
                message="Available Azure locations (fallback)",
                data={"locations": FALLBACK_LOCATIONS, "count": len(FALLBACK_LOCATIONS)}
            )

        # Create Azure API client (will auto-authenticate)
        azure_client = AzureAPIClient(subscription_id=subscription_id)

        # Call Azure Management API to get ALL locations
        locations_raw = await azure_client.get_locations()

        # Format for frontend
        locations = []
        for loc in locations_raw:
            locations.append({
                "name": loc.get("name"),
                "display_name": loc.get("display_name") or loc.get("regional_display_name"),
                "description": loc.get("display_name") or loc.get("regional_display_name")
            })

        await azure_client.close()

        # If API returned empty, use fallback
        if not locations:
            logger.warning("Azure API returned empty locations, using fallback")
            locations = FALLBACK_LOCATIONS

        logger.info(f"Fetched {len(locations)} Azure locations")

        return create_success_response(
            message="Available Azure locations",
            data={"locations": locations, "count": len(locations)}
        )

    except Exception as e:
        logger.warning(f"Error fetching Azure locations, using fallback: {e}")
        return create_success_response(
            message="Available Azure locations (fallback)",
            data={"locations": FALLBACK_LOCATIONS, "count": len(FALLBACK_LOCATIONS)}
        )


@app.get("/api/gcp/machine-types",
    summary="Get Available GCP Machine Types",
    response_model=StandardResponse,
    tags=["GCP", "Dynamic Options"])
async def get_gcp_machine_types(
    zone: Optional[str] = Query(None, description="GCP zone (e.g., us-central1-a)"),
    region: Optional[str] = Query(None, description="GCP region (e.g., us-central1)")
):
    """
    Get available GCP machine types from Compute Engine API.

    Returns a list of ALL GCP machine types with their specifications.
    Falls back to static list if credentials are not available.
    """
    # Fallback static machine types
    FALLBACK_MACHINE_TYPES = [
        {"name": "e2-micro", "vcpus": 0.25, "memory_gb": 1, "description": "0.25 vCPU, 1 GB RAM (Shared-core)"},
        {"name": "e2-small", "vcpus": 0.5, "memory_gb": 2, "description": "0.5 vCPU, 2 GB RAM (Shared-core)"},
        {"name": "e2-medium", "vcpus": 1, "memory_gb": 4, "description": "1 vCPU, 4 GB RAM (Shared-core)"},
        {"name": "n1-standard-1", "vcpus": 1, "memory_gb": 3.75, "description": "1 vCPU, 3.75 GB RAM"},
        {"name": "n1-standard-2", "vcpus": 2, "memory_gb": 7.5, "description": "2 vCPUs, 7.5 GB RAM"},
        {"name": "n2-standard-2", "vcpus": 2, "memory_gb": 8, "description": "2 vCPUs, 8 GB RAM"},
        {"name": "n2-standard-4", "vcpus": 4, "memory_gb": 16, "description": "4 vCPUs, 16 GB RAM"},
    ]

    try:
        from backend.services.gcp_api_client import GCPAPIClient

        project_id = os.getenv("GOOGLE_PROJECT_ID")
        # Check if we have valid credentials (not placeholder)
        if not project_id or project_id.startswith("your-"):
            logger.info("Using fallback GCP machine types (no valid credentials)")
            return create_success_response(
                message="Available GCP machine types (fallback)",
                data={"zone": zone, "region": region, "machine_types": FALLBACK_MACHINE_TYPES, "count": len(FALLBACK_MACHINE_TYPES)}
            )

        # Create GCP API client (will auto-authenticate)
        gcp_client = GCPAPIClient(project_id=project_id)

        # Call GCP Compute Engine API to get machine types
        # If region provided but not zone, use first zone in region
        target_zone = zone
        if not target_zone and region:
            # Get zones for region and pick first one
            zones = await gcp_client.get_zones(region=region)
            if zones:
                target_zone = zones[0].get("name")

        machine_types_raw = await gcp_client.get_machine_types(zone=target_zone)

        await gcp_client.close()

        # If API returned empty (permissions issue), use fallback
        if not machine_types_raw:
            logger.warning("GCP API returned empty machine types, using fallback")
            return create_success_response(
                message="Available GCP machine types (fallback)",
                data={"zone": zone, "region": region, "machine_types": FALLBACK_MACHINE_TYPES, "count": len(FALLBACK_MACHINE_TYPES)}
            )

        logger.info(f"Fetched {len(machine_types_raw)} GCP machine types{f' for zone {target_zone}' if target_zone else ''}")

        return create_success_response(
            message=f"Available GCP machine types",
            data={
                "zone": target_zone,
                "region": region,
                "machine_types": machine_types_raw,
                "count": len(machine_types_raw)
            }
        )

    except Exception as e:
        logger.warning(f"Error fetching GCP machine types, using fallback: {e}")
        return create_success_response(
            message="Available GCP machine types (fallback)",
            data={"zone": zone, "region": region, "machine_types": FALLBACK_MACHINE_TYPES, "count": len(FALLBACK_MACHINE_TYPES)}
        )


@app.get("/api/gcp/zones",
    summary="Get Available GCP Zones",
    response_model=StandardResponse,
    tags=["GCP", "Dynamic Options"])
async def get_gcp_zones(region: Optional[str] = Query(None, description="Filter by region (e.g., us-central1)")):
    """
    Get all available GCP zones from Compute Engine API, optionally filtered by region.

    Returns a list of GCP zones where resources can be deployed.
    Falls back to static list if API is unavailable.
    """
    # Fallback GCP zones (common zones for popular regions)
    FALLBACK_GCP_ZONES = [
        {"name": "us-central1-a", "region": "us-central1", "description": "US Central (Iowa) - Zone A"},
        {"name": "us-central1-b", "region": "us-central1", "description": "US Central (Iowa) - Zone B"},
        {"name": "us-central1-c", "region": "us-central1", "description": "US Central (Iowa) - Zone C"},
        {"name": "us-east1-b", "region": "us-east1", "description": "US East (South Carolina) - Zone B"},
        {"name": "us-east1-c", "region": "us-east1", "description": "US East (South Carolina) - Zone C"},
        {"name": "us-west1-a", "region": "us-west1", "description": "US West (Oregon) - Zone A"},
        {"name": "us-west1-b", "region": "us-west1", "description": "US West (Oregon) - Zone B"},
        {"name": "europe-west1-b", "region": "europe-west1", "description": "Europe West (Belgium) - Zone B"},
        {"name": "europe-west1-c", "region": "europe-west1", "description": "Europe West (Belgium) - Zone C"},
        {"name": "europe-west2-a", "region": "europe-west2", "description": "Europe West (London) - Zone A"},
        {"name": "europe-west3-a", "region": "europe-west3", "description": "Europe West (Frankfurt) - Zone A"},
        {"name": "europe-north1-a", "region": "europe-north1", "description": "Europe North (Finland) - Zone A"},
        {"name": "asia-east1-a", "region": "asia-east1", "description": "Asia East (Taiwan) - Zone A"},
        {"name": "asia-southeast1-a", "region": "asia-southeast1", "description": "Asia Southeast (Singapore) - Zone A"},
        {"name": "asia-northeast1-a", "region": "asia-northeast1", "description": "Asia Northeast (Tokyo) - Zone A"},
        {"name": "australia-southeast1-a", "region": "australia-southeast1", "description": "Australia (Sydney) - Zone A"},
    ]

    def filter_zones(zones, region_filter):
        if not region_filter:
            return zones
        return [z for z in zones if z.get("region") == region_filter]

    try:
        from backend.services.gcp_api_client import GCPAPIClient

        project_id = os.getenv("GOOGLE_PROJECT_ID")
        if not project_id:
            logger.warning("GCP Project ID not configured, using fallback zones")
            filtered = filter_zones(FALLBACK_GCP_ZONES, region)
            return create_success_response(
                message=f"Available GCP zones (fallback){f' in {region}' if region else ''}",
                data={"zones": filtered, "count": len(filtered)}
            )

        # Create GCP API client (will auto-authenticate)
        gcp_client = GCPAPIClient(project_id=project_id)

        # Call GCP Compute Engine API to get zones
        zones_raw = await gcp_client.get_zones(region=region)

        await gcp_client.close()

        # If API returned empty (permissions issue), use fallback
        if not zones_raw:
            logger.warning("GCP API returned empty zones, using fallback")
            filtered = filter_zones(FALLBACK_GCP_ZONES, region)
            return create_success_response(
                message=f"Available GCP zones (fallback){f' in {region}' if region else ''}",
                data={"zones": filtered, "count": len(filtered)}
            )

        # Format for frontend
        zones = [
            {
                "name": z.get("name"),
                "region": z.get("region"),
                "description": z.get("description") or z.get("name")
            }
            for z in zones_raw
        ]

        logger.info(f"Fetched {len(zones)} GCP zones{f' for region {region}' if region else ''}")

        return create_success_response(
            message=f"Available GCP zones{f' in {region}' if region else ''}",
            data={"zones": zones, "count": len(zones)}
        )

    except Exception as e:
        logger.warning(f"Error fetching GCP zones, using fallback: {e}")
        filtered = filter_zones(FALLBACK_GCP_ZONES, region)
        return create_success_response(
            message=f"Available GCP zones (fallback){f' in {region}' if region else ''}",
            data={"zones": filtered, "count": len(filtered)}
        )


@app.get("/api/gcp/regions",
    summary="Get Available GCP Regions",
    response_model=StandardResponse,
    tags=["GCP", "Dynamic Options"])
async def get_gcp_regions():
    """
    Get all available GCP regions from Compute Engine API.

    Returns a comprehensive list of ALL GCP regions where resources can be deployed.
    Falls back to static list if API is unavailable.
    """
    # Fallback GCP regions (used when API fails or no credentials)
    FALLBACK_GCP_REGIONS = [
        {"name": "us-central1", "display_name": "US Central (Iowa)", "description": "US Central (Iowa)"},
        {"name": "us-east1", "display_name": "US East (South Carolina)", "description": "US East (South Carolina)"},
        {"name": "us-east4", "display_name": "US East (N. Virginia)", "description": "US East (N. Virginia)"},
        {"name": "us-west1", "display_name": "US West (Oregon)", "description": "US West (Oregon)"},
        {"name": "us-west2", "display_name": "US West (Los Angeles)", "description": "US West (Los Angeles)"},
        {"name": "europe-west1", "display_name": "Europe West (Belgium)", "description": "Europe West (Belgium)"},
        {"name": "europe-west2", "display_name": "Europe West (London)", "description": "Europe West (London)"},
        {"name": "europe-west3", "display_name": "Europe West (Frankfurt)", "description": "Europe West (Frankfurt)"},
        {"name": "europe-west4", "display_name": "Europe West (Netherlands)", "description": "Europe West (Netherlands)"},
        {"name": "europe-north1", "display_name": "Europe North (Finland)", "description": "Europe North (Finland)"},
        {"name": "asia-east1", "display_name": "Asia East (Taiwan)", "description": "Asia East (Taiwan)"},
        {"name": "asia-east2", "display_name": "Asia East (Hong Kong)", "description": "Asia East (Hong Kong)"},
        {"name": "asia-southeast1", "display_name": "Asia Southeast (Singapore)", "description": "Asia Southeast (Singapore)"},
        {"name": "asia-northeast1", "display_name": "Asia Northeast (Tokyo)", "description": "Asia Northeast (Tokyo)"},
        {"name": "australia-southeast1", "display_name": "Australia (Sydney)", "description": "Australia (Sydney)"},
    ]

    try:
        from backend.services.gcp_api_client import GCPAPIClient

        project_id = os.getenv("GOOGLE_PROJECT_ID")
        if not project_id:
            logger.warning("GCP Project ID not configured, using fallback regions")
            return create_success_response(
                message="Available GCP regions (fallback - no project configured)",
                data={"regions": FALLBACK_GCP_REGIONS, "count": len(FALLBACK_GCP_REGIONS)}
            )

        # Create GCP API client (will auto-authenticate)
        gcp_client = GCPAPIClient(project_id=project_id)

        # Call GCP Compute Engine API to get ALL regions
        regions_raw = await gcp_client.get_regions()

        await gcp_client.close()

        # If API returned empty (permissions issue), use fallback
        if not regions_raw:
            logger.warning("GCP API returned empty regions, using fallback")
            return create_success_response(
                message="Available GCP regions (fallback - API unavailable)",
                data={"regions": FALLBACK_GCP_REGIONS, "count": len(FALLBACK_GCP_REGIONS)}
            )

        # Format for frontend
        regions = [
            {
                "name": r.get("name"),
                "display_name": r.get("display_name"),
                "description": r.get("display_name")
            }
            for r in regions_raw
        ]

        logger.info(f"Fetched {len(regions)} GCP regions from Compute Engine API")

        return create_success_response(
            message="Available GCP regions",
            data={"regions": regions, "count": len(regions)}
        )

    except Exception as e:
        logger.warning(f"Error fetching GCP regions, using fallback: {e}")
        return create_success_response(
            message="Available GCP regions (fallback)",
            data={"regions": FALLBACK_GCP_REGIONS, "count": len(FALLBACK_GCP_REGIONS)}
        )


# ==================== Template Parameters ====================

@app.get("/templates/{provider_type}/{template_name}/parameters",
    summary="Get Template Parameters",
    response_model=StandardResponse,
    tags=["Templates"])
async def get_template_parameters(provider_type: str, template_name: str):
    """
    Extract and return parameters from a template.

    Parses the template file and extracts:
    - Parameter names and types
    - Descriptions
    - Default values
    - Validation rules (allowed values, min/max, patterns)
    - Whether parameters are required

    This enables dynamic form generation for deployments.

    **Supported formats:**
    - Bicep (.bicep)
    - Terraform (.tf)
    - ARM templates (.json) - coming soon

    **Example response:**
    ```json
    {
      "parameters": [
        {
          "name": "storageAccountName",
          "type": "string",
          "description": "The name of the storage account",
          "required": true
        },
        {
          "name": "storageAccountType",
          "type": "string",
          "description": "The type of the storage account (SKU)",
          "default": "Standard_LRS",
          "required": false,
          "allowed_values": ["Standard_LRS", "Standard_GRS", "Premium_LRS"]
        }
      ]
    }
    ```
    """
    try:
        # Get template path
        template_path = template_manager.get_template_path(template_name, provider_type)

        if not template_path:
            return create_error_response(
                message=f"Template '{template_name}' not found for provider '{provider_type}'",
                status_code=404
            )

        # Parse parameters
        parameters = TemplateParameterParser.parse_file(str(template_path))

        # Convert to dict format
        parameters_dict = [param.to_dict() for param in parameters]

        return create_success_response(
            message=f"Found {len(parameters)} parameters",
            data={
                "template_name": template_name,
                "provider_type": provider_type,
                "parameters": parameters_dict,
                "count": len(parameters)
            }
        )

    except FileNotFoundError as e:
        return create_error_response(
            message="Template file not found",
            details=str(e),
            status_code=404
        )
    except Exception as e:
        logger.exception(f"Error parsing template parameters: {e}")
        return create_error_response(
            message="Failed to parse template parameters",
            details=str(e),
            status_code=500
        )


@app.post("/deploy",
    summary="Deploy Infrastructure",
    response_model=StandardResponse,
    tags=["Deployments"],
    status_code=status.HTTP_202_ACCEPTED)
async def deploy_infrastructure(
    request: DeploymentRequest,
    http_request: Request,
    db: Session = Depends(get_db)
):
    """
    Deploy infrastructure using the specified template and provider.

    **Security**: This endpoint requires authentication (if enabled) and is rate-limited.

    This endpoint:
    1. Validates authentication and rate limits
    2. Validates deployment parameters for security
    3. Validates the template exists
    4. Creates a deployment record in the database
    5. Queues the deployment task in Celery
    6. Returns immediately with deployment_id for tracking

    The deployment runs asynchronously in the background.
    Use GET /deployments/{deployment_id}/status to check progress.
    """
    try:
        # Auto-populate subscription_id from environment if not provided
        subscription_id = request.subscription_id
        if not subscription_id:
            if request.provider_type in ['terraform-azure', 'azure']:
                subscription_id = os.getenv('AZURE_SUBSCRIPTION_ID')
                logger.info("Using AZURE_SUBSCRIPTION_ID from environment")
            elif request.provider_type in ['terraform-gcp', 'gcp']:
                subscription_id = os.getenv('GOOGLE_PROJECT_ID')
                logger.info("Using GOOGLE_PROJECT_ID from environment")

            if not subscription_id:
                raise MissingParameterError(
                    "subscription_id (Set AZURE_SUBSCRIPTION_ID or GOOGLE_PROJECT_ID in .env)"
                )

        # Validate deployment request
        is_valid, error_msg = DeploymentRequestValidator.validate_deployment_request(
            provider_type=request.provider_type,
            template_name=request.template_name,
            resource_group=request.resource_group,
            location=request.location,
            parameters=request.parameters
        )
        if not is_valid:
            logger.warning(f"Invalid deployment request: {error_msg}")
            raise ValidationError("deployment_request", error_msg)

        # Validate parameters for security issues
        is_valid, error_msg = validate_deployment_parameters(request.parameters)
        if not is_valid:
            logger.warning(f"Invalid deployment parameters: {error_msg}")
            raise ValidationError("parameters", error_msg)

        # Provider-specific parameter validation
        try:
            if 'azure' in request.provider_type.lower():
                # Azure-specific validations
                if 'storage_account_name' in request.parameters and request.parameters.get('storage_account_name'):
                    ParameterValidator.validate_azure_storage_account_name(
                        request.parameters['storage_account_name']
                    )
                if 'resource_group' in request.parameters and request.parameters.get('resource_group'):
                    ParameterValidator.validate_azure_resource_group_name(
                        request.parameters['resource_group']
                    )

            elif 'gcp' in request.provider_type.lower():
                # GCP-specific validations
                if 'bucket_name' in request.parameters and request.parameters.get('bucket_name'):
                    from backend.utils.validators import validate_gcp_bucket_name
                    validate_gcp_bucket_name(request.parameters['bucket_name'])

                if 'instance_name' in request.parameters and request.parameters.get('instance_name'):
                    ParameterValidator.validate_gcp_resource_name(
                        request.parameters['instance_name'], 'instance_name'
                    )

                if 'cluster_name' in request.parameters and request.parameters.get('cluster_name'):
                    ParameterValidator.validate_gcp_resource_name(
                        request.parameters['cluster_name'], 'cluster_name'
                    )

                if 'project_id' in request.parameters and request.parameters.get('project_id'):
                    ParameterValidator.validate_gcp_project_id(
                        request.parameters['project_id']
                    )

            # Common validations for all providers
            if 'cidr_block' in request.parameters and request.parameters.get('cidr_block'):
                ParameterValidator.validate_cidr(request.parameters['cidr_block'])

            if 'ip_address' in request.parameters and request.parameters.get('ip_address'):
                ParameterValidator.validate_ip_address(request.parameters['ip_address'])

        except (InvalidParameterError, MissingParameterError) as e:
            logger.warning(f"Parameter validation failed: {str(e)}")
            raise

        # Get template path
        template_path = template_manager.get_template_path(
            request.template_name,
            request.provider_type
        )

        if not template_path:
            raise TemplateNotFoundError(request.template_name, request.provider_type)

        # Get template metadata for cloud provider
        template_meta = template_manager.get_template(request.template_name, request.provider_type)
        cloud_provider = template_meta.cloud_provider.value if template_meta else "unknown"

        # Generate unique deployment ID
        deployment_id = f"deploy-{uuid.uuid4().hex[:12]}"

        # Create deployment record in database
        deployment = Deployment(
            deployment_id=deployment_id,
            provider_type=request.provider_type,
            cloud_provider=cloud_provider,
            template_name=request.template_name,
            resource_group=request.resource_group,
            status=DBDeploymentStatus.PENDING,
            parameters=request.parameters,
            tags=request.tags or []
        )
        db.add(deployment)
        db.commit()

        # Log with masked sensitive data
        masked_params = mask_sensitive_data(request.parameters)
        logger.info(
            f"Created deployment record {deployment_id} for {request.template_name} "
            f"(provider: {request.provider_type}, params: {masked_params})"
        )

        # Queue deployment task in Celery
        # Build provider config based on provider type
        provider_config = {
            "subscription_id": subscription_id,
            "region": request.location
        }

        # Add cloud_platform for Terraform providers
        if request.provider_type in ("gcp", "terraform-gcp"):
            provider_config["cloud_platform"] = "gcp"
        elif request.provider_type in ("terraform-azure",):
            provider_config["cloud_platform"] = "azure"
        elif request.provider_type in ("terraform-aws",):
            provider_config["cloud_platform"] = "aws"

        task = deploy_task.delay(
            deployment_id=deployment_id,
            provider_type=request.provider_type,
            template_path=str(template_path),
            parameters=request.parameters,
            resource_group=request.resource_group,
            provider_config=provider_config
        )

        logger.info(f"Queued deployment task {task.id} for deployment {deployment_id}")

        return create_success_response(
            message="Deployment queued successfully",
            data={
                "deployment_id": deployment_id,
                "status": "pending",
                "task_id": task.id,
                "resource_group": request.resource_group,
                "provider": request.provider_type,
                "template": request.template_name,
                "message": "Deployment has been queued and will start shortly. Use the deployment_id to check status."
            }
        )

    except Exception as e:
        logger.exception("Error creating deployment")
        return create_error_response(
            message="Failed to queue deployment",
            details=str(e),
            status_code=500
        )


@app.get("/deployments/{deployment_id}/status",
    summary="Get Deployment Status",
    response_model=StandardResponse,
    tags=["Deployments"])
async def get_deployment_status(deployment_id: str, db: Session = Depends(get_db)):
    """
    Get the current status of a deployment.

    Retrieves deployment status from the database and Celery task status.
    """
    try:
        # Get deployment from database
        deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()

        if not deployment:
            raise DeploymentNotFoundError(deployment_id)

        # Calculate duration if available
        duration = None
        if deployment.started_at and deployment.completed_at:
            duration = (deployment.completed_at - deployment.started_at).total_seconds()
        elif deployment.started_at:
            duration = (datetime.utcnow() - deployment.started_at).total_seconds()

        return create_success_response(
            message="Deployment status retrieved",
            data={
                **deployment.to_dict(),
                "duration_seconds": duration
            }
        )

    except MultiCloudException:
        # Re-raise our custom exceptions to be handled by global handler
        raise
    except Exception as e:
        logger.exception(f"Error retrieving deployment status for {deployment_id}")
        raise InternalServerError(f"Failed to get deployment status: {str(e)}")


@app.get("/tasks/{task_id}/status",
    summary="Get Task Status",
    response_model=StandardResponse,
    tags=["Tasks"])
async def get_task_status(task_id: str):
    """
    Get the current status of a Celery task, including phase information.

    Returns task state, progress, and current deployment phase.
    """
    try:
        from backend.celery_app import celery_app

        # Get task result from Celery
        task = celery_app.AsyncResult(task_id)

        # Get task state and metadata
        state = task.state
        info = task.info if task.info else {}

        # Extract phase information from metadata
        phase = info.get('phase', 'unknown') if isinstance(info, dict) else 'unknown'
        progress = info.get('progress', 0) if isinstance(info, dict) else 0
        status_message = info.get('status', '') if isinstance(info, dict) else ''

        return create_success_response(
            message="Task status retrieved",
            data={
                "task_id": task_id,
                "state": state,
                "phase": phase,
                "progress": progress,
                "status": status_message,
                "info": info
            }
        )

    except Exception as e:
        logger.exception(f"Error getting task status for {task_id}")
        raise InternalServerError(f"Failed to get task status: {str(e)}")


def parse_structured_log(log_line: str) -> dict:
    """
    Parse structured log line to extract timestamp, level, phase, and message.

    Format: [timestamp] [LEVEL] [PHASE] message - details_json
    Returns: {timestamp, level, phase, message, details}
    """
    import re

    # Regex pattern to match: [timestamp] [LEVEL] [PHASE] message
    pattern = r'\[([^\]]+)\]\s*\[([^\]]+)\](?:\s*\[([^\]]+)\])?\s*(.+?)(?:\s*-\s*(\{.+\}))?$'
    match = re.match(pattern, log_line)

    if match:
        timestamp, level, phase, message, details_json = match.groups()
        details = None
        if details_json:
            try:
                details = json.loads(details_json)
            except:
                pass

        return {
            'timestamp': timestamp,
            'level': level,
            'phase': phase or 'unknown',
            'message': message.strip(),
            'details': details
        }

    # Fallback for unstructured logs
    return {
        'timestamp': datetime.utcnow().isoformat(),
        'level': 'INFO',
        'phase': 'unknown',
        'message': log_line,
        'details': None
    }


@app.get("/deployments/{deployment_id}/logs",
    summary="Stream Deployment Logs (SSE)",
    tags=["Deployments"])
async def stream_deployment_logs(deployment_id: str, db: Session = Depends(get_db)):
    """
    Stream real-time deployment logs using Server-Sent Events (SSE) with structured log parsing.

    Logs are streamed with metadata including:
    - timestamp: ISO 8601 timestamp
    - level: Log level (INFO, WARNING, ERROR, DEBUG)
    - phase: Deployment phase (initialization, validating, planning, applying, finalizing)
    - message: Log message
    - details: Optional JSON details

    **Example (JavaScript):**
    ```javascript
    const eventSource = new EventSource(`/deployments/${deploymentId}/logs`);
    eventSource.onmessage = (event) => {
        const log = JSON.parse(event.data);
        console.log(`[${log.level}] [${log.phase}] ${log.message}`);
    };
    ```
    """
    async def event_generator():
        """Generate SSE events for deployment logs"""
        try:
            # Get deployment from database
            deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()

            if not deployment:
                yield f"data: {json.dumps({'type': 'error', 'message': 'Deployment not found'})}\n\n"
                return

            # Send initial status
            yield f"data: {json.dumps({'type': 'status', 'status': deployment.status.value, 'message': f'Deployment status: {deployment.status.value}'})}\n\n"

            # Stream logs in real-time
            last_log_length = 0
            max_iterations = 300  # Max 5 minutes (300 * 1 second)
            iteration = 0

            while iteration < max_iterations:
                # Refresh deployment data
                db.refresh(deployment)

                # Send current logs if they've changed
                if deployment.logs:
                    current_logs = deployment.logs
                    if len(current_logs) > last_log_length:
                        new_logs = current_logs[last_log_length:]
                        for line in new_logs.split('\n'):
                            if line.strip():
                                # Parse structured log
                                parsed_log = parse_structured_log(line)
                                yield f"data: {json.dumps({'type': 'log', **parsed_log})}\n\n"
                        last_log_length = len(current_logs)

                # Send progress updates with phase information
                if deployment.status == DBDeploymentStatus.RUNNING:
                    # Get task info for accurate phase/progress
                    if deployment.celery_task_id:
                        try:
                            from backend.celery_app import celery_app
                            task = celery_app.AsyncResult(deployment.celery_task_id)
                            task_info = task.info if task.info and isinstance(task.info, dict) else {}
                            phase = task_info.get('phase', 'running')
                            progress = task_info.get('progress', min(30 + (iteration * 2), 90))
                            yield f"data: {json.dumps({'type': 'progress', 'progress': progress, 'phase': phase, 'status': 'running'})}\n\n"
                        except:
                            progress = min(30 + (iteration * 2), 90)
                            yield f"data: {json.dumps({'type': 'progress', 'progress': progress, 'status': 'running'})}\n\n"
                    else:
                        progress = min(30 + (iteration * 2), 90)
                        yield f"data: {json.dumps({'type': 'progress', 'progress': progress, 'status': 'running'})}\n\n"

                # Check if deployment is complete
                if deployment.status in [DBDeploymentStatus.COMPLETED, DBDeploymentStatus.FAILED]:
                    # Send final status
                    yield f"data: {json.dumps({'type': 'status', 'status': deployment.status.value, 'message': f'Deployment {deployment.status.value}'})}\n\n"

                    # Send completion message
                    if deployment.status == DBDeploymentStatus.COMPLETED:
                        yield f"data: {json.dumps({'type': 'complete', 'message': 'Deployment completed successfully', 'outputs': deployment.outputs or {}})}\n\n"
                    else:
                        yield f"data: {json.dumps({'type': 'error', 'message': deployment.error_message or 'Deployment failed'})}\n\n"

                    break

                # Wait before next check
                await asyncio.sleep(1)
                iteration += 1

            # Send final done message
            yield f"data: {json.dumps({'type': 'done', 'message': 'Stream ended'})}\n\n"

        except Exception as e:
            logger.exception(f"Error streaming logs for deployment {deployment_id}")
            yield f"data: {json.dumps({'type': 'error', 'message': str(e)})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"  # Disable nginx buffering
        }
    )


@app.get("/deployments",
    summary="List All Deployments",
    response_model=StandardResponse,
    tags=["Deployments"])
async def list_deployments(
    db: Session = Depends(get_db),
    status: Optional[str] = Query(None, description="Filter by status"),
    provider_type: Optional[str] = Query(None, description="Filter by provider"),
    tag: Optional[str] = Query(None, description="Filter by tag"),
    limit: int = Query(50, description="Max number of results", le=100)
):
    """
    List all deployments with optional filtering.

    Returns recent deployments sorted by creation date (newest first).
    Supports filtering by status, provider_type, and tags.
    """
    try:
        query = db.query(Deployment)

        # Apply filters
        if status:
            query = query.filter(Deployment.status == status)
        if provider_type:
            query = query.filter(Deployment.provider_type == provider_type)

        # Filter by tag (check if tag exists in JSON array)
        if tag:
            # For PostgreSQL: Use JSON operators
            # For SQLite: Need to fetch all and filter in Python
            if DATABASE_URL.startswith("postgresql"):
                from sqlalchemy import func
                query = query.filter(func.json_array_contains(Deployment.tags, tag))
            else:
                # For SQLite, filter in Python after fetch
                all_deployments = query.order_by(Deployment.created_at.desc()).all()
                deployments = [d for d in all_deployments if tag in (d.tags or [])][:limit]
                return create_success_response(
                    message=f"Found {len(deployments)} deployments",
                    data={
                        "deployments": [d.to_dict() for d in deployments],
                        "total": len(deployments)
                    }
                )

        # Order and limit
        deployments = query.order_by(Deployment.created_at.desc()).limit(limit).all()

        return create_success_response(
            message=f"Found {len(deployments)} deployments",
            data={
                "deployments": [d.to_dict() for d in deployments],
                "total": len(deployments)
            }
        )

    except Exception as e:
        logger.exception("Error listing deployments")
        return create_error_response(
            message="Failed to list deployments",
            details=str(e),
            status_code=500
        )


@app.put("/deployments/{deployment_id}/tags",
    summary="Update Deployment Tags",
    response_model=StandardResponse,
    tags=["Deployments"])
async def update_deployment_tags(
    deployment_id: str,
    tags: List[str],
    db: Session = Depends(get_db)
):
    """
    Update tags for a specific deployment.

    **Example:**
    ```json
    ["production", "critical", "automated"]
    ```
    """
    try:
        deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()

        if not deployment:
            return create_error_response(
                message=f"Deployment {deployment_id} not found",
                status_code=404
            )

        # Update tags
        deployment.tags = tags
        db.commit()

        logger.info(f"Updated tags for deployment {deployment_id}: {tags}")

        return create_success_response(
            message="Tags updated successfully",
            data=deployment.to_dict()
        )

    except Exception as e:
        logger.exception(f"Error updating tags for deployment {deployment_id}")
        return create_error_response(
            message="Failed to update tags",
            details=str(e),
            status_code=500
        )


@app.get("/deployments/tags",
    summary="Get All Available Tags",
    response_model=StandardResponse,
    tags=["Deployments"])
async def get_all_tags(db: Session = Depends(get_db)):
    """
    Get a list of all unique tags used across all deployments.

    Useful for tag autocomplete and filtering UI.
    """
    try:
        deployments = db.query(Deployment).all()

        # Collect all unique tags
        all_tags = set()
        for deployment in deployments:
            if deployment.tags:
                all_tags.update(deployment.tags)

        tags_list = sorted(list(all_tags))

        return create_success_response(
            message=f"Found {len(tags_list)} unique tags",
            data={
                "tags": tags_list,
                "total": len(tags_list)
            }
        )

    except Exception as e:
        logger.exception("Error retrieving tags")
        return create_error_response(
            message="Failed to retrieve tags",
            details=str(e),
            status_code=500
        )


@app.delete("/deployments/{deployment_id}",
    summary="Delete Deployment",
    response_model=StandardResponse,
    tags=["Deployments"])
async def delete_deployment(deployment_id: str, db: Session = Depends(get_db)):
    """
    Delete a deployment record from the database.

    **Warning**: This does NOT destroy the actual cloud resources.
    It only removes the deployment record from the database.
    Use the destroy endpoint to remove actual infrastructure.
    """
    try:
        deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()

        if not deployment:
            return create_error_response(
                message=f"Deployment {deployment_id} not found",
                status_code=404
            )

        # Delete the deployment record
        db.delete(deployment)
        db.commit()

        logger.info(f"Deleted deployment record {deployment_id}")

        return create_success_response(
            message="Deployment record deleted successfully",
            data={"deployment_id": deployment_id}
        )

    except Exception as e:
        logger.exception(f"Error deleting deployment {deployment_id}")
        return create_error_response(
            message="Failed to delete deployment",
            details=str(e),
            status_code=500
        )


@app.get("/deployments/{deployment_id}",
    summary="Get Deployment Details",
    response_model=StandardResponse,
    tags=["Deployments"])
async def get_deployment_details(deployment_id: str, db: Session = Depends(get_db)):
    """
    Get detailed information about a specific deployment.

    Returns complete deployment information including parameters, outputs, logs, and status.
    """
    try:
        deployment = db.query(Deployment).filter_by(deployment_id=deployment_id).first()

        if not deployment:
            return create_error_response(
                message=f"Deployment {deployment_id} not found",
                status_code=404
            )

        # Calculate duration
        duration = None
        if deployment.started_at and deployment.completed_at:
            duration = (deployment.completed_at - deployment.started_at).total_seconds()
        elif deployment.started_at:
            duration = (datetime.utcnow() - deployment.started_at).total_seconds()

        return create_success_response(
            message="Deployment details retrieved successfully",
            data={
                **deployment.to_dict(),
                "duration_seconds": duration,
                "logs": deployment.logs
            }
        )

    except Exception as e:
        logger.exception(f"Error retrieving deployment details for {deployment_id}")
        return create_error_response(
            message="Failed to get deployment details",
            details=str(e),
            status_code=500
        )


@app.get("/resource-groups",
    summary="List Resource Groups",
    response_model=StandardResponse,
    tags=["Resource Groups"])
async def list_resource_groups(
    provider_type: str = Query("azure", description="Provider type"),
    subscription_id: str = Query(..., description="Subscription/account ID")
):
    """
    List all resource groups/stacks in the subscription.

    Returns resource groups for the specified cloud provider.
    """
    try:
        provider = get_provider(provider_type, subscription_id=subscription_id)
        groups = await provider.list_resource_groups()

        return create_success_response(
            message=f"Found {len(groups)} resource groups",
            data={
                "resource_groups": [
                    {
                        "name": group.name,
                        "location": group.location,
                        "resource_count": group.resource_count,
                        "tags": group.tags
                    }
                    for group in groups
                ],
                "count": len(groups)
            }
        )

    except Exception as e:
        return create_error_response(
            message="Failed to list resource groups",
            details=str(e),
            status_code=500
        )


@app.post("/resource-groups",
    summary="Create Resource Group",
    response_model=StandardResponse,
    tags=["Resource Groups"],
    status_code=status.HTTP_201_CREATED)
async def create_resource_group(request: ResourceGroupCreateRequest):
    """
    Create a new resource group/stack.

    Creates a logical container for resources in the specified cloud.
    """
    try:
        provider = get_provider(
            request.provider_type,
            subscription_id=request.subscription_id
        )

        group = await provider.create_resource_group(
            name=request.name,
            location=request.location,
            tags=request.tags
        )

        return create_success_response(
            message=f"Resource group '{request.name}' created successfully",
            data={
                "name": group.name,
                "location": group.location,
                "provider_id": group.provider_id
            }
        )

    except Exception as e:
        return create_error_response(
            message="Failed to create resource group",
            details=str(e),
            status_code=500
        )


@app.delete("/resource-groups/{resource_group_name}",
    summary="Delete Resource Group",
    response_model=StandardResponse,
    tags=["Resource Groups"])
async def delete_resource_group(
    resource_group_name: str,
    provider_type: str = Query("azure", description="Provider type"),
    subscription_id: str = Query(..., description="Subscription/account ID")
):
    """
    Delete a resource group and all its contained resources.

    **Warning**: This is a destructive operation that cannot be undone!
    """
    try:
        provider = get_provider(provider_type, subscription_id=subscription_id)

        success = await provider.delete_resource_group(resource_group_name)

        if success:
            return create_success_response(
                message=f"Resource group '{resource_group_name}' deletion initiated",
                data={"resource_group": resource_group_name}
            )
        else:
            return create_error_response(
                message=f"Resource group '{resource_group_name}' not found",
                status_code=404
            )

    except Exception as e:
        return create_error_response(
            message="Failed to delete resource group",
            details=str(e),
            status_code=500
        )


@app.get("/resource-groups/{resource_group_name}/resources",
    summary="List Resources in Group",
    response_model=StandardResponse,
    tags=["Resource Groups"])
async def list_resources_in_group(
    resource_group_name: str,
    provider_type: str = Query("azure", description="Provider type"),
    subscription_id: str = Query(..., description="Subscription/account ID")
):
    """
    List all resources within a resource group.

    Returns detailed information about each resource including
    type, location, and properties.
    """
    try:
        provider = get_provider(provider_type, subscription_id=subscription_id)
        resources = await provider.list_resources(resource_group_name)

        return create_success_response(
            message=f"Found {len(resources)} resources",
            data={
                "resource_group": resource_group_name,
                "resources": [
                    {
                        "id": resource.id,
                        "name": resource.name,
                        "type": resource.type,
                        "location": resource.location,
                        "tags": resource.tags
                    }
                    for resource in resources
                ],
                "count": len(resources)
            }
        )

    except Exception as e:
        return create_error_response(
            message="Failed to list resources",
            details=str(e),
            status_code=500
        )


# ==================== Error Handlers ====================

@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler."""
    logger.exception("Unhandled exception")
    return create_error_response(
        message="An unexpected error occurred",
        details=str(exc),
        status_code=500
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
