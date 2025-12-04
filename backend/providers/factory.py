"""
Provider Factory

Factory pattern implementation for creating cloud provider instances.
This allows dynamic provider selection based on configuration or user preference.
"""

import logging
from typing import Optional, Dict, Any

from .base import CloudProvider, ProviderType, ProviderConfigurationError
from .terraform_provider import TerraformProvider

logger = logging.getLogger(__name__)


class ProviderFactory:
    """
    Factory class for creating cloud provider instances.

    Note: All providers now use Terraform for multi-cloud support.

    Usage:
        provider = ProviderFactory.create_provider(
            provider_type="terraform-azure",
            subscription_id="xxx",
            region="eastus"
        )
    """

    # Registry of available providers - all use Terraform
    _providers: Dict[str, type] = {
        "terraform-azure": TerraformProvider,
        "terraform-gcp": TerraformProvider,
        "gcp": TerraformProvider,
        ProviderType.TERRAFORM.value: TerraformProvider,
    }

    @classmethod
    def register_provider(cls, provider_name: str, provider_class: type):
        """
        Register a new provider implementation.

        Args:
            provider_name: Name/identifier for the provider
            provider_class: Provider class (must inherit from CloudProvider)

        Raises:
            ValueError: If provider_class doesn't inherit from CloudProvider
        """
        if not issubclass(provider_class, CloudProvider):
            raise ValueError(
                f"Provider class {provider_class.__name__} must inherit from CloudProvider"
            )

        cls._providers[provider_name.lower()] = provider_class
        logger.info(f"Registered provider: {provider_name} -> {provider_class.__name__}")

    @classmethod
    def create_provider(
        cls,
        provider_type: str,
        subscription_id: Optional[str] = None,
        region: Optional[str] = None,
        **kwargs
    ) -> CloudProvider:
        """
        Create a cloud provider instance.

        Args:
            provider_type: Type of provider (e.g., "azure", "aws", "gcp", "terraform")
            subscription_id: Cloud subscription/account ID
            region: Default region for operations
            **kwargs: Additional provider-specific configuration

        Returns:
            CloudProvider instance

        Raises:
            ProviderConfigurationError: If provider type is not supported or configuration is invalid
        """
        provider_type_lower = provider_type.lower()

        if provider_type_lower not in cls._providers:
            available = ", ".join(cls._providers.keys())
            raise ProviderConfigurationError(
                f"Unsupported provider type: '{provider_type}'. Available providers: {available}",
                provider=provider_type
            )

        provider_class = cls._providers[provider_type_lower]

        try:
            logger.info(f"Creating provider instance: {provider_class.__name__}")
            provider = provider_class(
                subscription_id=subscription_id,
                region=region,
                **kwargs
            )
            logger.info(f"Provider created successfully: {provider_type}")
            return provider

        except Exception as e:
            logger.error(f"Failed to create provider '{provider_type}': {str(e)}")
            raise ProviderConfigurationError(
                f"Failed to initialize {provider_type} provider: {str(e)}",
                provider=provider_type
            )

    @classmethod
    def get_available_providers(cls) -> list[str]:
        """
        Get list of available provider types.

        Returns:
            List of provider type identifiers
        """
        return list(cls._providers.keys())

    @classmethod
    def is_provider_available(cls, provider_type: str) -> bool:
        """
        Check if a provider type is available.

        Args:
            provider_type: Provider type to check

        Returns:
            True if provider is registered
        """
        return provider_type.lower() in cls._providers


# Convenience function for creating providers
def get_provider(
    provider_type: str,
    subscription_id: Optional[str] = None,
    region: Optional[str] = None,
    **kwargs
) -> CloudProvider:
    """
    Convenience function to create a provider instance.

    Args:
        provider_type: Type of provider
        subscription_id: Cloud subscription/account ID
        region: Default region
        **kwargs: Additional configuration

    Returns:
        CloudProvider instance
    """
    return ProviderFactory.create_provider(
        provider_type=provider_type,
        subscription_id=subscription_id,
        region=region,
        **kwargs
    )
