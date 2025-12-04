"""
Azure API Client

Client for interacting with various Azure REST APIs:
- Azure Retail Prices API (public, no auth)
- Azure Management API (requires authentication)
"""

import os
import logging
import httpx
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
from functools import lru_cache

logger = logging.getLogger(__name__)

# Try to import Azure Identity for authentication
try:
    from azure.identity import ClientSecretCredential, AzureCliCredential, DefaultAzureCredential
    AZURE_IDENTITY_AVAILABLE = True
except ImportError:
    AZURE_IDENTITY_AVAILABLE = False
    logger.warning("azure-identity not installed - Management API calls will be limited")

# Azure Retail Prices API - Public endpoint (no authentication required)
AZURE_RETAIL_PRICES_API = "https://prices.azure.com/api/retail/prices"

# Azure Management API - Requires authentication
AZURE_MANAGEMENT_API = "https://management.azure.com"


class AzureAPIClient:
    """Client for Azure REST APIs"""

    def __init__(self, subscription_id: Optional[str] = None, access_token: Optional[str] = None):
        """
        Initialize Azure API client.

        Args:
            subscription_id: Azure subscription ID (for Management API)
            access_token: Azure access token (for Management API, will be auto-obtained if not provided)
        """
        self.subscription_id = subscription_id or os.getenv("AZURE_SUBSCRIPTION_ID")
        self.access_token = access_token
        self._credential = None
        self.client = httpx.AsyncClient(timeout=30.0)

        # Initialize Azure credential if available and access_token not provided
        if not self.access_token and AZURE_IDENTITY_AVAILABLE:
            self._initialize_credential()

    async def close(self):
        """Close HTTP client"""
        await self.client.aclose()

    def _initialize_credential(self):
        """Initialize Azure credential for authentication"""
        try:
            tenant_id = os.getenv("AZURE_TENANT_ID")
            client_id = os.getenv("AZURE_CLIENT_ID")
            client_secret = os.getenv("AZURE_CLIENT_SECRET")

            # Try Service Principal first if all credentials are provided
            if tenant_id and client_id and client_secret:
                logger.info("Initializing Azure authentication with Service Principal")
                self._credential = ClientSecretCredential(
                    tenant_id=tenant_id,
                    client_id=client_id,
                    client_secret=client_secret
                )
            else:
                # Fallback to DefaultAzureCredential (tries multiple methods including Azure CLI)
                logger.info("Initializing Azure authentication with DefaultAzureCredential")
                self._credential = DefaultAzureCredential()

        except Exception as e:
            logger.warning(f"Failed to initialize Azure credential: {e}")
            self._credential = None

    def _get_access_token(self) -> Optional[str]:
        """Get or refresh Azure access token"""
        if self.access_token:
            return self.access_token

        if not self._credential:
            return None

        try:
            # Get token for Azure Management API
            token = self._credential.get_token("https://management.azure.com/.default")
            return token.token
        except Exception as e:
            logger.error(f"Failed to get Azure access token: {e}")
            return None

    # ==================== Azure Retail Prices API ====================
    # Public API - No authentication required

    async def get_vm_pricing(
        self,
        vm_size: str,
        region: str,
        operating_system: str = "Linux"
    ) -> Optional[Dict[str, Any]]:
        """
        Get real-time pricing for Azure VM from Retail Prices API.

        This is a PUBLIC API - no authentication required!

        Args:
            vm_size: VM size (e.g., "Standard_B2s")
            region: Azure region (e.g., "westeurope", "eastus")
            operating_system: "Linux" or "Windows"

        Returns:
            Pricing information or None if not found
        """
        try:
            # Build filter for the API
            # Format: serviceName eq 'Virtual Machines' and armSkuName eq 'Standard_B2s' and armRegionName eq 'westeurope'
            filter_query = (
                f"serviceName eq 'Virtual Machines' "
                f"and armSkuName eq '{vm_size}' "
                f"and armRegionName eq '{region}' "
                f"and priceType eq 'Consumption'"
            )

            # Add OS filter
            if operating_system.lower() == "windows":
                filter_query += " and productName contains 'Windows'"
            else:
                filter_query += " and productName contains 'Linux'"

            params = {
                "$filter": filter_query,
                "currencyCode": "USD"
            }

            logger.info(f"Fetching Azure VM pricing for {vm_size} in {region}")

            response = await self.client.get(
                AZURE_RETAIL_PRICES_API,
                params=params
            )
            response.raise_for_status()

            data = response.json()
            items = data.get("Items", [])

            if not items:
                logger.warning(f"No pricing found for {vm_size} in {region}")
                return None

            # Get the first result (usually compute pricing)
            pricing = items[0]

            return {
                "vm_size": vm_size,
                "region": region,
                "operating_system": operating_system,
                "retail_price_per_hour": pricing.get("retailPrice", 0.0),
                "retail_price_per_month": pricing.get("retailPrice", 0.0) * 730,  # Average hours per month
                "unit_of_measure": pricing.get("unitOfMeasure", "1 Hour"),
                "currency": pricing.get("currencyCode", "USD"),
                "product_name": pricing.get("productName", ""),
                "sku_name": pricing.get("skuName", ""),
                "meter_name": pricing.get("meterName", ""),
                "last_updated": datetime.utcnow().isoformat()
            }

        except httpx.HTTPError as e:
            logger.error(f"HTTP error fetching Azure pricing: {e}")
            return None
        except Exception as e:
            logger.error(f"Error fetching Azure pricing: {e}")
            return None

    async def get_storage_pricing(
        self,
        storage_type: str,
        region: str,
        redundancy: str = "LRS"
    ) -> Optional[Dict[str, Any]]:
        """
        Get real-time pricing for Azure Storage.

        Args:
            storage_type: Storage type (e.g., "Standard", "Premium")
            region: Azure region
            redundancy: Storage redundancy (LRS, GRS, ZRS, etc.)

        Returns:
            Pricing information or None if not found
        """
        try:
            filter_query = (
                f"serviceName eq 'Storage' "
                f"and armRegionName eq '{region}' "
                f"and priceType eq 'Consumption'"
            )

            # Add redundancy filter
            if redundancy:
                filter_query += f" and skuName contains '{redundancy}'"

            params = {
                "$filter": filter_query,
                "currencyCode": "USD"
            }

            logger.info(f"Fetching Azure Storage pricing for {storage_type}/{redundancy} in {region}")

            response = await self.client.get(
                AZURE_RETAIL_PRICES_API,
                params=params
            )
            response.raise_for_status()

            data = response.json()
            items = data.get("Items", [])

            if not items:
                logger.warning(f"No storage pricing found for {storage_type}/{redundancy} in {region}")
                return None

            # Filter for block blob storage (most common)
            block_blob_items = [
                item for item in items
                if "Block Blob" in item.get("productName", "")
                and "Data Stored" in item.get("meterName", "")
            ]

            if not block_blob_items:
                block_blob_items = items

            pricing = block_blob_items[0]

            return {
                "storage_type": storage_type,
                "redundancy": redundancy,
                "region": region,
                "price_per_gb_month": pricing.get("retailPrice", 0.0),
                "unit_of_measure": pricing.get("unitOfMeasure", "1 GB/Month"),
                "currency": pricing.get("currencyCode", "USD"),
                "product_name": pricing.get("productName", ""),
                "sku_name": pricing.get("skuName", ""),
                "meter_name": pricing.get("meterName", ""),
                "last_updated": datetime.utcnow().isoformat()
            }

        except Exception as e:
            logger.error(f"Error fetching Azure storage pricing: {e}")
            return None

    async def get_disk_pricing(
        self,
        disk_type: str,
        region: str,
        size_gb: Optional[int] = None
    ) -> Optional[Dict[str, Any]]:
        """
        Get real-time pricing for Azure Managed Disks.

        Args:
            disk_type: Disk type (Standard_LRS, Premium_LRS, StandardSSD_LRS)
            region: Azure region
            size_gb: Optional disk size for tier-based pricing

        Returns:
            Pricing information or None if not found
        """
        try:
            # Map common names to service names
            disk_service_map = {
                "Standard_LRS": "Standard HDD Managed Disks",
                "StandardSSD_LRS": "Standard SSD Managed Disks",
                "Premium_LRS": "Premium SSD Managed Disks",
                "PremiumV2_LRS": "Premium SSD v2 Managed Disks"
            }

            service_name = disk_service_map.get(disk_type, "Standard SSD Managed Disks")

            filter_query = (
                f"serviceName eq '{service_name}' "
                f"and armRegionName eq '{region}' "
                f"and priceType eq 'Consumption'"
            )

            params = {
                "$filter": filter_query,
                "currencyCode": "USD"
            }

            logger.info(f"Fetching Azure Disk pricing for {disk_type} in {region}")

            response = await self.client.get(
                AZURE_RETAIL_PRICES_API,
                params=params
            )
            response.raise_for_status()

            data = response.json()
            items = data.get("Items", [])

            if not items:
                logger.warning(f"No disk pricing found for {disk_type} in {region}")
                return None

            # If size is specified, try to find the appropriate tier
            if size_gb:
                # Find closest tier
                for item in items:
                    meter_name = item.get("meterName", "")
                    if "Provisioned" in meter_name or "Disk" in meter_name:
                        pricing = item
                        break
            else:
                pricing = items[0]

            return {
                "disk_type": disk_type,
                "region": region,
                "price_per_month": pricing.get("retailPrice", 0.0),
                "unit_of_measure": pricing.get("unitOfMeasure", "1/Month"),
                "currency": pricing.get("currencyCode", "USD"),
                "product_name": pricing.get("productName", ""),
                "sku_name": pricing.get("skuName", ""),
                "meter_name": pricing.get("meterName", ""),
                "last_updated": datetime.utcnow().isoformat()
            }

        except Exception as e:
            logger.error(f"Error fetching Azure disk pricing: {e}")
            return None

    # ==================== Azure Management API ====================
    # Requires authentication

    def _get_management_headers(self) -> Dict[str, str]:
        """Get headers for Azure Management API requests"""
        access_token = self._get_access_token()
        if not access_token:
            raise ValueError("Access token required for Azure Management API. Please configure Azure credentials.")

        return {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }

    async def get_vm_sizes_for_region(self, location: str) -> List[Dict[str, Any]]:
        """
        Get available VM sizes for a specific region.

        Requires authentication.

        Args:
            location: Azure location (e.g., "eastus", "westeurope")

        Returns:
            List of VM size information
        """
        if not self.subscription_id:
            raise ValueError("Subscription ID required")

        try:
            url = (
                f"{AZURE_MANAGEMENT_API}/subscriptions/{self.subscription_id}"
                f"/providers/Microsoft.Compute/locations/{location}/vmSizes"
            )

            params = {"api-version": "2023-03-01"}

            logger.info(f"Fetching available VM sizes for region: {location}")

            response = await self.client.get(
                url,
                headers=self._get_management_headers(),
                params=params
            )
            response.raise_for_status()

            data = response.json()
            vm_sizes = data.get("value", [])

            return [
                {
                    "name": vm.get("name"),
                    "number_of_cores": vm.get("numberOfCores"),
                    "memory_in_mb": vm.get("memoryInMB"),
                    "max_data_disk_count": vm.get("maxDataDiskCount"),
                    "os_disk_size_in_mb": vm.get("osDiskSizeInMB"),
                    "resource_disk_size_in_mb": vm.get("resourceDiskSizeInMB")
                }
                for vm in vm_sizes
            ]

        except httpx.HTTPError as e:
            logger.error(f"HTTP error fetching VM sizes: {e}")
            return []
        except Exception as e:
            logger.error(f"Error fetching VM sizes: {e}")
            return []

    async def get_locations(self) -> List[Dict[str, Any]]:
        """
        Get all available Azure locations/regions.

        Requires authentication.

        Returns:
            List of location information
        """
        if not self.subscription_id:
            raise ValueError("Subscription ID required")

        try:
            url = (
                f"{AZURE_MANAGEMENT_API}/subscriptions/{self.subscription_id}"
                f"/locations"
            )

            params = {"api-version": "2022-12-01"}

            logger.info("Fetching available Azure locations")

            response = await self.client.get(
                url,
                headers=self._get_management_headers(),
                params=params
            )
            response.raise_for_status()

            data = response.json()
            locations = data.get("value", [])

            return [
                {
                    "name": loc.get("name"),
                    "display_name": loc.get("displayName"),
                    "regional_display_name": loc.get("regionalDisplayName")
                }
                for loc in locations
            ]

        except Exception as e:
            logger.error(f"Error fetching Azure locations: {e}")
            return []


# Global client instance (for public APIs that don't need auth)
_public_client: Optional[AzureAPIClient] = None


async def get_azure_public_client() -> AzureAPIClient:
    """Get or create Azure public API client (for Retail Prices API)"""
    global _public_client
    if _public_client is None:
        _public_client = AzureAPIClient()
    return _public_client
