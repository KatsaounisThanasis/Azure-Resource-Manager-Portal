"""
Integration tests for REST API endpoints
"""
import pytest
from fastapi.testclient import TestClient
from unittest.mock import Mock, patch, AsyncMock
from backend.api.routes import app
from backend.providers.base import DeploymentResult, ResourceGroup, CloudResource


@pytest.fixture
def client():
    """Create test client"""
    return TestClient(app)


@pytest.fixture
def mock_provider():
    """Mock cloud provider"""
    provider = Mock()
    provider.deploy = AsyncMock(return_value=DeploymentResult(
        success=True,
        deployment_id="test-deployment-123",
        status="Succeeded",
        message="Deployment completed successfully",
        outputs={"resource_id": "test-resource-id"},
        provider="azure",
        timestamp="2025-01-01T00:00:00Z"
    ))
    provider.list_resource_groups = AsyncMock(return_value=[
        ResourceGroup(
            name="test-rg-1",
            location="eastus",
            id="/subscriptions/test/resourceGroups/test-rg-1",
            tags={"env": "test"}
        )
    ])
    provider.list_resources = AsyncMock(return_value=[
        CloudResource(
            name="storage-account-1",
            type="Microsoft.Storage/storageAccounts",
            location="eastus",
            id="/subscriptions/test/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/storage-account-1",
            tags={}
        )
    ])
    return provider


class TestHealthEndpoint:
    """Test health check endpoint"""

    def test_health_check(self, client):
        """Test GET /health"""
        response = client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data
        assert "version" in data


class TestProvidersEndpoint:
    """Test providers endpoint"""

    def test_list_providers(self, client):
        """Test GET /api/v1/providers"""
        response = client.get("/api/v1/providers")

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "data" in data
        assert "providers" in data["data"]

        providers = data["data"]["providers"]
        assert "azure" in providers
        assert "terraform-aws" in providers
        assert "terraform-gcp" in providers

    def test_providers_response_format(self, client):
        """Test providers response has correct format"""
        response = client.get("/api/v1/providers")
        data = response.json()

        providers = data["data"]["providers"]
        for provider_id, provider_info in providers.items():
            assert "description" in provider_info
            assert "cloud" in provider_info


class TestTemplatesEndpoint:
    """Test templates endpoint"""

    @patch('backend.api_rest.template_manager')
    def test_list_templates(self, mock_template_manager, client):
        """Test GET /api/v1/templates"""
        mock_template_manager.list_templates.return_value = [
            {
                "name": "storage-account",
                "description": "Azure Storage Account",
                "provider_type": "azure",
                "cloud": "azure",
                "category": "storage",
                "parameters": {"storageAccountName": "string"}
            }
        ]

        response = client.get("/api/v1/templates")

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert len(data["data"]["templates"]) > 0

    @patch('backend.api_rest.template_manager')
    def test_list_templates_filtered_by_cloud(self, mock_template_manager, client):
        """Test GET /api/v1/templates?cloud=azure"""
        mock_template_manager.list_templates.return_value = [
            {
                "name": "storage-account",
                "cloud": "azure",
                "provider_type": "azure"
            }
        ]

        response = client.get("/api/v1/templates?cloud=azure")

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        mock_template_manager.list_templates.assert_called_once_with(
            provider_type=None,
            cloud="azure",
            category=None
        )

    @patch('backend.api_rest.template_manager')
    def test_list_templates_filtered_by_category(self, mock_template_manager, client):
        """Test GET /api/v1/templates?category=storage"""
        mock_template_manager.list_templates.return_value = []

        response = client.get("/api/v1/templates?category=storage")

        assert response.status_code == 200
        mock_template_manager.list_templates.assert_called_once_with(
            provider_type=None,
            cloud=None,
            category="storage"
        )

    @patch('backend.api_rest.template_manager')
    def test_get_template_details(self, mock_template_manager, client):
        """Test GET /api/v1/templates/{template_name}"""
        mock_template = Mock()
        mock_template.name = "storage-account"
        mock_template.description = "Azure Storage Account"
        mock_template.provider_type = "azure"
        mock_template.cloud = "azure"
        mock_template.category = "storage"
        mock_template.parameters = {"storageAccountName": "string"}
        mock_template.version = "1.0.0"

        mock_template_manager.get_template.return_value = mock_template

        response = client.get("/api/v1/templates/storage-account")

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["data"]["name"] == "storage-account"

    @patch('backend.api_rest.template_manager')
    def test_get_template_not_found(self, mock_template_manager, client):
        """Test GET /api/v1/templates/{template_name} with non-existent template"""
        mock_template_manager.get_template.return_value = None

        response = client.get("/api/v1/templates/non-existent")

        assert response.status_code == 404
        data = response.json()
        assert data["success"] is False


