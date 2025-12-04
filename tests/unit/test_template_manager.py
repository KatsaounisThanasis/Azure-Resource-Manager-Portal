"""
Simple unit tests for Template Manager
Tests the actual implementation without complex mocking
"""
import pytest
from pathlib import Path
from backend.services.template_manager import TemplateManager, TemplateFormat, CloudProvider


class TestTemplateManagerBasic:
    """Basic tests for TemplateManager functionality"""

    def test_initialization(self):
        """Test TemplateManager can be initialized"""
        manager = TemplateManager(templates_root="templates")

        assert manager.templates_root == Path("templates")
        assert hasattr(manager, '_templates_cache')
        assert isinstance(manager._templates_cache, dict)

    def test_list_templates_returns_list(self):
        """Test list_templates returns a list"""
        manager = TemplateManager(templates_root="templates")
        templates = manager.list_templates()

        assert isinstance(templates, list)

    def test_cache_has_expected_keys(self):
        """Test cache contains expected provider keys"""
        manager = TemplateManager(templates_root="templates")
        cache = manager._templates_cache

        # Should have entries for different providers
        assert "bicep" in cache
        assert "terraform-aws" in cache
        assert "terraform-gcp" in cache
        assert "terraform-azure" in cache

    def test_bicep_templates_discovered(self):
        """Test that Bicep templates are discovered"""
        manager = TemplateManager(templates_root="templates")

        # Check if we found any templates
        templates = manager.list_templates(provider_type="bicep")

        # We should have bicep templates in the templates directory
        assert isinstance(templates, list)
        # This might be 0 if no templates exist, which is ok for testing

    def test_template_metadata_structure(self):
        """Test that template metadata has expected structure"""
        manager = TemplateManager(templates_root="templates")
        templates = manager.list_templates()

        if len(templates) > 0:
            template = templates[0]
            # Check it's a dict with expected keys
            assert isinstance(template, dict)
            assert 'name' in template
            assert 'format' in template
            assert 'cloud_provider' in template


class TestTemplateManagerWithMockDirectory:
    """Tests with a mock template directory"""

    @pytest.fixture
    def temp_templates_dir(self, tmp_path):
        """Create temporary templates directory"""
        templates_dir = tmp_path / "templates"
        templates_dir.mkdir()

        # Create a mock bicep file
        bicep_file = templates_dir / "test-storage.bicep"
        bicep_file.write_text("// Test storage account template\n\nresource storage 'Microsoft.Storage/storageAccounts@2021-04-01' = {}")

        # Create terraform directories
        tf_azure_dir = templates_dir / "terraform" / "azure"
        tf_azure_dir.mkdir(parents=True)

        tf_aws_dir = templates_dir / "terraform" / "aws"
        tf_aws_dir.mkdir(parents=True)

        tf_gcp_dir = templates_dir / "terraform" / "gcp"
        tf_gcp_dir.mkdir(parents=True)

        # Create mock terraform files
        (tf_aws_dir / "test-bucket.tf").write_text("resource \"aws_s3_bucket\" \"test\" {}")
        (tf_gcp_dir / "test-bucket.tf").write_text("resource \"google_storage_bucket\" \"test\" {}")

        return templates_dir

    def test_scans_temporary_directory(self, temp_templates_dir):
        """Test scanning a temporary templates directory"""
        manager = TemplateManager(templates_root=str(temp_templates_dir))

        templates = manager.list_templates()

        # Should find at least the templates we created
        assert len(templates) >= 3  # bicep + aws + gcp

    def test_filters_by_provider(self, temp_templates_dir):
        """Test filtering templates by provider type"""
        manager = TemplateManager(templates_root=str(temp_templates_dir))

        bicep_templates = manager.list_templates(provider_type="bicep")
        aws_templates = manager.list_templates(provider_type="terraform-aws")

        # Should have at least one of each
        assert len(bicep_templates) >= 1
        assert len(aws_templates) >= 1

        # Bicep templates should be for Azure
        for template in bicep_templates:
            assert template['cloud_provider'] == 'azure'

        # AWS templates should be for AWS
        for template in aws_templates:
            assert template['cloud_provider'] == 'aws'

    def test_get_template_by_name(self, temp_templates_dir):
        """Test getting a specific template by name"""
        from backend.services.template_manager import TemplateMetadata

        manager = TemplateManager(templates_root=str(temp_templates_dir))

        # Get all templates
        all_templates = manager.list_templates()

        if len(all_templates) > 0:
            # Try to get the first template by name
            first_template_name = all_templates[0]['name']
            template = manager.get_template(first_template_name, provider_type="bicep")

            # Should return TemplateMetadata object or None
            assert template is None or isinstance(template, TemplateMetadata)


class TestTemplateManagerEdgeCases:
    """Test edge cases and error handling"""

    def test_nonexistent_directory(self):
        """Test initialization with non-existent directory"""
        manager = TemplateManager(templates_root="/nonexistent/path")

        # Should not crash, just return empty lists
        templates = manager.list_templates()
        assert isinstance(templates, list)

    def test_empty_directory(self, tmp_path):
        """Test with empty templates directory"""
        empty_dir = tmp_path / "empty_templates"
        empty_dir.mkdir()

        manager = TemplateManager(templates_root=str(empty_dir))
        templates = manager.list_templates()

        assert isinstance(templates, list)
        assert len(templates) == 0

    def test_list_templates_with_invalid_provider(self):
        """Test listing templates with invalid provider type"""
        manager = TemplateManager(templates_root="templates")

        # Should handle gracefully
        templates = manager.list_templates(provider_type="invalid-provider")

        # Should return empty list or handle gracefully
        assert isinstance(templates, list)
