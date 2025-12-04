"""
GCP API Client

Client for interacting with various GCP REST APIs:
- Cloud Billing Catalog API (for pricing)
- Compute Engine API (for machine types, zones, etc.)
"""

import os
import logging
import httpx
from typing import Dict, List, Any, Optional
from datetime import datetime
import json

logger = logging.getLogger(__name__)

# Try to import Google auth libraries
try:
    from google.auth import default as google_auth_default
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account
    GOOGLE_AUTH_AVAILABLE = True
except ImportError:
    GOOGLE_AUTH_AVAILABLE = False
    logger.warning("google-auth not installed - GCP Management API calls will be limited")

# GCP API endpoints
GCP_CLOUD_BILLING_API = "https://cloudbilling.googleapis.com/v1"
GCP_COMPUTE_API = "https://compute.googleapis.com/compute/v1"


class GCPAPIClient:
    """Client for GCP REST APIs"""

    def __init__(self, project_id: Optional[str] = None, access_token: Optional[str] = None):
        """
        Initialize GCP API client.

        Args:
            project_id: GCP project ID
            access_token: GCP access token (will be auto-obtained if not provided)
        """
        self.project_id = project_id or os.getenv("GOOGLE_PROJECT_ID")
        self.access_token = access_token
        self._credentials = None
        self.client = httpx.AsyncClient(timeout=30.0)

        # Initialize Google credentials if available and access_token not provided
        if not self.access_token and GOOGLE_AUTH_AVAILABLE:
            self._initialize_credentials()

    async def close(self):
        """Close HTTP client"""
        await self.client.aclose()

    def _initialize_credentials(self):
        """Initialize Google credentials for authentication"""
        try:
            # Check for service account JSON file
            credentials_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

            if credentials_path and os.path.exists(credentials_path):
                logger.info("Initializing GCP authentication with service account JSON")
                self._credentials = service_account.Credentials.from_service_account_file(
                    credentials_path,
                    scopes=["https://www.googleapis.com/auth/cloud-platform"]
                )
            else:
                # Fallback to Application Default Credentials
                logger.info("Initializing GCP authentication with Application Default Credentials")
                self._credentials, project = google_auth_default(
                    scopes=["https://www.googleapis.com/auth/cloud-platform"]
                )
                if not self.project_id and project:
                    self.project_id = project

        except Exception as e:
            logger.warning(f"Failed to initialize GCP credentials: {e}")
            self._credentials = None

    def _get_access_token(self) -> Optional[str]:
        """Get or refresh GCP access token"""
        if self.access_token:
            return self.access_token

        if not self._credentials:
            return None

        try:
            # Refresh token if needed
            if not self._credentials.valid:
                self._credentials.refresh(Request())

            return self._credentials.token
        except Exception as e:
            logger.error(f"Failed to get GCP access token: {e}")
            return None

    def _get_headers(self) -> Dict[str, str]:
        """Get headers for GCP API requests"""
        headers = {"Content-Type": "application/json"}

        access_token = self._get_access_token()
        if access_token:
            headers["Authorization"] = f"Bearer {access_token}"

        return headers

    # ==================== GCP Cloud Billing Catalog API ====================

    async def get_compute_pricing(
        self,
        machine_type: str,
        region: str
    ) -> Optional[Dict[str, Any]]:
        """
        Get pricing for GCP Compute Engine instance.

        Note: GCP Billing API requires authentication and is complex.
        For now, we'll use a simplified pricing database with common types.

        Args:
            machine_type: Machine type (e.g., "e2-medium", "n1-standard-2")
            region: GCP region (e.g., "us-central1", "europe-west1")

        Returns:
            Pricing information
        """
        # Simplified pricing database for common machine types
        # Prices are approximate monthly costs (730 hours)
        # Source: https://cloud.google.com/compute/all-pricing

        base_pricing = {
            # E2 series (cost-optimized)
            "e2-micro": {"vcpu": 0.25, "memory_gb": 1, "price_per_month": 6.11},
            "e2-small": {"vcpu": 0.5, "memory_gb": 2, "price_per_month": 12.22},
            "e2-medium": {"vcpu": 1, "memory_gb": 4, "price_per_month": 24.44},
            "e2-standard-2": {"vcpu": 2, "memory_gb": 8, "price_per_month": 48.88},
            "e2-standard-4": {"vcpu": 4, "memory_gb": 16, "price_per_month": 97.76},
            "e2-standard-8": {"vcpu": 8, "memory_gb": 32, "price_per_month": 195.52},

            # N1 series (first-generation, general-purpose)
            "n1-standard-1": {"vcpu": 1, "memory_gb": 3.75, "price_per_month": 24.95},
            "n1-standard-2": {"vcpu": 2, "memory_gb": 7.5, "price_per_month": 49.90},
            "n1-standard-4": {"vcpu": 4, "memory_gb": 15, "price_per_month": 99.80},
            "n1-standard-8": {"vcpu": 8, "memory_gb": 30, "price_per_month": 199.60},
            "n1-highmem-2": {"vcpu": 2, "memory_gb": 13, "price_per_month": 67.14},
            "n1-highmem-4": {"vcpu": 4, "memory_gb": 26, "price_per_month": 134.28},
            "n1-highcpu-2": {"vcpu": 2, "memory_gb": 1.8, "price_per_month": 36.62},
            "n1-highcpu-4": {"vcpu": 4, "memory_gb": 3.6, "price_per_month": 73.24},

            # N2 series (second-generation, balanced)
            "n2-standard-2": {"vcpu": 2, "memory_gb": 8, "price_per_month": 60.74},
            "n2-standard-4": {"vcpu": 4, "memory_gb": 16, "price_per_month": 121.48},
            "n2-standard-8": {"vcpu": 8, "memory_gb": 32, "price_per_month": 242.96},
            "n2-highmem-2": {"vcpu": 2, "memory_gb": 16, "price_per_month": 81.76},
            "n2-highmem-4": {"vcpu": 4, "memory_gb": 32, "price_per_month": 163.52},
            "n2-highcpu-2": {"vcpu": 2, "memory_gb": 2, "price_per_month": 44.50},
            "n2-highcpu-4": {"vcpu": 4, "memory_gb": 4, "price_per_month": 89.00},

            # N2D series (AMD-based)
            "n2d-standard-2": {"vcpu": 2, "memory_gb": 8, "price_per_month": 48.91},
            "n2d-standard-4": {"vcpu": 4, "memory_gb": 16, "price_per_month": 97.82},
            "n2d-standard-8": {"vcpu": 8, "memory_gb": 32, "price_per_month": 195.64},

            # C2 series (compute-optimized)
            "c2-standard-4": {"vcpu": 4, "memory_gb": 16, "price_per_month": 152.73},
            "c2-standard-8": {"vcpu": 8, "memory_gb": 32, "price_per_month": 305.46},
            "c2-standard-16": {"vcpu": 16, "memory_gb": 64, "price_per_month": 610.92},
        }

        pricing_info = base_pricing.get(machine_type.lower())

        if not pricing_info:
            logger.warning(f"No pricing found for machine type: {machine_type}")
            return None

        # Regional pricing adjustments (approximate)
        region_multipliers = {
            "us-central1": 1.0,
            "us-east1": 1.0,
            "us-west1": 1.0,
            "europe-west1": 1.08,
            "europe-west2": 1.10,
            "asia-southeast1": 1.12,
            "asia-northeast1": 1.15,
        }

        multiplier = region_multipliers.get(region, 1.0)
        adjusted_price = pricing_info["price_per_month"] * multiplier

        return {
            "machine_type": machine_type,
            "region": region,
            "vcpu_count": pricing_info["vcpu"],
            "memory_gb": pricing_info["memory_gb"],
            "price_per_month": round(adjusted_price, 2),
            "price_per_hour": round(adjusted_price / 730, 4),
            "currency": "USD",
            "notes": [
                "Sustained use discounts may apply (up to 30% savings)",
                "Committed use discounts available for 1-3 year terms",
                "Preemptible VMs available at ~70-80% discount"
            ],
            "last_updated": datetime.utcnow().isoformat()
        }

    async def get_storage_pricing(
        self,
        storage_class: str,
        region: str
    ) -> Optional[Dict[str, Any]]:
        """
        Get pricing for GCP Cloud Storage.

        Args:
            storage_class: Storage class (STANDARD, NEARLINE, COLDLINE, ARCHIVE)
            region: GCP region

        Returns:
            Pricing information
        """
        # Simplified pricing (per GB/month in USD)
        storage_pricing = {
            "STANDARD": {
                "us-central1": 0.020,
                "us-east1": 0.020,
                "us-west1": 0.020,
                "europe-west1": 0.020,
                "asia-southeast1": 0.023,
                "multi-region": 0.026
            },
            "NEARLINE": {
                "us-central1": 0.010,
                "us-east1": 0.010,
                "europe-west1": 0.010,
                "asia-southeast1": 0.013,
                "multi-region": 0.013
            },
            "COLDLINE": {
                "us-central1": 0.004,
                "us-east1": 0.004,
                "europe-west1": 0.004,
                "asia-southeast1": 0.007,
                "multi-region": 0.007
            },
            "ARCHIVE": {
                "us-central1": 0.0012,
                "us-east1": 0.0012,
                "europe-west1": 0.0012,
                "asia-southeast1": 0.0025,
                "multi-region": 0.0025
            }
        }

        class_pricing = storage_pricing.get(storage_class.upper(), {})
        price_per_gb = class_pricing.get(region, class_pricing.get("us-central1", 0.020))

        return {
            "storage_class": storage_class,
            "region": region,
            "price_per_gb_month": price_per_gb,
            "currency": "USD",
            "notes": [
                "Operations and network egress charges apply separately",
                f"{storage_class} storage has minimum storage duration requirements" if storage_class != "STANDARD" else ""
            ],
            "last_updated": datetime.utcnow().isoformat()
        }

    async def get_disk_pricing(
        self,
        disk_type: str,
        region: str
    ) -> Optional[Dict[str, Any]]:
        """
        Get pricing for GCP Persistent Disks.

        Args:
            disk_type: Disk type (pd-standard, pd-balanced, pd-ssd, pd-extreme)
            region: GCP region

        Returns:
            Pricing information
        """
        # Pricing per GB/month in USD
        disk_pricing = {
            "pd-standard": 0.040,  # Standard persistent disk
            "pd-balanced": 0.100,  # Balanced persistent disk
            "pd-ssd": 0.170,       # SSD persistent disk
            "pd-extreme": 0.125,   # Extreme persistent disk (per GB provisioned IOPS)
        }

        price_per_gb = disk_pricing.get(disk_type, 0.100)

        return {
            "disk_type": disk_type,
            "region": region,
            "price_per_gb_month": price_per_gb,
            "currency": "USD",
            "notes": [
                "Regional persistent disks cost 2x of zonal disks",
                "Snapshots are billed separately at $0.026 per GB/month"
            ],
            "last_updated": datetime.utcnow().isoformat()
        }

    # ==================== GCP Compute Engine API ====================

    async def get_machine_types(
        self,
        zone: str
    ) -> List[Dict[str, Any]]:
        """
        Get available machine types for a specific zone.

        Requires authentication.

        Args:
            zone: GCP zone (e.g., "us-central1-a")

        Returns:
            List of machine type information
        """
        if not self.project_id:
            raise ValueError("Project ID required")

        try:
            url = f"{GCP_COMPUTE_API}/projects/{self.project_id}/zones/{zone}/machineTypes"

            logger.info(f"Fetching machine types for zone: {zone}")

            response = await self.client.get(
                url,
                headers=self._get_headers()
            )
            response.raise_for_status()

            data = response.json()
            machine_types = data.get("items", [])

            return [
                {
                    "name": mt.get("name"),
                    "description": mt.get("description"),
                    "guest_cpus": mt.get("guestCpus"),
                    "memory_mb": mt.get("memoryMb"),
                    "is_shared_cpu": mt.get("isSharedCpu", False),
                    "maximum_persistent_disks": mt.get("maximumPersistentDisks"),
                    "zone": zone
                }
                for mt in machine_types
            ]

        except httpx.HTTPError as e:
            logger.error(f"HTTP error fetching machine types: {e}")
            return []
        except Exception as e:
            logger.error(f"Error fetching machine types: {e}")
            return []

    async def get_zones(self, region: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Get available GCP zones, optionally filtered by region.

        Requires authentication.

        Args:
            region: Optional region filter (e.g., "us-central1")

        Returns:
            List of zone information
        """
        if not self.project_id:
            raise ValueError("Project ID required")

        try:
            url = f"{GCP_COMPUTE_API}/projects/{self.project_id}/zones"

            logger.info(f"Fetching GCP zones{f' for region {region}' if region else ''}")

            response = await self.client.get(
                url,
                headers=self._get_headers()
            )
            response.raise_for_status()

            data = response.json()
            zones = data.get("items", [])

            # Filter by region if specified
            if region:
                zones = [z for z in zones if z.get("name", "").startswith(region)]

            return [
                {
                    "name": zone.get("name"),
                    "description": zone.get("description"),
                    "region": zone.get("region", "").split("/")[-1],
                    "status": zone.get("status")
                }
                for zone in zones
            ]

        except Exception as e:
            logger.error(f"Error fetching GCP zones: {e}")
            return []

    async def get_regions(self) -> List[Dict[str, Any]]:
        """
        Get all available GCP regions.

        Requires authentication.

        Returns:
            List of region information
        """
        if not self.project_id:
            raise ValueError("Project ID required")

        try:
            url = f"{GCP_COMPUTE_API}/projects/{self.project_id}/regions"

            logger.info("Fetching GCP regions")

            response = await self.client.get(
                url,
                headers=self._get_headers()
            )
            response.raise_for_status()

            data = response.json()
            regions = data.get("items", [])

            return [
                {
                    "name": region.get("name"),
                    "description": region.get("description"),
                    "status": region.get("status"),
                    "zones": [z.split("/")[-1] for z in region.get("zones", [])]
                }
                for region in regions
            ]

        except Exception as e:
            logger.error(f"Error fetching GCP regions: {e}")
            return []


    # ==================== GCP Compute Engine API ====================

    async def get_regions(self) -> List[Dict[str, Any]]:
        """
        Get all available GCP regions from Compute Engine API.

        Returns:
            List of region information
        """
        if not self.project_id:
            logger.warning("Project ID not set, returning empty regions list")
            return []

        try:
            url = f"{GCP_COMPUTE_API}/projects/{self.project_id}/regions"

            logger.info("Fetching GCP regions from Compute Engine API")

            response = await self.client.get(url, headers=self._get_headers())
            response.raise_for_status()

            data = response.json()
            regions = data.get("items", [])

            return [
                {
                    "name": region.get("name"),
                    "display_name": region.get("description", region.get("name")),
                    "status": region.get("status"),
                    "zones": [z.split("/")[-1] for z in region.get("zones", [])]
                }
                for region in regions
            ]

        except httpx.HTTPError as e:
            logger.error(f"HTTP error fetching GCP regions: {e}")
            return []
        except Exception as e:
            logger.error(f"Error fetching GCP regions: {e}")
            return []

    async def get_zones(self, region: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Get all available GCP zones, optionally filtered by region.

        Args:
            region: Optional region filter (e.g., "us-central1")

        Returns:
            List of zone information
        """
        if not self.project_id:
            logger.warning("Project ID not set, returning empty zones list")
            return []

        try:
            url = f"{GCP_COMPUTE_API}/projects/{self.project_id}/zones"

            logger.info(f"Fetching GCP zones{f' in {region}' if region else ''}")

            response = await self.client.get(url, headers=self._get_headers())
            response.raise_for_status()

            data = response.json()
            zones = data.get("items", [])

            # Filter by region if specified
            if region:
                zones = [z for z in zones if z.get("region", "").endswith(f"/{region}")]

            return [
                {
                    "name": zone.get("name"),
                    "region": zone.get("region", "").split("/")[-1],
                    "status": zone.get("status"),
                    "description": zone.get("description")
                }
                for zone in zones
            ]

        except httpx.HTTPError as e:
            logger.error(f"HTTP error fetching GCP zones: {e}")
            return []
        except Exception as e:
            logger.error(f"Error fetching GCP zones: {e}")
            return []

    async def get_machine_types(self, zone: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Get available machine types, optionally filtered by zone.

        Args:
            zone: Optional zone filter (e.g., "us-central1-a")

        Returns:
            List of machine type information
        """
        if not self.project_id:
            logger.warning("Project ID not set, returning empty machine types list")
            return []

        try:
            # If zone specified, get machine types for that zone
            # Otherwise, get from a default zone (us-central1-a) as aggregated list
            target_zone = zone or "us-central1-a"

            url = f"{GCP_COMPUTE_API}/projects/{self.project_id}/zones/{target_zone}/machineTypes"

            logger.info(f"Fetching GCP machine types for zone: {target_zone}")

            response = await self.client.get(url, headers=self._get_headers())
            response.raise_for_status()

            data = response.json()
            machine_types = data.get("items", [])

            return [
                {
                    "name": mt.get("name"),
                    "vcpus": mt.get("guestCpus", 0),
                    "memory_gb": round(mt.get("memoryMb", 0) / 1024, 2),
                    "description": mt.get("description", f"{mt.get('guestCpus', 0)} vCPUs, {round(mt.get('memoryMb', 0) / 1024, 1)} GB RAM"),
                    "zone": target_zone
                }
                for mt in machine_types
            ]

        except httpx.HTTPError as e:
            logger.error(f"HTTP error fetching GCP machine types: {e}")
            return []
        except Exception as e:
            logger.error(f"Error fetching GCP machine types: {e}")
            return []


# Global client instance
_public_client: Optional[GCPAPIClient] = None


async def get_gcp_client() -> GCPAPIClient:
    """Get or create GCP API client"""
    global _public_client
    if _public_client is None:
        _public_client = GCPAPIClient()
    return _public_client
