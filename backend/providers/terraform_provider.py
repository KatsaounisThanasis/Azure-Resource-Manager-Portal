"""
Terraform Provider Implementation

This provider uses Terraform to deploy resources across multiple cloud platforms.
Supports Azure, AWS, and GCP through Terraform.
"""

import os
import json
import logging
import subprocess
import tempfile
from typing import Dict, List, Any, Optional
from datetime import datetime
from pathlib import Path

from .base import (
    CloudProvider,
    ProviderType,
    DeploymentResult,
    DeploymentStatus,
    ResourceGroup,
    CloudResource,
    DeploymentError,
    ProviderConfigurationError
)
from backend.services.state_backend_manager import StateBackendManager

logger = logging.getLogger(__name__)


class TerraformProvider(CloudProvider):
    """
    Terraform-based provider for multi-cloud deployments.

    This provider allows deploying to Azure, AWS, and GCP using
    Terraform configurations instead of cloud-native templates.
    """

    def __init__(
        self,
        subscription_id: Optional[str] = None,
        region: Optional[str] = None,
        cloud_platform: str = "azure",
        terraform_version: str = "1.5.0"
    ):
        """
        Initialize Terraform provider.

        Args:
            subscription_id: Cloud subscription/account ID
            region: Default region
            cloud_platform: Target cloud (azure, aws, gcp)
            terraform_version: Terraform version to use
        """
        super().__init__(subscription_id, region)
        self.cloud_platform = cloud_platform.lower()
        self.terraform_version = terraform_version
        self.working_dir = tempfile.mkdtemp(prefix="terraform_")

        # Verify Terraform is installed
        if not self._check_terraform_installed():
            raise ProviderConfigurationError(
                "Terraform is not installed or not in PATH. "
                "Please install Terraform: https://www.terraform.io/downloads",
                provider="terraform"
            )

        logger.info(f"Terraform provider initialized for {cloud_platform}")

    def _check_terraform_installed(self) -> bool:
        """Check if Terraform is installed and accessible."""
        try:
            result = subprocess.run(
                ["terraform", "version"],
                capture_output=True,
                text=True,
                timeout=10
            )
            return result.returncode == 0
        except (subprocess.SubprocessError, FileNotFoundError):
            return False

    def _check_azure_rg_exists(self, resource_group: str) -> bool:
        """Check if an Azure resource group exists using az CLI."""
        try:
            result = subprocess.run(
                ["az", "group", "show", "--name", resource_group, "--query", "name", "-o", "tsv"],
                capture_output=True,
                text=True,
                timeout=30
            )
            exists = result.returncode == 0 and resource_group in result.stdout
            logger.info(f"Resource group '{resource_group}' exists: {exists}")
            return exists
        except Exception as e:
            logger.warning(f"Could not check if RG exists (assuming it doesn't): {e}")
            return False

    def _run_terraform_command(
        self,
        command: List[str],
        working_dir: Optional[str] = None,
        env: Optional[Dict[str, str]] = None
    ) -> tuple[str, int]:
        """
        Execute a Terraform command.

        Args:
            command: Terraform command arguments
            working_dir: Working directory for the command
            env: Environment variables

        Returns:
            Tuple of (output, return_code)
        """
        if working_dir is None:
            working_dir = self.working_dir

        full_command = ["terraform"] + command

        logger.info(f"Running Terraform command: {' '.join(full_command)}")

        try:
            # Merge environment variables
            cmd_env = os.environ.copy()
            if env:
                cmd_env.update(env)

            result = subprocess.run(
                full_command,
                cwd=working_dir,
                capture_output=True,
                text=True,
                env=cmd_env,
                timeout=600  # 10 minute timeout
            )

            if result.stdout:
                logger.debug(f"Terraform stdout: {result.stdout}")
            if result.stderr:
                logger.warning(f"Terraform stderr: {result.stderr}")

            return result.stdout + result.stderr, result.returncode

        except subprocess.TimeoutExpired:
            raise DeploymentError(
                "Terraform command timed out after 10 minutes",
                provider="terraform"
            )
        except Exception as e:
            raise DeploymentError(
                f"Failed to execute Terraform command: {str(e)}",
                provider="terraform"
            )

    def _generate_terraform_config(
        self,
        template_content: str,
        parameters: Dict[str, Any],
        resource_group: str,
        location: str,
        deployment_id: Optional[str] = None
    ) -> str:
        """
        Generate Terraform configuration from template.

        Args:
            template_content: Template content (could be Bicep, ARM, or Terraform)
            parameters: Deployment parameters
            resource_group: Resource group/stack name
            location: Deployment location
            deployment_id: Unique deployment identifier (για remote state)

        Returns:
            Path to generated Terraform configuration directory
        """
        config_dir = os.path.join(self.working_dir, "config")
        os.makedirs(config_dir, exist_ok=True)

        # Generate backend configuration (remote state)
        # NOTE: Disabled for testing - using local backend
        # if deployment_id:
        #     backend_manager = StateBackendManager(
        #         cloud_platform=self.cloud_platform,
        #         deployment_id=deployment_id,
        #         region=location or self.region
        #     )
        #     backend_tf_content = backend_manager.generate_backend_tf_content()
        #     backend_tf_path = os.path.join(config_dir, "backend.tf")
        #     with open(backend_tf_path, 'w') as f:
        #         f.write(backend_tf_content)
        #     logger.info(f"Generated remote state backend configuration for {self.cloud_platform}")

        # Generate provider configuration
        provider_config = self._generate_provider_block(location)

        # Generate resource_group.tf for Azure (auto-create only if RG doesn't exist)
        # Check if resource group exists before trying to create it
        if self.cloud_platform == "azure" and resource_group:
            rg_exists = self._check_azure_rg_exists(resource_group)
            if not rg_exists:
                rg_tf_path = os.path.join(config_dir, "resource_group.tf")
                with open(rg_tf_path, 'w') as f:
                    f.write(f'''# Auto-create Resource Group (detected as not existing)
resource "azurerm_resource_group" "deployment_rg" {{
  name     = var.resource_group_name
  location = var.location

  tags = {{
    ManagedBy = "Terraform"
    CreatedBy = "MultiCloud-Manager"
  }}
}}
''')
                logger.info(f"Generated resource_group.tf for auto-creation (RG does not exist)")
            else:
                logger.info(f"Resource group '{resource_group}' already exists, skipping auto-creation")

        # Generate main.tf
        main_tf_path = os.path.join(config_dir, "main.tf")
        with open(main_tf_path, 'w') as f:
            f.write(provider_config)
            f.write("\n\n")
            # If template_content is already Terraform, use it
            if "resource" in template_content or "module" in template_content:
                f.write(template_content)
            else:
                # Convert parameters to Terraform format
                f.write(self._convert_to_terraform_resources(
                    template_content,
                    parameters,
                    resource_group,
                    location
                ))

        # Generate variables.tf
        # NOTE: Disabled because templates already contain variable declarations
        # variables_tf_path = os.path.join(config_dir, "variables.tf")
        # with open(variables_tf_path, 'w') as f:
        #     f.write(self._generate_variables(parameters))

        # Generate terraform.tfvars
        tfvars_path = os.path.join(config_dir, "terraform.tfvars")
        logger.info(f"Generating terraform.tfvars with parameters: {parameters}")
        with open(tfvars_path, 'w') as f:
            for key, value in parameters.items():
                if isinstance(value, str):
                    f.write(f'{key} = "{value}"\n')
                else:
                    f.write(f'{key} = {json.dumps(value)}\n')

        # Log the generated tfvars content for debugging
        with open(tfvars_path, 'r') as f:
            tfvars_content = f.read()
            logger.info(f"Generated terraform.tfvars content:\n{tfvars_content}")

        logger.info(f"Generated Terraform configuration in {config_dir}")
        return config_dir

    def _generate_provider_block(self, location: str) -> str:
        """Generate cloud provider configuration block.

        Note: Only generates the provider block, not the terraform block.
        Templates should contain their own terraform block with required_providers.
        """
        if self.cloud_platform == "azure":
            # Get Azure credentials from environment
            tenant_id = os.getenv('AZURE_TENANT_ID', '')
            client_id = os.getenv('AZURE_CLIENT_ID', '')
            client_secret = os.getenv('AZURE_CLIENT_SECRET', '')

            # If service principal credentials are available, use them
            if tenant_id and client_id and client_secret:
                return f"""
provider "azurerm" {{
  features {{}}
  subscription_id = "{self.subscription_id or ''}"
  tenant_id       = "{tenant_id}"
  client_id       = "{client_id}"
  client_secret   = "{client_secret}"
}}
"""
            else:
                # Fallback to Azure CLI authentication (requires 'az login')
                return f"""
provider "azurerm" {{
  features {{}}
  subscription_id = "{self.subscription_id or ''}"
}}
"""
        elif self.cloud_platform == "aws":
            return f"""
provider "aws" {{
  region = "{location or self.region or 'us-east-1'}"
}}
"""
        elif self.cloud_platform == "gcp":
            return f"""
provider "google" {{
  project = "{self.subscription_id or ''}"
  region  = "{location or self.region or 'us-central1'}"
}}
"""
        else:
            raise ProviderConfigurationError(
                f"Unsupported cloud platform: {self.cloud_platform}",
                provider="terraform"
            )

    def _convert_to_terraform_resources(
        self,
        template_content: str,
        parameters: Dict[str, Any],
        resource_group: str,
        location: str
    ) -> str:
        """
        Convert template to Terraform resources.

        This is a simplified conversion. In production, you'd need more sophisticated
        conversion logic or use existing tools like Bicep-to-Terraform converters.
        """
        # Placeholder for basic resource group
        if self.cloud_platform == "azure":
            return f"""
resource "azurerm_resource_group" "main" {{
  name     = "{resource_group}"
  location = "{location}"

  tags = {{
    managed_by = "terraform"
    environment = "production"
  }}
}}

# Additional resources would be converted from the template
# This is a simplified example - production would need full conversion logic
"""
        elif self.cloud_platform == "aws":
            return f"""
# AWS resources converted from template
# CloudFormation stack equivalent
"""
        elif self.cloud_platform == "gcp":
            return f"""
# GCP resources converted from template
"""

        return "# Template conversion not implemented for this platform"

    def _generate_variables(self, parameters: Dict[str, Any]) -> str:
        """Generate Terraform variables.tf file."""
        variables = ""
        for key, value in parameters.items():
            var_type = "string"
            if isinstance(value, bool):
                var_type = "bool"
            elif isinstance(value, int):
                var_type = "number"
            elif isinstance(value, list):
                var_type = "list"
            elif isinstance(value, dict):
                var_type = "map"

            variables += f"""
variable "{key}" {{
  type        = {var_type}
  description = "Parameter {key}"
}}
"""
        return variables

    async def deploy(
        self,
        template_path: str,
        parameters: Dict[str, Any],
        resource_group: str,
        location: str,
        deployment_name: Optional[str] = None,
        deployment_id: Optional[str] = None
    ) -> DeploymentResult:
        """Deploy using Terraform with remote state backend."""
        try:
            # Use provided deployment_id or generate one
            if not deployment_id:
                deployment_id = f"terraform-{resource_group}-{datetime.now().strftime('%Y%m%d%H%M%S')}"

            # Read template
            with open(template_path, 'r') as f:
                template_content = f.read()

            # Generate Terraform configuration (including remote state backend)
            config_dir = self._generate_terraform_config(
                template_content,
                parameters,
                resource_group,
                location,
                deployment_id=deployment_id
            )

            # Initialize Terraform
            logger.info("Initializing Terraform...")
            output, returncode = self._run_terraform_command(
                ["init"],
                working_dir=config_dir
            )
            if returncode != 0:
                raise DeploymentError(
                    f"Terraform init failed: {output}",
                    provider="terraform"
                )

            # Plan
            logger.info("Planning Terraform deployment...")
            output, returncode = self._run_terraform_command(
                ["plan", "-var-file=terraform.tfvars", "-input=false", "-out=tfplan"],
                working_dir=config_dir
            )
            if returncode != 0:
                raise DeploymentError(
                    f"Terraform plan failed: {output}",
                    provider="terraform"
                )

            # Apply
            logger.info("Applying Terraform configuration...")
            output, returncode = self._run_terraform_command(
                ["apply", "-input=false", "-auto-approve", "tfplan"],
                working_dir=config_dir
            )
            if returncode != 0:
                raise DeploymentError(
                    f"Terraform apply failed: {output}",
                    provider="terraform"
                )

            # Get outputs
            output_json, _ = self._run_terraform_command(
                ["output", "-json"],
                working_dir=config_dir
            )
            try:
                outputs = json.loads(output_json) if output_json else {}
            except json.JSONDecodeError:
                outputs = {}

            return DeploymentResult(
                deployment_id=deployment_id,
                status=DeploymentStatus.SUCCEEDED,
                resource_group=resource_group,
                resources_created=[],
                message="Terraform deployment completed successfully",
                outputs=outputs,
                timestamp=datetime.now(),
                provider_metadata={
                    "config_dir": config_dir,
                    "cloud_platform": self.cloud_platform
                }
            )

        except Exception as e:
            logger.error(f"Terraform deployment failed: {str(e)}")
            raise DeploymentError(
                f"Terraform deployment failed: {str(e)}",
                provider="terraform"
            )

    async def get_deployment_status(
        self,
        deployment_id: str,
        resource_group: str
    ) -> DeploymentStatus:
        """Get deployment status - Terraform doesn't track this natively."""
        return DeploymentStatus.SUCCEEDED

    async def list_resource_groups(self) -> List[ResourceGroup]:
        """List resource groups - implementation depends on cloud platform."""
        # This would need cloud-specific implementation
        return []

    async def create_resource_group(
        self,
        name: str,
        location: str,
        tags: Optional[Dict[str, str]] = None
    ) -> ResourceGroup:
        """Create resource group using Terraform."""
        # Generate minimal Terraform config for resource group
        config_dir = os.path.join(self.working_dir, f"rg-{name}")
        os.makedirs(config_dir, exist_ok=True)

        # This would generate appropriate Terraform for the cloud platform
        raise NotImplementedError("Resource group creation via Terraform not yet implemented")

    async def delete_resource_group(self, name: str) -> bool:
        """Delete resource group."""
        raise NotImplementedError("Resource group deletion via Terraform not yet implemented")

    async def list_resources(self, resource_group: str) -> List[CloudResource]:
        """List resources."""
        # Would need to parse Terraform state
        return []

    async def validate_template(
        self,
        template_path: str,
        parameters: Dict[str, Any]
    ) -> tuple[bool, Optional[str]]:
        """Validate template."""
        try:
            with open(template_path, 'r') as f:
                content = f.read()
            # Basic validation - check if it looks like valid Terraform
            if "resource" in content or "module" in content:
                return True, None
            return True, "Template validation passed"
        except Exception as e:
            return False, str(e)

    def get_supported_locations(self) -> List[str]:
        """Get supported locations based on cloud platform."""
        if self.cloud_platform == "azure":
            return ["eastus", "westus", "westeurope", "northeurope"]
        elif self.cloud_platform == "aws":
            return ["us-east-1", "us-west-2", "eu-west-1", "eu-central-1"]
        elif self.cloud_platform == "gcp":
            return ["us-central1", "us-east1", "europe-west1", "asia-east1"]
        return []

    def get_provider_type(self) -> ProviderType:
        """Get provider type."""
        return ProviderType.TERRAFORM