class TestDeploymentEndpoint:
    """Test deployment endpoint"""

    @patch('backend.api_rest.ProviderFactory.create_provider')
    @patch('backend.api_rest.template_manager')
    def test_deploy_success(self, mock_template_manager, mock_factory, client, mock_provider):
        """Test POST /api/v1/deploy"""
        mock_factory.return_value = mock_provider
        mock_template_manager.get_template_path.return_value = "/path/to/template.bicep"

        payload = {
            "template_name": "storage-account",
            "provider_type": "azure",
            "subscription_id": "test-sub-id",
            "resource_group": "test-rg",
            "location": "eastus",
            "parameters": {
                "storageAccountName": "teststorage123"
            }
        }

        response = client.post("/api/v1/deploy", json=payload)

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "deployment_id" in data["data"]
        assert data["data"]["status"] == "Succeeded"

    @patch('backend.api_rest.template_manager')
    def test_deploy_template_not_found(self, mock_template_manager, client):
        """Test POST /api/v1/deploy with non-existent template"""
        mock_template_manager.get_template_path.side_effect = ValueError("Template not found")

        payload = {
            "template_name": "non-existent",
            "provider_type": "azure",
            "subscription_id": "test-sub-id",
            "resource_group": "test-rg",
            "location": "eastus",
            "parameters": {}
        }

        response = client.post("/api/v1/deploy", json=payload)

        assert response.status_code == 404

    @patch('backend.api_rest.ProviderFactory.create_provider')
    @patch('backend.api_rest.template_manager')
    def test_deploy_failure(self, mock_template_manager, mock_factory, client):
        """Test POST /api/v1/deploy with deployment failure"""
        mock_provider = Mock()
        mock_provider.deploy = AsyncMock(return_value=DeploymentResult(
            success=False,
            deployment_id="failed-deployment",
            status="Failed",
            message="Deployment failed",
            error="Resource creation error",
            provider="azure",
            timestamp="2025-01-01T00:00:00Z"
        ))
        mock_factory.return_value = mock_provider
        mock_template_manager.get_template_path.return_value = "/path/to/template.bicep"

        payload = {
            "template_name": "storage-account",
            "provider_type": "azure",
            "subscription_id": "test-sub-id",
            "resource_group": "test-rg",
            "location": "eastus",
            "parameters": {}
        }

        response = client.post("/api/v1/deploy", json=payload)

        assert response.status_code == 200  # Still returns 200 but success=false
        data = response.json()
        assert data["success"] is False
        assert "error" in data["data"]

    def test_deploy_missing_required_fields(self, client):
        """Test POST /api/v1/deploy with missing required fields"""
        payload = {
            "template_name": "storage-account"
            # Missing other required fields
        }

        response = client.post("/api/v1/deploy", json=payload)

        assert response.status_code == 422  # Validation error


class TestResourceGroupsEndpoint:
    """Test resource groups endpoint"""

    @patch('backend.api_rest.ProviderFactory.create_provider')
    def test_list_resource_groups(self, mock_factory, client, mock_provider):
        """Test GET /api/v1/resource-groups"""
        mock_factory.return_value = mock_provider

        response = client.get(
            "/api/v1/resource-groups",
            params={
                "provider_type": "azure",
                "subscription_id": "test-sub-id"
            }
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert len(data["data"]["resource_groups"]) > 0

    @patch('backend.api_rest.ProviderFactory.create_provider')
    def test_create_resource_group(self, mock_factory, client, mock_provider):
        """Test POST /api/v1/resource-groups"""
        mock_provider.create_resource_group = AsyncMock(return_value=ResourceGroup(
            name="new-rg",
            location="eastus",
            id="/subscriptions/test/resourceGroups/new-rg",
            tags={"env": "test"}
        ))
        mock_factory.return_value = mock_provider

        payload = {
            "provider_type": "azure",
            "subscription_id": "test-sub-id",
            "name": "new-rg",
            "location": "eastus",
            "tags": {"env": "test"}
        }

        response = client.post("/api/v1/resource-groups", json=payload)

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["data"]["name"] == "new-rg"

    @patch('backend.api_rest.ProviderFactory.create_provider')
    def test_delete_resource_group(self, mock_factory, client, mock_provider):
        """Test DELETE /api/v1/resource-groups/{name}"""
        mock_provider.delete_resource_group = AsyncMock()
        mock_factory.return_value = mock_provider

        response = client.delete(
            "/api/v1/resource-groups/test-rg",
            params={
                "provider_type": "azure",
                "subscription_id": "test-sub-id"
            }
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


class TestResourcesEndpoint:
    """Test resources endpoint"""

    @patch('backend.api_rest.ProviderFactory.create_provider')
    def test_list_resources(self, mock_factory, client, mock_provider):
        """Test GET /api/v1/resources"""
        mock_factory.return_value = mock_provider

        response = client.get(
            "/api/v1/resources",
            params={
                "provider_type": "azure",
                "subscription_id": "test-sub-id",
                "resource_group": "test-rg"
            }
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert len(data["data"]["resources"]) > 0


class TestErrorHandling:
    """Test error handling"""

    def test_404_not_found(self, client):
        """Test 404 error for non-existent endpoint"""
        response = client.get("/api/v1/nonexistent")
        assert response.status_code == 404

    @patch('backend.api_rest.ProviderFactory.create_provider')
    def test_internal_server_error(self, mock_factory, client):
        """Test 500 error handling"""
        mock_factory.side_effect = Exception("Internal error")

        response = client.get(
            "/api/v1/resource-groups",
            params={
                "provider_type": "azure",
                "subscription_id": "test-sub-id"
            }
        )

        assert response.status_code == 500
        data = response.json()
        assert data["success"] is False


class TestCORS:
    """Test CORS configuration"""

    def test_cors_headers(self, client):
        """Test CORS headers are present"""
        response = client.options(
            "/api/v1/providers",
            headers={"Origin": "http://localhost:3000"}
        )

        assert response.status_code == 200
        assert "access-control-allow-origin" in response.headers


class TestOpenAPIDocumentation:
    """Test OpenAPI/Swagger documentation"""

    def test_openapi_json(self, client):
        """Test OpenAPI JSON is available"""
        response = client.get("/openapi.json")

        assert response.status_code == 200
        data = response.json()
        assert "openapi" in data
        assert "info" in data
        assert "paths" in data

    def test_swagger_ui(self, client):
        """Test Swagger UI is available"""
        response = client.get("/docs")

        assert response.status_code == 200
        assert "swagger" in response.text.lower() or "openapi" in response.text.lower()

    def test_redoc(self, client):
        """Test ReDoc is available"""
        response = client.get("/redoc")

        assert response.status_code == 200
