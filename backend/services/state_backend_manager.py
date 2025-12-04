"""
Terraform State Backend Manager

Διαχειρίζεται remote state backends για Terraform deployments σε διάφορους cloud providers.
Υποστηρίζει S3 (AWS), Azure Storage, και GCS (GCP).
"""

import json
import hashlib
from typing import Dict, Any, Optional
from enum import Enum
import os


class BackendType(str, Enum):
    """Τύποι backend για Terraform state"""
    S3 = "s3"  # AWS S3
    AZURERM = "azurerm"  # Azure Storage
    GCS = "gcs"  # Google Cloud Storage
    LOCAL = "local"  # Local (για development)


class StateBackendManager:
    """
    Διαχειρίζεται Terraform remote state backends.

    Για κάθε deployment δημιουργεί ένα μοναδικό state backend configuration
    που αποθηκεύει το state στο cloud.
    """

    def __init__(self, cloud_platform: str, deployment_id: str, region: str = None):
        """
        Args:
            cloud_platform: aws, gcp, ή azure
            deployment_id: Μοναδικό ID του deployment
            region: Region για το backend storage
        """
        self.cloud_platform = cloud_platform.lower()
        self.deployment_id = deployment_id
        self.region = region or self._get_default_region()
        self.backend_type = self._determine_backend_type()

    def _get_default_region(self) -> str:
        """Επιστρέφει default region για κάθε cloud"""
        defaults = {
            "aws": "us-east-1",
            "gcp": "us-central1",
            "azure": "eastus"
        }
        return defaults.get(self.cloud_platform, "us-east-1")

    def _determine_backend_type(self) -> BackendType:
        """Καθορίζει τον τύπο backend με βάση το cloud platform"""
        backend_map = {
            "aws": BackendType.S3,
            "gcp": BackendType.GCS,
            "azure": BackendType.AZURERM
        }
        return backend_map.get(self.cloud_platform, BackendType.LOCAL)

    def _generate_state_key(self) -> str:
        """
        Δημιουργεί unique key για το state file.

        Format: terraform-states/{deployment_id}/terraform.tfstate
        """
        return f"terraform-states/{self.deployment_id}/terraform.tfstate"

    def _get_bucket_name_from_env(self) -> Optional[str]:
        """Παίρνει το bucket/container name από environment variables"""
        env_vars = {
            "aws": "TERRAFORM_STATE_S3_BUCKET",
            "gcp": "TERRAFORM_STATE_GCS_BUCKET",
            "azure": "TERRAFORM_STATE_STORAGE_ACCOUNT"
        }
        return os.getenv(env_vars.get(self.cloud_platform))

    def generate_backend_config(
        self,
        bucket_name: Optional[str] = None,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Δημιουργεί backend configuration για Terraform.

        Args:
            bucket_name: Όνομα του bucket/container (αν δεν δοθεί, παίρνει από env)
            **kwargs: Επιπλέον parameters για το backend

        Returns:
            Dictionary με backend configuration

        Example:
            >>> manager = StateBackendManager("aws", "deploy-123", "us-east-1")
            >>> config = manager.generate_backend_config("my-terraform-state-bucket")
        """
        # Παίρνει bucket name από argument ή environment
        storage_name = bucket_name or self._get_bucket_name_from_env()

        if self.backend_type == BackendType.S3:
            return self._generate_s3_backend(storage_name, **kwargs)
        elif self.backend_type == BackendType.AZURERM:
            return self._generate_azurerm_backend(storage_name, **kwargs)
        elif self.backend_type == BackendType.GCS:
            return self._generate_gcs_backend(storage_name, **kwargs)
        else:
            return self._generate_local_backend()

    def _generate_s3_backend(
        self,
        bucket_name: Optional[str],
        dynamodb_table: Optional[str] = None,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Δημιουργεί S3 backend configuration για AWS.

        S3 backend χρησιμοποιεί:
        - S3 bucket για state storage
        - DynamoDB table για state locking (προαιρετικό)
        """
        if not bucket_name:
            return self._generate_local_backend()

        config = {
            "terraform": {
                "backend": {
                    "s3": {
                        "bucket": bucket_name,
                        "key": self._generate_state_key(),
                        "region": self.region,
                        "encrypt": True,  # Encryption at rest
                    }
                }
            }
        }

        # Προσθήκη DynamoDB table για locking (προτεινόμενο)
        if dynamodb_table:
            config["terraform"]["backend"]["s3"]["dynamodb_table"] = dynamodb_table
            config["terraform"]["backend"]["s3"]["lock_table"] = dynamodb_table

        return config

    def _generate_azurerm_backend(
        self,
        storage_account: Optional[str],
        container_name: str = "terraform-state",
        **kwargs
    ) -> Dict[str, Any]:
        """
        Δημιουργεί Azure Storage backend configuration.

        Azure backend χρησιμοποιεί:
        - Storage Account
        - Blob Container
        - Automatic state locking
        """
        if not storage_account:
            return self._generate_local_backend()

        config = {
            "terraform": {
                "backend": {
                    "azurerm": {
                        "storage_account_name": storage_account,
                        "container_name": container_name,
                        "key": self._generate_state_key(),
                        "use_azuread_auth": True  # Χρήση Azure AD authentication
                    }
                }
            }
        }

        # Προσθήκη resource group αν δοθεί
        resource_group = kwargs.get("resource_group")
        if resource_group:
            config["terraform"]["backend"]["azurerm"]["resource_group_name"] = resource_group

        return config

    def _generate_gcs_backend(
        self,
        bucket_name: Optional[str],
        prefix: str = "terraform-state",
        **kwargs
    ) -> Dict[str, Any]:
        """
        Δημιουργεί GCS backend configuration για GCP.

        GCS backend χρησιμοποιεί:
        - GCS bucket για state storage
        - Automatic state locking
        """
        if not bucket_name:
            return self._generate_local_backend()

        config = {
            "terraform": {
                "backend": {
                    "gcs": {
                        "bucket": bucket_name,
                        "prefix": f"{prefix}/{self.deployment_id}",
                        "encryption_key": kwargs.get("encryption_key")  # Optional customer-supplied encryption
                    }
                }
            }
        }

        return config

    def _generate_local_backend(self) -> Dict[str, Any]:
        """
        Δημιουργεί local backend configuration (για development).

        ΠΡΟΣΟΧΗ: Το local backend δεν πρέπει να χρησιμοποιείται σε production!
        """
        return {
            "terraform": {
                "backend": {
                    "local": {
                        "path": f"./terraform-states/{self.deployment_id}/terraform.tfstate"
                    }
                }
            }
        }

    def generate_backend_tf_content(
        self,
        bucket_name: Optional[str] = None,
        **kwargs
    ) -> str:
        """
        Δημιουργεί το περιεχόμενο του backend.tf file.

        Returns:
            String με HCL (Terraform configuration)
        """
        config = self.generate_backend_config(bucket_name, **kwargs)
        return self._dict_to_hcl(config)

    def _dict_to_hcl(self, config: Dict[str, Any], indent: int = 0) -> str:
        """
        Μετατρέπει Python dictionary σε HCL (Terraform configuration language).

        Args:
            config: Dictionary με configuration
            indent: Επίπεδο indentation

        Returns:
            String με HCL format
        """
        lines = []
        indent_str = "  " * indent

        for key, value in config.items():
            if isinstance(value, dict):
                lines.append(f"{indent_str}{key} {{")
                lines.append(self._dict_to_hcl(value, indent + 1))
                lines.append(f"{indent_str}}}")
            elif isinstance(value, bool):
                lines.append(f'{indent_str}{key} = {str(value).lower()}')
            elif isinstance(value, str):
                lines.append(f'{indent_str}{key} = "{value}"')
            elif isinstance(value, (int, float)):
                lines.append(f'{indent_str}{key} = {value}')
            elif value is not None:
                lines.append(f'{indent_str}{key} = "{value}"')

        return "\n".join(lines)

    def get_backend_metadata(self) -> Dict[str, Any]:
        """
        Επιστρέφει metadata για το backend (για αποθήκευση στη βάση).

        Returns:
            Dictionary με backend metadata
        """
        return {
            "backend_type": self.backend_type.value,
            "deployment_id": self.deployment_id,
            "cloud_platform": self.cloud_platform,
            "region": self.region,
            "state_key": self._generate_state_key()
        }

    @staticmethod
    def validate_backend_requirements(cloud_platform: str) -> Dict[str, bool]:
        """
        Ελέγχει αν υπάρχουν τα απαραίτητα credentials για το backend.

        Returns:
            Dictionary με validation results
        """
        requirements = {
            "aws": {
                "has_credentials": bool(
                    os.getenv("AWS_ACCESS_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY")
                ),
                "has_bucket_config": bool(os.getenv("TERRAFORM_STATE_S3_BUCKET"))
            },
            "gcp": {
                "has_credentials": bool(
                    os.getenv("GOOGLE_APPLICATION_CREDENTIALS") or os.getenv("GOOGLE_CREDENTIALS")
                ),
                "has_bucket_config": bool(os.getenv("TERRAFORM_STATE_GCS_BUCKET"))
            },
            "azure": {
                "has_credentials": bool(
                    os.getenv("AZURE_SUBSCRIPTION_ID") and
                    (os.getenv("AZURE_CLIENT_ID") or os.getenv("ARM_CLIENT_ID"))
                ),
                "has_storage_config": bool(os.getenv("TERRAFORM_STATE_STORAGE_ACCOUNT"))
            }
        }

        return requirements.get(cloud_platform.lower(), {})


# Helper function για γρήγορη χρήση
def create_backend_config(
    cloud_platform: str,
    deployment_id: str,
    region: Optional[str] = None,
    storage_name: Optional[str] = None,
    **kwargs
) -> Dict[str, Any]:
    """
    Helper function για γρήγορη δημιουργία backend configuration.

    Example:
        >>> config = create_backend_config("aws", "deploy-123", "us-east-1", "my-state-bucket")
    """
    manager = StateBackendManager(cloud_platform, deployment_id, region)
    return manager.generate_backend_config(storage_name, **kwargs)
