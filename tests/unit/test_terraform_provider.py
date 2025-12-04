"""
Unit tests for Terraform Provider
"""
import pytest
import os
import json
from unittest.mock import Mock, patch, MagicMock, mock_open
from backend.providers.terraform_provider import TerraformProvider
from backend.providers.base import DeploymentResult, DeploymentStatus, ResourceGroup, CloudResource, ProviderType


@pytest.fixture
def terraform_aws_provider():
    """Create TerraformProvider instance for AWS"""
    with patch.dict(os.environ, {
        'AWS_ACCESS_KEY_ID': 'test-key',
        'AWS_SECRET_ACCESS_KEY': 'test-secret',
        'AWS_DEFAULT_REGION': 'us-east-1'
    }):
        provider = TerraformProvider(cloud_platform="aws", region="us-east-1")
        return provider


@pytest.fixture
def terraform_gcp_provider():
    """Create TerraformProvider instance for GCP"""
    with patch.dict(os.environ, {
        'GOOGLE_PROJECT_ID': 'test-project',
        'GOOGLE_APPLICATION_CREDENTIALS': '/path/to/creds.json'
    }):
        provider = TerraformProvider(cloud_platform="gcp", subscription_id="test-project")
        return provider


class TestTerraformProvider:
    """Test cases for TerraformProvider"""

    def test_aws_initialization(self, terraform_aws_provider):
        """Test AWS provider initialization"""
        assert terraform_aws_provider.cloud_platform == "aws"
        assert terraform_aws_provider.region == "us-east-1"
        assert terraform_aws_provider.working_dir is not None

    def test_gcp_initialization(self, terraform_gcp_provider):
        """Test GCP provider initialization"""
        assert terraform_gcp_provider.cloud_platform == "gcp"
        assert terraform_gcp_provider.subscription_id == "test-project"

    def test_azure_initialization(self):
        """Test Azure (via Terraform) initialization"""
        with patch.dict(os.environ, {
            'AZURE_SUBSCRIPTION_ID': 'test-sub',
            'AZURE_TENANT_ID': 'test-tenant'
        }):
            provider = TerraformProvider(
                cloud_platform="azure",
                subscription_id="test-sub"
            )
            assert provider.cloud_platform == "azure"
            assert provider.subscription_id == "test-sub"

    def test_generate_aws_provider_block(self, terraform_aws_provider):
        """Test generating AWS provider block"""
        # Note: method name changed from _generate_provider_config to _generate_provider_block
        config = terraform_aws_provider._generate_provider_block(location="us-east-1")

        assert "provider" in config
        assert "aws" in config
        assert "us-east-1" in config

    def test_generate_gcp_provider_block(self, terraform_gcp_provider):
        """Test generating GCP provider block"""
        config = terraform_gcp_provider._generate_provider_block(location="us-central1")

        assert "provider" in config
        assert "google" in config
        assert "test-project" in config

    @patch('subprocess.run')
    def test_terraform_init_success(self, mock_run, terraform_aws_provider):
        """Test successful Terraform initialization"""
        mock_run.return_value = Mock(returncode=0, stdout="Terraform initialized", stderr="")

        # Fix: Pass list instead of string
        terraform_aws_provider._run_terraform_command(["init"])

        mock_run.assert_called_once()
        call_args = mock_run.call_args[0][0]
        assert "terraform" in call_args
        assert "init" in call_args

    @patch('subprocess.run')
    def test_terraform_command_failure(self, mock_run, terraform_aws_provider):
        """Test Terraform command failure"""
        mock_run.return_value = Mock(
            returncode=1,
            stdout="",
            stderr="Error: Invalid configuration"
        )

        # _run_terraform_command returns (output, returncode) and does NOT raise exception itself
        output, returncode = terraform_aws_provider._run_terraform_command(["apply"])
        
        assert returncode == 1
        assert "Error: Invalid configuration" in output

    @pytest.mark.asyncio
    @patch('subprocess.run')
    @patch('builtins.open', new_callable=mock_open, read_data='resource "aws_s3_bucket" "example" {}')
    async def test_deploy_success(self, mock_file, mock_run, terraform_aws_provider):
        """Test successful deployment"""
        # Mock Terraform commands
        mock_run.side_effect = [
            Mock(returncode=0, stdout="Initialized", stderr=""),  # init
            Mock(returncode=0, stdout="Plan complete", stderr=""),  # plan
            Mock(returncode=0, stdout="Apply complete", stderr=""),  # apply
            # Fix: Terraform output -json returns keys directly, not wrapped in "outputs"
            Mock(returncode=0, stdout='{"bucket_name": {"value": "test-bucket"}}', stderr="")  # output
        ]

        result = await terraform_aws_provider.deploy(
            template_path="/path/to/template.tf",
            parameters={"bucket_name": "test-bucket"},
            resource_group="test-group",
            location="us-east-1"
        )

        assert isinstance(result, DeploymentResult)
        # Fix: Check status instead of success
        assert result.status == DeploymentStatus.SUCCEEDED
        assert "bucket_name" in result.outputs

    @pytest.mark.asyncio
    @patch('subprocess.run')
    @patch('builtins.open', new_callable=mock_open, read_data='resource "aws_s3_bucket" "example" {}')
    async def test_deploy_failure(self, mock_file, mock_run, terraform_aws_provider):
        """Test deployment failure"""
        mock_run.side_effect = [
            Mock(returncode=0, stdout="Initialized", stderr=""),  # init
            Mock(returncode=0, stdout="Plan complete", stderr=""),  # plan
            Mock(returncode=1, stdout="", stderr="Error: Resource creation failed")  # apply fails
        ]

        # Should raise DeploymentError
        with pytest.raises(Exception) as excinfo:
            await terraform_aws_provider.deploy(
                template_path="/path/to/template.tf",
                parameters={},
                resource_group="test-group",
                location="us-east-1"
            )
        
        assert "Terraform apply failed" in str(excinfo.value)

    @pytest.mark.asyncio
    @patch('subprocess.run')
    async def test_list_resource_groups_aws(self, mock_run, terraform_aws_provider):
        """Test listing AWS resource groups (returns empty list for now)"""
        result = await terraform_aws_provider.list_resource_groups()
        assert isinstance(result, list)
        assert len(result) == 0

    @pytest.mark.asyncio
    async def test_create_resource_group_not_implemented(self, terraform_aws_provider):
        """Test that create resource group raises NotImplementedError"""
        with pytest.raises(NotImplementedError):
            await terraform_aws_provider.create_resource_group(
                name="test-group",
                location="us-east-1"
            )

    def test_get_provider_type(self, terraform_aws_provider):
        """Test getting provider type"""
        assert terraform_aws_provider.get_provider_type() == ProviderType.TERRAFORM

    def test_get_supported_locations(self, terraform_aws_provider):
        """Test getting supported locations"""
        locations = terraform_aws_provider.get_supported_locations()
        assert "us-east-1" in locations