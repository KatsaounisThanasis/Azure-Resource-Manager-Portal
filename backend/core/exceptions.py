"""
Custom Exception Classes for Multi-Cloud Infrastructure Management

This module defines a unified exception hierarchy for consistent error handling.
"""

from typing import Optional, Dict, Any


class MultiCloudException(Exception):
    """
    Base exception for all multi-cloud manager errors.

    Provides a consistent error structure across the application.
    """
    def __init__(
        self,
        message: str,
        code: str,
        details: Optional[str] = None,
        status_code: int = 500
    ):
        self.message = message
        self.code = code
        self.details = details
        self.status_code = status_code
        super().__init__(self.message)

    def to_dict(self) -> Dict[str, Any]:
        """Convert exception to dictionary for API response"""
        error_dict = {
            "code": self.code,
            "message": self.message,
        }
        if self.details:
            error_dict["details"] = self.details
        return error_dict


# ================================================================
# Template & Configuration Errors
# ================================================================

class TemplateNotFoundError(MultiCloudException):
    """Raised when a requested template cannot be found."""
    def __init__(self, template_name: str, provider: str):
        super().__init__(
            message=f"Template '{template_name}' not found for provider '{provider}'",
            code="TEMPLATE_NOT_FOUND",
            details=f"Available templates can be listed via GET /templates?provider={provider}",
            status_code=404
        )


class TemplateParseError(MultiCloudException):
    """Raised when a template file cannot be parsed."""
    def __init__(self, template_name: str, reason: str):
        super().__init__(
            message=f"Failed to parse template '{template_name}'",
            code="TEMPLATE_PARSE_ERROR",
            details=reason,
            status_code=400
        )


class InvalidParameterError(MultiCloudException):
    """Raised when template parameters are invalid."""
    def __init__(self, parameter_name: str, reason: str):
        super().__init__(
            message=f"Invalid parameter '{parameter_name}'",
            code="INVALID_PARAMETER",
            details=reason,
            status_code=400
        )


class MissingParameterError(MultiCloudException):
    """Raised when required parameters are missing."""
    def __init__(self, parameter_name: str):
        super().__init__(
            message=f"Required parameter '{parameter_name}' is missing",
            code="MISSING_PARAMETER",
            details=f"Please provide '{parameter_name}' in the request parameters",
            status_code=400
        )


# ================================================================
# Provider & Authentication Errors
# ================================================================

class ProviderNotFoundError(MultiCloudException):
    """Raised when a cloud provider is not supported."""
    def __init__(self, provider_type: str):
        super().__init__(
            message=f"Provider '{provider_type}' is not supported",
            code="PROVIDER_NOT_FOUND",
            details="Supported providers: terraform-azure, terraform-gcp, terraform-aws",
            status_code=404
        )


class ProviderConfigurationError(MultiCloudException):
    """Raised when provider configuration is invalid."""
    def __init__(self, provider: str, reason: str):
        super().__init__(
            message=f"Provider '{provider}' configuration error",
            code="PROVIDER_CONFIG_ERROR",
            details=reason,
            status_code=500
        )


class AuthenticationError(MultiCloudException):
    """Raised when cloud provider authentication fails."""
    def __init__(self, provider: str, reason: str):
        super().__init__(
            message=f"Authentication failed for provider '{provider}'",
            code="AUTHENTICATION_ERROR",
            details=reason,
            status_code=401
        )


class AuthorizationError(MultiCloudException):
    """Raised when user lacks permissions for an operation."""
    def __init__(self, resource: str, action: str):
        super().__init__(
            message=f"Insufficient permissions to {action} {resource}",
            code="AUTHORIZATION_ERROR",
            details="Check your cloud provider IAM permissions",
            status_code=403
        )


# ================================================================
# Deployment Errors
# ================================================================

class DeploymentNotFoundError(MultiCloudException):
    """Raised when a deployment cannot be found."""
    def __init__(self, deployment_id: str):
        super().__init__(
            message=f"Deployment '{deployment_id}' not found",
            code="DEPLOYMENT_NOT_FOUND",
            details="The deployment may have been deleted or the ID is incorrect",
            status_code=404
        )


class DeploymentAlreadyExistsError(MultiCloudException):
    """Raised when attempting to create a duplicate deployment."""
    def __init__(self, deployment_id: str):
        super().__init__(
            message=f"Deployment '{deployment_id}' already exists",
            code="DEPLOYMENT_ALREADY_EXISTS",
            details="Use a different deployment ID or update the existing deployment",
            status_code=409
        )


class DeploymentFailedError(MultiCloudException):
    """Raised when a deployment fails during execution."""
    def __init__(self, deployment_id: str, reason: str):
        super().__init__(
            message=f"Deployment '{deployment_id}' failed",
            code="DEPLOYMENT_FAILED",
            details=reason,
            status_code=500
        )


