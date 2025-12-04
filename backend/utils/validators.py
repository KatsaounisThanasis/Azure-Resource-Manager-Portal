"""
Parameter Validation Module for Multi-Cloud Infrastructure Management

This module provides validation logic for template parameters and deployment requests.
"""

from typing import Dict, Any, List, Optional, Tuple
import re
from backend.core.exceptions import (
    InvalidParameterError,
    MissingParameterError,
    ValidationError
)


class ParameterValidator:
    """
    Validates template parameters against rules and constraints.
    """

    # Common regex patterns
    PATTERNS = {
        'azure_resource_name': r'^[a-zA-Z0-9\-_]{1,64}$',
        'azure_storage_account': r'^[a-z0-9]{3,24}$',
        'gcp_resource_name': r'^[a-z]([-a-z0-9]*[a-z0-9])?$',
        'gcp_project_id': r'^[a-z]([-a-z0-9]*[a-z0-9])?$',
        'email': r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
        'ipv4': r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
        'cidr': r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/([0-9]|[12][0-9]|3[0-2])$',
    }

    @staticmethod
    def validate_required_fields(
        parameters: Dict[str, Any],
        required_fields: List[str]
    ) -> None:
        """
        Validate that all required fields are present.

        Raises:
            MissingParameterError: If a required field is missing
        """
        for field in required_fields:
            if field not in parameters or parameters[field] is None or parameters[field] == '':
                raise MissingParameterError(field)

    @staticmethod
    def validate_string_length(
        value: str,
        param_name: str,
        min_length: Optional[int] = None,
        max_length: Optional[int] = None
    ) -> None:
        """
        Validate string length constraints.

        Raises:
            InvalidParameterError: If length constraints are violated
        """
        if not isinstance(value, str):
            raise InvalidParameterError(param_name, "Must be a string")

        length = len(value)

        if min_length is not None and length < min_length:
            raise InvalidParameterError(
                param_name,
                f"Must be at least {min_length} characters (got {length})"
            )

        if max_length is not None and length > max_length:
            raise InvalidParameterError(
                param_name,
                f"Must be at most {max_length} characters (got {length})"
            )

    @staticmethod
    def validate_pattern(
        value: str,
        param_name: str,
        pattern: str,
        pattern_description: str = "the required format"
    ) -> None:
        """
        Validate string against a regex pattern.

        Raises:
            InvalidParameterError: If pattern doesn't match
        """
        if not isinstance(value, str):
            raise InvalidParameterError(param_name, "Must be a string")

        if not re.match(pattern, value):
            raise InvalidParameterError(
                param_name,
                f"Must match {pattern_description}"
            )

    @staticmethod
    def validate_enum(
        value: str,
        param_name: str,
        allowed_values: List[str]
    ) -> None:
        """
        Validate that value is one of the allowed values.

        Raises:
            InvalidParameterError: If value is not in allowed_values
        """
        if value not in allowed_values:
            raise InvalidParameterError(
                param_name,
                f"Must be one of: {', '.join(allowed_values)}"
            )

    @staticmethod
    def validate_integer_range(
        value: int,
        param_name: str,
        min_value: Optional[int] = None,
        max_value: Optional[int] = None
    ) -> None:
        """
        Validate integer range constraints.

        Raises:
            InvalidParameterError: If range constraints are violated
        """
        if not isinstance(value, int):
            raise InvalidParameterError(param_name, "Must be an integer")

        if min_value is not None and value < min_value:
            raise InvalidParameterError(
                param_name,
                f"Must be at least {min_value} (got {value})"
            )

        if max_value is not None and value > max_value:
            raise InvalidParameterError(
                param_name,
                f"Must be at most {max_value} (got {value})"
            )

    @staticmethod
    def validate_azure_storage_account_name(name: str) -> None:
        """
        Validate Azure Storage Account naming rules.

        Rules:
        - 3-24 characters
        - Lowercase letters and numbers only
        - Must be globally unique

        Raises:
            InvalidParameterError: If validation fails
        """
        ParameterValidator.validate_string_length(name, 'storage_account_name', 3, 24)
        ParameterValidator.validate_pattern(
            name,
            'storage_account_name',
            ParameterValidator.PATTERNS['azure_storage_account'],
            "lowercase letters and numbers only"
        )

    @staticmethod
    def validate_azure_resource_group_name(name: str) -> None:
        """
        Validate Azure Resource Group naming rules.

        Rules:
        - 1-90 characters
        - Alphanumerics, underscores, parentheses, hyphens, periods
        - Cannot end in period

        Raises:
            InvalidParameterError: If validation fails
        """
        ParameterValidator.validate_string_length(name, 'resource_group', 1, 90)

        if name.endswith('.'):
            raise InvalidParameterError(
                'resource_group',
                "Cannot end with a period"
            )

        if not re.match(r'^[\w\-\.\(\)]+$', name):
            raise InvalidParameterError(
                'resource_group',
                "Can only contain alphanumerics, underscores, hyphens, periods, and parentheses"
            )

    @staticmethod
    def validate_gcp_resource_name(name: str, param_name: str = 'resource_name') -> None:
        """
        Validate GCP resource naming rules.

        Rules:
        - Lowercase letters, numbers, and hyphens
        - Must start with a letter
        - Must end with a letter or number

        Raises:
            InvalidParameterError: If validation fails
        """
        ParameterValidator.validate_pattern(
            name,
            param_name,
            ParameterValidator.PATTERNS['gcp_resource_name'],
            "lowercase letters, numbers, hyphens; must start with letter"
        )

    @staticmethod
    def validate_gcp_project_id(project_id: str) -> None:
        """
        Validate GCP Project ID naming rules.

        Rules:
        - 6-30 characters
        - Lowercase letters, numbers, and hyphens
        - Must start with a letter
        - Must end with a letter or number

        Raises:
            InvalidParameterError: If validation fails
        """
        ParameterValidator.validate_string_length(project_id, 'project_id', 6, 30)
        ParameterValidator.validate_gcp_resource_name(project_id, 'project_id')

    @staticmethod
    def validate_ip_address(ip: str, param_name: str = 'ip_address') -> None:
        """
        Validate IPv4 address format.

        Raises:
            InvalidParameterError: If not a valid IPv4 address
        """
        ParameterValidator.validate_pattern(
            ip,
            param_name,
            ParameterValidator.PATTERNS['ipv4'],
            "valid IPv4 address (e.g., 192.168.1.1)"
        )

    @staticmethod
    def validate_cidr(cidr: str, param_name: str = 'cidr_block') -> None:
        """
        Validate CIDR notation.

        Raises:
            InvalidParameterError: If not valid CIDR notation
        """
        ParameterValidator.validate_pattern(
            cidr,
            param_name,
            ParameterValidator.PATTERNS['cidr'],
            "valid CIDR notation (e.g., 10.0.0.0/16)"
        )


