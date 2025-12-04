"""
Security Utilities and Middleware

This module provides security headers, CORS configuration,
and other security-related utilities for the API.
"""

import os
from typing import Optional, List
from fastapi import Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp
import logging

logger = logging.getLogger(__name__)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    Middleware to add security headers to all responses.

    Headers added:
    - X-Content-Type-Options: nosniff
    - X-Frame-Options: DENY
    - X-XSS-Protection: 1; mode=block
    - Strict-Transport-Security: max-age=31536000; includeSubDomains
    - Content-Security-Policy: default-src 'self'
    - Referrer-Policy: strict-origin-when-cross-origin
    """

    async def dispatch(self, request: Request, call_next):
        """Add security headers to response."""
        response = await call_next(request)

        # Prevent MIME type sniffing
        response.headers["X-Content-Type-Options"] = "nosniff"

        # Prevent clickjacking
        response.headers["X-Frame-Options"] = "DENY"

        # Enable XSS filter
        response.headers["X-XSS-Protection"] = "1; mode=block"

        # Force HTTPS (only in production)
        if os.getenv("ENVIRONMENT", "development") == "production":
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains; preload"
            )

        # Content Security Policy
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data: https:; "
            "font-src 'self' data:; "
            "connect-src 'self';"
        )

        # Referrer policy
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

        # Remove server header (if exists)
        if "Server" in response.headers:
            del response.headers["Server"]

        return response


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """
    Middleware to log all incoming requests.

    Logs:
    - Request method and path
    - Client IP address
    - User agent
    - Response status code
    - Request duration
    """

    async def dispatch(self, request: Request, call_next):
        """Log request details."""
        import time

        # Get client info
        client_host = request.client.host if request.client else "unknown"
        forwarded_for = request.headers.get("X-Forwarded-For", "")
        user_agent = request.headers.get("User-Agent", "")

        # Log request
        logger.info(
            f"Request: {request.method} {request.url.path} "
            f"from {forwarded_for or client_host}"
        )

        # Process request and measure time
        start_time = time.time()
        response = await call_next(request)
        duration = time.time() - start_time

        # Log response
        logger.info(
            f"Response: {response.status_code} for {request.method} {request.url.path} "
            f"({duration:.3f}s)"
        )

        # Add custom header with request duration
        response.headers["X-Request-Duration"] = f"{duration:.3f}s"

        return response


def get_cors_config() -> dict:
    """
    Get CORS configuration from environment variables.

    Environment variables:
    - CORS_ORIGINS: Comma-separated list of allowed origins (default: *)
    - CORS_CREDENTIALS: Allow credentials (default: true)
    - CORS_METHODS: Allowed methods (default: *)
    - CORS_HEADERS: Allowed headers (default: *)

    Returns:
        Dictionary with CORS configuration
    """
    origins_str = os.getenv("CORS_ORIGINS", "*")

    # Parse origins
    if origins_str == "*":
        origins = ["*"]
    else:
        origins = [origin.strip() for origin in origins_str.split(",")]

    credentials = os.getenv("CORS_CREDENTIALS", "true").lower() == "true"
    methods_str = os.getenv("CORS_METHODS", "*")
    headers_str = os.getenv("CORS_HEADERS", "*")

    methods = ["*"] if methods_str == "*" else [m.strip() for m in methods_str.split(",")]
    headers = ["*"] if headers_str == "*" else [h.strip() for h in headers_str.split(",")]

    logger.info(f"CORS configuration: origins={origins}, credentials={credentials}")

    return {
        "allow_origins": origins,
        "allow_credentials": credentials,
        "allow_methods": methods,
        "allow_headers": headers,
        "expose_headers": [
            "X-Request-Duration",
            "X-RateLimit-Limit",
            "X-RateLimit-Remaining",
            "X-RateLimit-Reset"
        ],
        "max_age": 3600,  # Cache preflight requests for 1 hour
    }


def get_trusted_hosts() -> Optional[List[str]]:
    """
    Get list of trusted hosts from environment.

    Environment variables:
    - TRUSTED_HOSTS: Comma-separated list of trusted hosts

    Returns:
        List of trusted hosts or None to disable host validation
    """
    hosts_str = os.getenv("TRUSTED_HOSTS", "")

    if not hosts_str:
        # No host validation in development
        if os.getenv("ENVIRONMENT", "development") == "development":
            return None
        # In production, at least validate localhost
        return ["localhost", "127.0.0.1"]

    hosts = [host.strip() for host in hosts_str.split(",")]
    logger.info(f"Trusted hosts: {hosts}")
    return hosts


def sanitize_string(value: str, max_length: int = 1000) -> str:
    """
    Sanitize user input string.

    Args:
        value: Input string to sanitize
        max_length: Maximum allowed length

    Returns:
        Sanitized string
    """
    # Remove null bytes
    value = value.replace("\x00", "")

    # Limit length
    if len(value) > max_length:
        value = value[:max_length]

    return value


def sanitize_filename(filename: str) -> str:
    """
    Sanitize filename to prevent path traversal attacks.

    Args:
        filename: Original filename

    Returns:
        Sanitized filename
    """
    import re
    from pathlib import Path

    # Remove any path components
    filename = Path(filename).name

    # Remove any non-alphanumeric characters except dots, dashes, underscores
    filename = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)

    # Prevent hidden files
    if filename.startswith('.'):
        filename = '_' + filename[1:]

    # Ensure not empty
    if not filename:
        filename = "unnamed_file"

    return filename


def validate_deployment_parameters(parameters: dict) -> tuple[bool, Optional[str]]:
    """
    Validate deployment parameters for security issues.

    Checks for:
    - Command injection attempts
    - Path traversal attempts
    - Excessive parameter sizes
    - Dangerous parameter names

    Args:
        parameters: Deployment parameters to validate

    Returns:
        Tuple of (is_valid, error_message)
    """
    import re

    # Dangerous patterns
    dangerous_patterns = [
        r'[;&|`$]',  # Shell metacharacters
        r'\.\./|\.\.\\',  # Path traversal
        r'<script',  # XSS attempts
        r'DROP\s+TABLE',  # SQL injection attempts
        r'eval\s*\(',  # Code execution
    ]

    # Dangerous parameter names
    dangerous_names = [
        'password', 'secret', 'token', 'private_key',
        'admin', 'root', 'sudo'
    ]

    # Maximum sizes
    MAX_PARAM_NAME_LENGTH = 100
    MAX_PARAM_VALUE_LENGTH = 10000
    MAX_PARAMS_COUNT = 100

    # Check parameter count
    if len(parameters) > MAX_PARAMS_COUNT:
        return False, f"Too many parameters (max: {MAX_PARAMS_COUNT})"

    for key, value in parameters.items():
        # Check parameter name length
        if len(key) > MAX_PARAM_NAME_LENGTH:
            return False, f"Parameter name too long: {key[:50]}..."

        # Check for dangerous parameter names (warning only)
        key_lower = key.lower()
        for dangerous_name in dangerous_names:
            if dangerous_name in key_lower:
                logger.warning(f"Potentially sensitive parameter name: {key}")

        # Convert value to string for checking
        value_str = str(value)

        # Check value length
        if len(value_str) > MAX_PARAM_VALUE_LENGTH:
            return False, f"Parameter value too long for '{key}'"

        # Check for dangerous patterns
        for pattern in dangerous_patterns:
            if re.search(pattern, value_str, re.IGNORECASE):
                return False, f"Potentially dangerous value in parameter '{key}': contains '{pattern}'"

    return True, None


def mask_sensitive_data(data: dict) -> dict:
    """
    Mask sensitive data in dictionaries for logging.

    Args:
        data: Dictionary potentially containing sensitive data

    Returns:
        Dictionary with sensitive values masked
    """
    import copy

    # Sensitive keys to mask
    sensitive_keys = [
        'password', 'secret', 'token', 'api_key', 'private_key',
        'client_secret', 'access_token', 'refresh_token',
        'credentials', 'auth', 'authorization'
    ]

    masked = copy.deepcopy(data)

    def mask_dict(d):
        """Recursively mask sensitive keys."""
        if not isinstance(d, dict):
            return d

        for key, value in d.items():
            key_lower = key.lower()

            # Check if key is sensitive
            if any(sensitive in key_lower for sensitive in sensitive_keys):
                if isinstance(value, str) and len(value) > 4:
                    # Show first and last 2 characters
                    d[key] = value[:2] + "***" + value[-2:]
                else:
                    d[key] = "***"
            elif isinstance(value, dict):
                # Recursively mask nested dictionaries
                d[key] = mask_dict(value)
            elif isinstance(value, list):
                # Handle lists of dictionaries
                d[key] = [mask_dict(item) if isinstance(item, dict) else item for item in value]

        return d

    return mask_dict(masked)


class SecurityConfig:
    """
    Central security configuration.

    Loads security settings from environment variables
    and provides a unified interface for security features.
    """

    def __init__(self):
        """Initialize security configuration."""
        self.environment = os.getenv("ENVIRONMENT", "development")
        self.debug = os.getenv("DEBUG", "false").lower() == "true"

        # Authentication
        self.auth_enabled = os.getenv("API_AUTH_ENABLED", "false").lower() == "true"
        self.api_key = os.getenv("API_KEY", "")

        # Rate limiting
        self.rate_limit_enabled = os.getenv("RATE_LIMIT_ENABLED", "true").lower() == "true"
        self.rate_limit_requests = int(os.getenv("RATE_LIMIT_REQUESTS", "60"))

        # CORS
        self.cors_origins = os.getenv("CORS_ORIGINS", "*")

        # Trusted hosts
        self.trusted_hosts = get_trusted_hosts()

        # Key vault (for production)
        self.use_key_vault = os.getenv("USE_KEY_VAULT", "false").lower() == "true"
        self.key_vault_url = os.getenv("KEY_VAULT_URL", "")

        self._log_config()

    def _log_config(self):
        """Log security configuration (without sensitive data)."""
        logger.info("=" * 60)
        logger.info("Security Configuration:")
        logger.info(f"  Environment: {self.environment}")
        logger.info(f"  Debug Mode: {self.debug}")
        logger.info(f"  Authentication: {'Enabled' if self.auth_enabled else 'Disabled'}")
        logger.info(f"  Rate Limiting: {'Enabled' if self.rate_limit_enabled else 'Disabled'}")
        logger.info(f"  CORS Origins: {self.cors_origins}")
        logger.info(f"  Key Vault: {'Enabled' if self.use_key_vault else 'Disabled'}")
        logger.info("=" * 60)

    def is_production(self) -> bool:
        """Check if running in production."""
        return self.environment == "production"

    def is_development(self) -> bool:
        """Check if running in development."""
        return self.environment == "development"


# Global security configuration
security_config = SecurityConfig()