class DeploymentTimeoutError(MultiCloudException):
    """Raised when a deployment exceeds the timeout limit."""
    def __init__(self, deployment_id: str, timeout_seconds: int):
        super().__init__(
            message=f"Deployment '{deployment_id}' timed out",
            code="DEPLOYMENT_TIMEOUT",
            details=f"Deployment exceeded the maximum time limit of {timeout_seconds} seconds",
            status_code=504
        )


# ================================================================
# Terraform Errors
# ================================================================

class TerraformValidationError(MultiCloudException):
    """Raised when terraform validate fails."""
    def __init__(self, reason: str):
        super().__init__(
            message="Terraform validation failed",
            code="TERRAFORM_VALIDATE_FAILED",
            details=reason,
            status_code=400
        )


class TerraformPlanError(MultiCloudException):
    """Raised when terraform plan fails."""
    def __init__(self, reason: str):
        super().__init__(
            message="Terraform plan generation failed",
            code="TERRAFORM_PLAN_FAILED",
            details=reason,
            status_code=500
        )


class TerraformApplyError(MultiCloudException):
    """Raised when terraform apply fails."""
    def __init__(self, reason: str):
        super().__init__(
            message="Terraform apply failed",
            code="TERRAFORM_APPLY_FAILED",
            details=reason,
            status_code=500
        )


class TerraformDestroyError(MultiCloudException):
    """Raised when terraform destroy fails."""
    def __init__(self, reason: str):
        super().__init__(
            message="Terraform destroy failed",
            code="TERRAFORM_DESTROY_FAILED",
            details=reason,
            status_code=500
        )


class TerraformStateError(MultiCloudException):
    """Raised when terraform state operations fail."""
    def __init__(self, reason: str):
        super().__init__(
            message="Terraform state operation failed",
            code="TERRAFORM_STATE_ERROR",
            details=reason,
            status_code=500
        )


# ================================================================
# Resource Errors
# ================================================================

class ResourceNotFoundError(MultiCloudException):
    """Raised when a cloud resource cannot be found."""
    def __init__(self, resource_type: str, resource_id: str):
        super().__init__(
            message=f"{resource_type} '{resource_id}' not found",
            code="RESOURCE_NOT_FOUND",
            details="The resource may have been deleted or does not exist",
            status_code=404
        )


class ResourceAlreadyExistsError(MultiCloudException):
    """Raised when attempting to create a resource that already exists."""
    def __init__(self, resource_type: str, resource_name: str):
        super().__init__(
            message=f"{resource_type} '{resource_name}' already exists",
            code="RESOURCE_ALREADY_EXISTS",
            details="Use a different name or update the existing resource",
            status_code=409
        )


class QuotaExceededError(MultiCloudException):
    """Raised when cloud provider quota is exceeded."""
    def __init__(self, resource_type: str, limit: int):
        super().__init__(
            message=f"Quota exceeded for {resource_type}",
            code="QUOTA_EXCEEDED",
            details=f"Current limit: {limit}. Request a quota increase from your cloud provider",
            status_code=429
        )


# ================================================================
# Database Errors
# ================================================================

class DatabaseError(MultiCloudException):
    """Raised when database operations fail."""
    def __init__(self, operation: str, reason: str):
        super().__init__(
            message=f"Database {operation} failed",
            code="DATABASE_ERROR",
            details=reason,
            status_code=500
        )


class DatabaseConnectionError(MultiCloudException):
    """Raised when cannot connect to database."""
    def __init__(self, reason: str):
        super().__init__(
            message="Failed to connect to database",
            code="DATABASE_CONNECTION_ERROR",
            details=reason,
            status_code=503
        )


# ================================================================
# Validation Errors
# ================================================================

class ValidationError(MultiCloudException):
    """Raised when request validation fails."""
    def __init__(self, field: str, reason: str):
        super().__init__(
            message=f"Validation failed for field '{field}'",
            code="VALIDATION_ERROR",
            details=reason,
            status_code=422
        )


class SchemaValidationError(MultiCloudException):
    """Raised when request doesn't match expected schema."""
    def __init__(self, reason: str):
        super().__init__(
            message="Request schema validation failed",
            code="SCHEMA_VALIDATION_ERROR",
            details=reason,
            status_code=422
        )


# ================================================================
# API Errors
# ================================================================

class RateLimitExceededError(MultiCloudException):
    """Raised when API rate limit is exceeded."""
    def __init__(self, retry_after: int):
        super().__init__(
            message="Rate limit exceeded",
            code="RATE_LIMIT_EXCEEDED",
            details=f"Please retry after {retry_after} seconds",
            status_code=429
        )


class ServiceUnavailableError(MultiCloudException):
    """Raised when service is temporarily unavailable."""
    def __init__(self, service: str, reason: str):
        super().__init__(
            message=f"Service '{service}' is temporarily unavailable",
            code="SERVICE_UNAVAILABLE",
            details=reason,
            status_code=503
        )


class InternalServerError(MultiCloudException):
    """Raised for unexpected internal errors."""
    def __init__(self, reason: Optional[str] = None):
        super().__init__(
            message="An internal server error occurred",
            code="INTERNAL_SERVER_ERROR",
            details=reason or "Please contact support if the problem persists",
            status_code=500
        )
