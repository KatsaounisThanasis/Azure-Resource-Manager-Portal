"""
Pytest configuration and shared fixtures
This file is automatically loaded by pytest
"""
import pytest
import os
import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))


def pytest_configure(config):
    """Configure pytest with custom settings"""
    # Register custom markers
    config.addinivalue_line("markers", "unit: Unit tests")
    config.addinivalue_line("markers", "integration: Integration tests")
    config.addinivalue_line("markers", "e2e: End-to-end tests")
    config.addinivalue_line("markers", "slow: Slow running tests")
    config.addinivalue_line("markers", "docker: Tests requiring Docker")
    config.addinivalue_line("markers", "azure: Tests requiring Azure credentials")
    config.addinivalue_line("markers", "aws: Tests requiring AWS credentials")
    config.addinivalue_line("markers", "gcp: Tests requiring GCP credentials")


def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers automatically"""
    for item in items:
        # Auto-mark tests based on location
        if "unit" in str(item.fspath):
            item.add_marker(pytest.mark.unit)
        elif "integration" in str(item.fspath):
            item.add_marker(pytest.mark.integration)
        elif "e2e" in str(item.fspath):
            item.add_marker(pytest.mark.e2e)

        # Mark tests requiring external services
        if "docker" in item.nodeid.lower():
            item.add_marker(pytest.mark.docker)
        if "azure" in item.nodeid.lower():
            item.add_marker(pytest.mark.azure)
        if "aws" in item.nodeid.lower():
            item.add_marker(pytest.mark.aws)
        if "gcp" in item.nodeid.lower():
            item.add_marker(pytest.mark.gcp)

        # Mark slow tests
        if "e2e" in str(item.fspath) or "docker" in item.nodeid.lower():
            item.add_marker(pytest.mark.slow)


# ============================================================================
# Shared Fixtures
# ============================================================================

@pytest.fixture(scope="session")
def project_root():
    """Get project root directory"""
    return Path(__file__).parent


@pytest.fixture(scope="session")
def templates_dir(project_root):
    """Get templates directory"""
    return project_root / "templates"


@pytest.fixture(scope="session")
def backend_dir(project_root):
    """Get backend directory"""
    return project_root / "backend"


@pytest.fixture(autouse=True)
def setup_test_env():
    """Set up test environment variables"""
    # Save original environment
    original_env = dict(os.environ)

    # Set test environment variables
    os.environ["ENVIRONMENT"] = "test"
    os.environ["LOG_LEVEL"] = "DEBUG"

    # Mock credentials for testing (won't actually be used)
    os.environ["AZURE_SUBSCRIPTION_ID"] = "test-sub-id"
    os.environ["AZURE_TENANT_ID"] = "test-tenant-id"
    os.environ["AWS_ACCESS_KEY_ID"] = "test-access-key"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "test-secret-key"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
    os.environ["GOOGLE_PROJECT_ID"] = "test-project-id"

    yield

    # Restore original environment
    os.environ.clear()
    os.environ.update(original_env)


@pytest.fixture
def mock_azure_credentials():
    """Mock Azure credentials for testing"""
    return {
        "subscription_id": "test-subscription-id",
        "tenant_id": "test-tenant-id",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret"
    }


@pytest.fixture
def mock_aws_credentials():
    """Mock AWS credentials for testing"""
    return {
        "access_key_id": "test-access-key-id",
        "secret_access_key": "test-secret-access-key",
        "region": "us-east-1"
    }


@pytest.fixture
def mock_gcp_credentials():
    """Mock GCP credentials for testing"""
    return {
        "project_id": "test-project-id",
        "credentials_path": "/path/to/credentials.json"
    }


@pytest.fixture
def sample_deployment_parameters():
    """Sample deployment parameters for testing"""
    return {
        "storageAccountName": "teststorage123",
        "location": "eastus",
        "skuName": "Standard_LRS",
        "tags": {
            "environment": "test",
            "purpose": "testing"
        }
    }


@pytest.fixture
def sample_template_metadata():
    """Sample template metadata for testing"""
    return {
        "name": "test-template",
        "description": "Test template for unit testing",
        "provider_type": "azure",
        "cloud": "azure",
        "category": "storage",
        "version": "1.0.0",
        "parameters": {
            "storageAccountName": {
                "type": "string",
                "description": "Storage account name"
            },
            "location": {
                "type": "string",
                "default": "eastus"
            }
        }
    }


# ============================================================================
# Test Helpers
# ============================================================================

@pytest.fixture
def assert_valid_deployment_result():
    """Helper to validate DeploymentResult structure"""
    def _assert(result):
        assert hasattr(result, "success")
        assert hasattr(result, "deployment_id")
        assert hasattr(result, "status")
        assert hasattr(result, "message")
        assert hasattr(result, "provider")
        assert hasattr(result, "timestamp")
        assert isinstance(result.success, bool)
        if not result.success:
            assert hasattr(result, "error")
            assert result.error is not None
    return _assert


@pytest.fixture
def assert_valid_resource_group():
    """Helper to validate ResourceGroup structure"""
    def _assert(rg):
        assert hasattr(rg, "name")
        assert hasattr(rg, "location")
        assert hasattr(rg, "id")
        assert hasattr(rg, "tags")
        assert isinstance(rg.name, str)
        assert isinstance(rg.location, str)
        assert isinstance(rg.tags, dict)
    return _assert


@pytest.fixture
def assert_valid_cloud_resource():
    """Helper to validate CloudResource structure"""
    def _assert(resource):
        assert hasattr(resource, "name")
        assert hasattr(resource, "type")
        assert hasattr(resource, "location")
        assert hasattr(resource, "id")
        assert isinstance(resource.name, str)
        assert isinstance(resource.type, str)
    return _assert


# ============================================================================
# Skip Conditions
# ============================================================================

def pytest_runtest_setup(item):
    """Skip tests based on available services"""
    # Skip Docker tests if Docker is not available
    if "docker" in [mark.name for mark in item.iter_markers()]:
        try:
            import docker
            client = docker.from_env()
            client.ping()
        except Exception:
            pytest.skip("Docker not available")

    # Skip cloud provider tests if credentials not available
    if "azure" in [mark.name for mark in item.iter_markers()]:
        if not all([
            os.getenv("AZURE_SUBSCRIPTION_ID"),
            os.getenv("AZURE_TENANT_ID")
        ]):
            pytest.skip("Azure credentials not configured")

    if "aws" in [mark.name for mark in item.iter_markers()]:
        if not all([
            os.getenv("AWS_ACCESS_KEY_ID"),
            os.getenv("AWS_SECRET_ACCESS_KEY")
        ]):
            pytest.skip("AWS credentials not configured")

    if "gcp" in [mark.name for mark in item.iter_markers()]:
        if not os.getenv("GOOGLE_PROJECT_ID"):
            pytest.skip("GCP credentials not configured")


# ============================================================================
# Logging Configuration for Tests
# ============================================================================

@pytest.fixture(autouse=True)
def configure_test_logging(caplog):
    """Configure logging for tests"""
    import logging
    caplog.set_level(logging.DEBUG)