class DeploymentRequestValidator:
    """
    Validates deployment request payloads.
    """

    @staticmethod
    def validate_deployment_request(
        provider_type: str,
        template_name: str,
        resource_group: str,
        location: str,
        parameters: Dict[str, Any]
    ) -> Tuple[bool, Optional[str]]:
        """
        Validate a complete deployment request.

        Returns:
            Tuple[bool, Optional[str]]: (is_valid, error_message)
        """
        try:
            # Validate core fields
            if not provider_type:
                raise ValidationError('provider_type', 'Provider type is required')

            if not template_name:
                raise ValidationError('template_name', 'Template name is required')

            if not resource_group:
                raise ValidationError('resource_group', 'Resource group is required')

            if not location:
                raise ValidationError('location', 'Location is required')

            # Provider-specific validation
            if 'azure' in provider_type.lower():
                ParameterValidator.validate_azure_resource_group_name(resource_group)

            return True, None

        except (InvalidParameterError, ValidationError, MissingParameterError) as e:
            return False, str(e)
        except Exception as e:
            return False, f"Validation error: {str(e)}"


# Convenience functions
def validate_azure_storage_account(name: str) -> None:
    """Validate Azure Storage Account name"""
    ParameterValidator.validate_azure_storage_account_name(name)


def validate_gcp_bucket_name(name: str) -> None:
    """
    Validate GCP Storage Bucket name.

    Rules similar to GCP resource names but with additional constraints.
    """
    ParameterValidator.validate_string_length(name, 'bucket_name', 3, 63)
    ParameterValidator.validate_gcp_resource_name(name, 'bucket_name')
