"""
Template Management System

Automatically discovers and manages deployment templates across
different cloud providers and formats (Bicep, Terraform, ARM).
"""

import os
import json
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path
from dataclasses import dataclass, asdict
from enum import Enum

logger = logging.getLogger(__name__)


class TemplateFormat(Enum):
    """Supported template formats."""
    BICEP = "bicep"
    TERRAFORM = "terraform"
    ARM = "arm"


class CloudProvider(Enum):
    """Cloud providers."""
    AZURE = "azure"
    AWS = "aws"
    GCP = "gcp"


@dataclass
class TemplateMetadata:
    """Template metadata."""
    name: str
    display_name: str
    format: TemplateFormat
    cloud_provider: CloudProvider
    path: str
    description: Optional[str] = None
    category: Optional[str] = None
    parameters: Optional[List[Dict[str, Any]]] = None
    icon: str = "file-code"

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        result = asdict(self)
        result['format'] = self.format.value
        result['cloud_provider'] = self.cloud_provider.value
        return result


class TemplateManager:
    """
    Manages discovery and access to deployment templates.

    Automatically scans template directories and provides
    a unified interface for accessing templates across
    different formats and cloud providers.
    """

    def __init__(self, templates_root: str):
        """
        Initialize template manager.

        Args:
            templates_root: Root directory containing templates
        """
        self.templates_root = Path(templates_root)
        self._templates_cache: Dict[str, List[TemplateMetadata]] = {}
        self._refresh_cache()

    def _refresh_cache(self):
        """Scan and cache available templates."""
        logger.info(f"Scanning templates in {self.templates_root}")
        self._templates_cache = {
            "bicep": self._scan_bicep_templates(),
            "terraform-azure": self._scan_terraform_templates(CloudProvider.AZURE),
            "terraform-aws": self._scan_terraform_templates(CloudProvider.AWS),
            "terraform-gcp": self._scan_terraform_templates(CloudProvider.GCP),
        }

        total = sum(len(templates) for templates in self._templates_cache.values())
        logger.info(f"Found {total} templates across all providers")

    def _scan_bicep_templates(self) -> List[TemplateMetadata]:
        """Scan Bicep templates."""
        templates = []
        bicep_dir = self.templates_root

        if not bicep_dir.exists():
            logger.warning(f"Bicep directory not found: {bicep_dir}")
            return templates

        for bicep_file in bicep_dir.glob("*.bicep"):
            try:
                metadata = self._parse_bicep_metadata(bicep_file)
                templates.append(metadata)
            except Exception as e:
                logger.error(f"Error parsing {bicep_file}: {e}")

        logger.info(f"Found {len(templates)} Bicep templates")
        return templates

    def _scan_terraform_templates(self, cloud: CloudProvider) -> List[TemplateMetadata]:
        """Scan Terraform templates for a specific cloud."""
        templates = []
        tf_dir = self.templates_root / "terraform" / cloud.value

        if not tf_dir.exists():
            logger.warning(f"Terraform directory not found: {tf_dir}")
            return templates

        for tf_file in tf_dir.glob("*.tf"):
            try:
                metadata = self._parse_terraform_metadata(tf_file, cloud)
                templates.append(metadata)
            except Exception as e:
                logger.error(f"Error parsing {tf_file}: {e}")

        logger.info(f"Found {len(templates)} Terraform templates for {cloud.value}")
        return templates

    def _parse_bicep_metadata(self, bicep_file: Path) -> TemplateMetadata:
        """Parse Bicep template metadata."""
        name = bicep_file.stem
        display_name = name.replace("-", " ").replace("_", " ").title()

        # Try to extract description from file
        description = None
        try:
            with open(bicep_file, 'r') as f:
                first_line = f.readline()
                if first_line.startswith("//") or first_line.startswith("#"):
                    description = first_line.lstrip("/#").strip()
        except Exception:
            pass

        # Determine icon based on template name
        icon = self._determine_icon(name)

        return TemplateMetadata(
            name=name,
            display_name=display_name,
            format=TemplateFormat.BICEP,
            cloud_provider=CloudProvider.AZURE,
            path=str(bicep_file),
            description=description,
            icon=icon
        )

    def _parse_terraform_metadata(self, tf_file: Path, cloud: CloudProvider) -> TemplateMetadata:
        """Parse Terraform template metadata, loading from metadata.json if available."""
        name = tf_file.stem
        display_name = name.replace("-", " ").replace("_", " ").title()
        description = None
        parameters = None
        category = None

        # Check for metadata.json file
        metadata_file = tf_file.parent / f"{name}.metadata.json"
        if metadata_file.exists():
            try:
                with open(metadata_file, 'r') as f:
                    metadata_json = json.load(f)

                # Load metadata from JSON
                display_name = metadata_json.get('displayName', display_name)
                description = metadata_json.get('description')
                category = metadata_json.get('category')
                parameters = metadata_json.get('parameters', [])

                logger.debug(f"Loaded metadata from {metadata_file}")
            except Exception as e:
                logger.warning(f"Failed to load metadata from {metadata_file}: {e}")

        # Fallback: Try to extract description from template file
        if not description:
            try:
                with open(tf_file, 'r') as f:
                    first_line = f.readline()
                    if first_line.startswith("#"):
                        description = first_line.lstrip("#").strip()
            except Exception:
                pass

        # Determine icon
        icon = self._determine_icon(name)

        return TemplateMetadata(
            name=name,
            display_name=display_name,
            format=TemplateFormat.TERRAFORM,
            cloud_provider=cloud,
            path=str(tf_file),
            description=description,
            category=category,
            parameters=parameters,
            icon=icon
        )

    def _determine_icon(self, template_name: str) -> str:
        """Determine icon based on template name."""
        name_lower = template_name.lower()

        icon_map = {
            "storage": "hdd-stack",
            "bucket": "hdd-stack",
            "compute": "pc-display",
            "instance": "pc-display",
            "virtual-machine": "pc-display",
            "vm": "pc-display",
            "function": "code-slash",
            "lambda": "code-slash",
            "web": "globe",
            "app": "app",
            "database": "server",
            "sql": "server",
            "network": "diagram-3",
            "vpc": "diagram-3",
            "security": "shield-check",
            "key": "key",
            "vault": "lock",
        }

        for keyword, icon in icon_map.items():
            if keyword in name_lower:
                return icon

        return "file-code"

    def list_templates(
        self,
        provider_type: Optional[str] = None,
        cloud: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        List available templates.

        Args:
            provider_type: Filter by provider type (e.g., "azure", "terraform-aws")
            cloud: Filter by cloud provider (e.g., "azure", "aws", "gcp")

        Returns:
            List of template metadata dictionaries
        """
        if provider_type:
            # Return templates for specific provider type
            templates = self._templates_cache.get(provider_type, [])
        elif cloud:
            # Return templates for specific cloud across all formats
            templates = []
            for provider_templates in self._templates_cache.values():
                templates.extend([
                    t for t in provider_templates
                    if t.cloud_provider.value == cloud
                ])
        else:
            # Return all templates
            templates = []
            for provider_templates in self._templates_cache.values():
                templates.extend(provider_templates)

        return [t.to_dict() for t in templates]

    def get_template(self, template_name: str, provider_type: str) -> Optional[TemplateMetadata]:
        """
        Get specific template metadata.

        Args:
            template_name: Name of the template
            provider_type: Provider type (e.g., "azure", "gcp", "bicep", "terraform-azure")

        Returns:
            TemplateMetadata or None if not found
        """
        # Map new provider names to internal cache keys
        # "azure" includes BOTH bicep and terraform-azure templates
        # "gcp" maps to terraform-gcp templates
        provider_keys = self._map_provider_to_cache_keys(provider_type)

        for key in provider_keys:
            templates = self._templates_cache.get(key, [])
            for template in templates:
                if template.name == template_name:
                    return template
        return None

    def _map_provider_to_cache_keys(self, provider_type: str) -> List[str]:
        """
        Map provider type to internal cache keys.

        Args:
            provider_type: Provider type from API (e.g., "azure", "gcp")

        Returns:
            List of cache keys to search
        """
        # New provider names (azure, gcp)
        if provider_type == "azure":
            # Azure includes both Bicep and Terraform templates
            return ["bicep", "terraform-azure"]
        elif provider_type == "gcp":
            # GCP uses Terraform
            return ["terraform-gcp"]

        # Legacy provider names (for backward compatibility)
        elif provider_type in ["bicep", "terraform-azure", "terraform-aws", "terraform-gcp"]:
            return [provider_type]

        # Unknown provider
        return []

    def get_template_path(self, template_name: str, provider_type: str) -> Optional[str]:
        """
        Get path to template file.

        Args:
            template_name: Name of the template
            provider_type: Provider type

        Returns:
            Path to template file or None if not found
        """
        template = self.get_template(template_name, provider_type)
        return template.path if template else None

    def get_template_content(self, template_name: str, provider_type: str) -> Optional[str]:
        """
        Get template file content.

        Args:
            template_name: Name of the template
            provider_type: Provider type

        Returns:
            Template content as string or None if not found
        """
        path = self.get_template_path(template_name, provider_type)
        if not path:
            return None

        try:
            with open(path, 'r') as f:
                return f.read()
        except Exception as e:
            logger.error(f"Error reading template {path}: {e}")
            return None

    def get_providers_summary(self) -> Dict[str, Any]:
        """
        Get summary of available providers and template counts.

        Returns:
            Dictionary with provider information
        """
        return {
            "providers": [
                {
                    "id": "azure",
                    "name": "Azure (Bicep)",
                    "format": "bicep",
                    "cloud": "azure",
                    "template_count": len(self._templates_cache.get("bicep", []))
                },
                {
                    "id": "terraform-azure",
                    "name": "Azure (Terraform)",
                    "format": "terraform",
                    "cloud": "azure",
                    "template_count": len(self._templates_cache.get("terraform-azure", []))
                },
                {
                    "id": "terraform-aws",
                    "name": "AWS (Terraform)",
                    "format": "terraform",
                    "cloud": "aws",
                    "template_count": len(self._templates_cache.get("terraform-aws", []))
                },
                {
                    "id": "terraform-gcp",
                    "name": "GCP (Terraform)",
                    "format": "terraform",
                    "cloud": "gcp",
                    "template_count": len(self._templates_cache.get("terraform-gcp", []))
                },
            ],
            "total_templates": sum(len(t) for t in self._templates_cache.values())
        }

    def refresh(self):
        """Refresh template cache by rescanning directories."""
        self._refresh_cache()
