"""
Cost Estimation Module

Estimates deployment costs based on resource parameters and metadata.
Now with real-time pricing from Azure Retail Prices API and GCP pricing!
"""

from typing import Dict, Any, Optional, List
import logging
import asyncio
from backend.services.azure_api_client import get_azure_public_client
from backend.services.gcp_api_client import get_gcp_client

logger = logging.getLogger(__name__)

# Cost estimates per hour/month for common resources
COST_DATABASE = {
    # Azure VM Sizes (monthly estimates)
    'azure_vm': {
        'Standard_B1s': {'cost_per_month': 7.59, 'description': '1 vCPU, 1GB RAM'},
        'Standard_B2s': {'cost_per_month': 30.37, 'description': '2 vCPU, 4GB RAM'},
        'Standard_D2s_v3': {'cost_per_month': 70.08, 'description': '2 vCPU, 8GB RAM'},
        'Standard_D4s_v3': {'cost_per_month': 140.16, 'description': '4 vCPU, 16GB RAM'},
    },

    # GCP Machine Types (monthly estimates)
    'gcp_vm': {
        'e2-micro': {'cost_per_month': 6.11, 'description': '0.25 vCPU, 1GB RAM'},
        'e2-small': {'cost_per_month': 12.22, 'description': '0.5 vCPU, 2GB RAM'},
        'e2-medium': {'cost_per_month': 24.44, 'description': '1 vCPU, 4GB RAM'},
        'n1-standard-1': {'cost_per_month': 24.95, 'description': '1 vCPU, 3.75GB RAM'},
        'n1-standard-2': {'cost_per_month': 49.90, 'description': '2 vCPU, 7.5GB RAM'},
        'n2-standard-2': {'cost_per_month': 60.74, 'description': '2 vCPU, 8GB RAM'},
        'n2-standard-4': {'cost_per_month': 121.48, 'description': '4 vCPU, 16GB RAM'},
    },

    # Azure Storage Account (per GB/month)
    'azure_storage': {
        'LRS_Standard': {'cost_per_gb': 0.02, 'description': 'Locally Redundant Storage - Standard'},
        'GRS_Standard': {'cost_per_gb': 0.04, 'description': 'Geo-Redundant Storage - Standard'},
        'Premium': {'cost_per_gb': 0.15, 'description': 'Premium Storage'},
    },

    # GCP Storage Bucket (per GB/month)
    'gcp_storage': {
        'STANDARD': {'cost_per_gb': 0.02, 'description': 'Standard Storage'},
        'NEARLINE': {'cost_per_gb': 0.01, 'description': 'Nearline Storage'},
        'COLDLINE': {'cost_per_gb': 0.004, 'description': 'Coldline Storage'},
        'ARCHIVE': {'cost_per_gb': 0.0012, 'description': 'Archive Storage'},
    },

    # Disk costs (per GB/month)
    'disk_costs': {
        'pd-standard': 0.04,
        'pd-balanced': 0.10,
        'pd-ssd': 0.17,
        'azure_standard': 0.05,
        'azure_premium': 0.12,
    }
}


class CostEstimate:
    """Cost estimate result"""
    def __init__(self):
        self.monthly_cost: float = 0.0
        self.breakdown: List[Dict[str, Any]] = []
        self.notes: List[str] = []

    def add_component(self, name: str, cost: float, unit: str = 'month', details: str = ''):
        """Add a cost component to the estimate"""
        self.breakdown.append({
            'component': name,
            'cost': round(cost, 2),
            'unit': unit,
            'details': details
        })
        self.monthly_cost += cost

    def add_note(self, note: str):
        """Add a note about the estimate"""
        self.notes.append(note)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary"""
        return {
            'total_monthly_cost': round(self.monthly_cost, 2),
            'breakdown': self.breakdown,
            'notes': self.notes,
            'currency': 'USD'
        }


async def estimate_azure_vm_cost_realtime(parameters: Dict[str, Any]) -> CostEstimate:
    """Estimate cost for Azure Virtual Machine using real-time Azure Retail Prices API"""
    estimate = CostEstimate()

    # Get parameters
    vm_size = parameters.get('vm_size', 'Standard_B2s')
    region = parameters.get('location', parameters.get('region', 'eastus'))
    os_type = parameters.get('os_type', 'Linux')
    disk_size_gb = parameters.get('disk_size_gb', 30)

    try:
        # Get Azure API client
        azure_client = await get_azure_public_client()

        # Fetch real-time VM pricing
        vm_pricing = await azure_client.get_vm_pricing(
            vm_size=vm_size,
            region=region,
            operating_system=os_type
        )

        if vm_pricing:
            estimate.add_component(
                'Virtual Machine',
                vm_pricing['retail_price_per_month'],
                'month',
                f"{vm_size} - {vm_pricing.get('product_name', 'Azure VM')}"
            )
            estimate.add_note('✨ Real-time pricing from Azure Retail Prices API')
        else:
            # Fallback to hardcoded pricing
            vm_cost_info = COST_DATABASE['azure_vm'].get(vm_size)
            if vm_cost_info:
                estimate.add_component(
                    'Virtual Machine',
                    vm_cost_info['cost_per_month'],
                    'month',
                    f"{vm_size} - {vm_cost_info['description']}"
                )
            else:
                estimate.add_component('Virtual Machine', 50.0, 'month', f'{vm_size} (estimated)')
            estimate.add_note(f'Using estimated pricing (API data not available for {vm_size})')

        # Fetch real-time disk pricing
        disk_pricing = await azure_client.get_disk_pricing(
            disk_type='StandardSSD_LRS',
            region=region
        )

        if disk_pricing:
            disk_cost = disk_size_gb * (disk_pricing['price_per_month'] / 32)  # Approximate per GB
            estimate.add_component(
                'OS Disk',
                disk_cost,
                'month',
                f'{disk_size_gb} GB Standard SSD'
            )
        else:
            # Fallback
            disk_cost = disk_size_gb * COST_DATABASE['disk_costs']['azure_standard']
            estimate.add_component(
                'OS Disk',
                disk_cost,
                'month',
                f'{disk_size_gb} GB Standard SSD'
            )

    except Exception as e:
        logger.error(f"Error fetching real-time pricing: {e}")
        # Fallback to hardcoded pricing
        return estimate_azure_vm_cost_fallback(parameters)

    # Windows license note
    if os_type == 'Windows':
        estimate.add_note('Windows license cost is included in VM pricing')

    estimate.add_note('Costs may vary by region and are subject to change')
    estimate.add_note('Network egress charges apply separately')

    return estimate


def estimate_azure_vm_cost_fallback(parameters: Dict[str, Any]) -> CostEstimate:
    """Fallback: Estimate cost using hardcoded pricing database"""
    estimate = CostEstimate()

    # VM size cost
    vm_size = parameters.get('vm_size', 'Standard_B2s')
    vm_cost_info = COST_DATABASE['azure_vm'].get(vm_size)

    if vm_cost_info:
        estimate.add_component(
            'Virtual Machine',
            vm_cost_info['cost_per_month'],
            'month',
            f"{vm_size} - {vm_cost_info['description']}"
        )
    else:
        estimate.add_component('Virtual Machine', 50.0, 'month', f'{vm_size} (estimated)')
        estimate.add_note(f'Exact pricing for {vm_size} not available - using estimate')

    # OS Disk cost
    disk_size_gb = parameters.get('disk_size_gb', 30)
    disk_cost = disk_size_gb * COST_DATABASE['disk_costs']['azure_standard']
    estimate.add_component(
        'OS Disk',
        disk_cost,
        'month',
        f'{disk_size_gb} GB Standard SSD'
    )

    # Windows license (if applicable)
    os_type = parameters.get('os_type', 'Linux')
    if os_type == 'Windows':
        estimate.add_note('Windows license cost is included in VM pricing')

    estimate.add_note('Using estimated pricing (fallback)')
    estimate.add_note('Costs may vary by region and are subject to change')
    estimate.add_note('Network egress charges apply separately')

    return estimate


async def estimate_gcp_vm_cost_realtime(parameters: Dict[str, Any]) -> CostEstimate:
    """Estimate cost for GCP Compute Instance using GCP pricing API"""
    estimate = CostEstimate()

    # Get parameters
    machine_type = parameters.get('machine_type', 'e2-medium')
    region = parameters.get('region', 'us-central1')
    boot_disk_size = parameters.get('boot_disk_size', 20)
    boot_disk_type = parameters.get('boot_disk_type', 'pd-standard')

    try:
        # Get GCP API client
        gcp_client = await get_gcp_client()

        # Fetch compute pricing
        compute_pricing = await gcp_client.get_compute_pricing(
            machine_type=machine_type,
            region=region
        )

        if compute_pricing:
            estimate.add_component(
                'Compute Instance',
                compute_pricing['price_per_month'],
                'month',
                f"{machine_type} - {compute_pricing['vcpu_count']} vCPU, {compute_pricing['memory_gb']} GB RAM"
            )

            # Add notes from pricing
            for note in compute_pricing.get('notes', []):
                if note:  # Only add non-empty notes
                    estimate.add_note(note)
        else:
            # Fallback
            machine_cost_info = COST_DATABASE['gcp_vm'].get(machine_type)
            if machine_cost_info:
                estimate.add_component(
                    'Compute Instance',
                    machine_cost_info['cost_per_month'],
                    'month',
                    f"{machine_type} - {machine_cost_info['description']}"
                )
            else:
                estimate.add_component('Compute Instance', 50.0, 'month', f'{machine_type} (estimated)')
            estimate.add_note('Using estimated pricing')

        # Fetch disk pricing
        disk_pricing = await gcp_client.get_disk_pricing(
            disk_type=boot_disk_type,
            region=region
        )

        if disk_pricing:
            disk_cost = boot_disk_size * disk_pricing['price_per_gb_month']
            estimate.add_component(
                'Boot Disk',
                disk_cost,
                'month',
                f'{boot_disk_size} GB {boot_disk_type}'
            )
        else:
            # Fallback
            disk_cost_per_gb = COST_DATABASE['disk_costs'].get(boot_disk_type, 0.04)
            disk_cost = boot_disk_size * disk_cost_per_gb
            estimate.add_component(
                'Boot Disk',
                disk_cost,
                'month',
                f'{boot_disk_size} GB {boot_disk_type}'
            )

    except Exception as e:
        logger.error(f"Error fetching GCP real-time pricing: {e}")
        # Fallback
        return estimate_gcp_vm_cost_fallback(parameters)

    estimate.add_note('Network egress charges apply separately')

    return estimate


def estimate_gcp_vm_cost_fallback(parameters: Dict[str, Any]) -> CostEstimate:
    """Estimate cost for GCP Compute Instance"""
    estimate = CostEstimate()

    # Machine type cost
    machine_type = parameters.get('machine_type', 'e2-medium')
    machine_cost_info = COST_DATABASE['gcp_vm'].get(machine_type)

    if machine_cost_info:
        estimate.add_component(
            'Compute Instance',
            machine_cost_info['cost_per_month'],
            'month',
            f"{machine_type} - {machine_cost_info['description']}"
        )
    else:
        estimate.add_component('Compute Instance', 50.0, 'month', f'{machine_type} (estimated)')
        estimate.add_note(f'Exact pricing for {machine_type} not available - using estimate')

    # Boot disk cost
    boot_disk_size = parameters.get('boot_disk_size', 20)
    boot_disk_type = parameters.get('boot_disk_type', 'pd-standard')
    disk_cost_per_gb = COST_DATABASE['disk_costs'].get(boot_disk_type, 0.04)
    disk_cost = boot_disk_size * disk_cost_per_gb

    estimate.add_component(
        'Boot Disk',
        disk_cost,
        'month',
        f'{boot_disk_size} GB {boot_disk_type}'
    )

    estimate.add_note('Sustained use discounts may apply (up to 30% savings)')
    estimate.add_note('Network egress charges apply separately')

    return estimate


def estimate_azure_storage_cost(parameters: Dict[str, Any]) -> CostEstimate:
    """Estimate cost for Azure Storage Account"""
    estimate = CostEstimate()

    # Storage account has minimal base cost
    estimate.add_component('Storage Account Base', 0.5, 'month', 'Account management fee')

    # Replication type determines storage cost
    replication_type = parameters.get('account_replication_type', 'LRS')
    tier = parameters.get('account_tier', 'Standard')

    storage_key = f"{replication_type}_{tier}"
    storage_cost_info = COST_DATABASE['azure_storage'].get(storage_key)

    if not storage_cost_info:
        storage_cost_info = COST_DATABASE['azure_storage']['LRS_Standard']

    # Estimate 100GB usage for example
    estimated_gb = 100
    storage_cost = estimated_gb * storage_cost_info['cost_per_gb']

    estimate.add_component(
        'Storage Cost',
        storage_cost,
        'month',
        f"{estimated_gb} GB - {storage_cost_info['description']}"
    )

    estimate.add_note(f'Estimate based on {estimated_gb} GB of data')
    estimate.add_note('Transaction costs and bandwidth charges apply separately')

    return estimate


def estimate_gcp_storage_cost(parameters: Dict[str, Any]) -> CostEstimate:
    """Estimate cost for GCP Storage Bucket"""
    estimate = CostEstimate()

    # Storage class determines cost
    storage_class = parameters.get('storage_class', 'STANDARD')
    storage_cost_info = COST_DATABASE['gcp_storage'].get(storage_class)

    if not storage_cost_info:
        storage_cost_info = COST_DATABASE['gcp_storage']['STANDARD']

    # Estimate 100GB usage for example
    estimated_gb = 100
    storage_cost = estimated_gb * storage_cost_info['cost_per_gb']

    estimate.add_component(
        'Storage Cost',
        storage_cost,
        'month',
        f"{estimated_gb} GB - {storage_cost_info['description']}"
    )

    estimate.add_note(f'Estimate based on {estimated_gb} GB of data')
    estimate.add_note('Operations and network egress charges apply separately')

    if storage_class in ['NEARLINE', 'COLDLINE', 'ARCHIVE']:
        estimate.add_note(f'{storage_class} storage has minimum storage duration requirements')

    return estimate


async def estimate_deployment_cost(
    template_name: str,
    provider_type: str,
    parameters: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Estimate cost for a deployment using real-time pricing APIs.

    Args:
        template_name: Name of the template
        provider_type: Cloud provider type
        parameters: Template parameters

    Returns:
        Cost estimate dictionary with real-time pricing
    """
    try:
        # Determine which estimator to use
        estimate = None

        if 'virtual-machine' in template_name and 'azure' in provider_type:
            # Use real-time Azure pricing
            estimate = await estimate_azure_vm_cost_realtime(parameters)
        elif 'compute-instance' in template_name and 'gcp' in provider_type:
            # Use GCP pricing (currently uses hardcoded with API structure ready)
            estimate = await estimate_gcp_vm_cost_realtime(parameters)
        elif 'storage-account' in template_name and 'azure' in provider_type:
            estimate = estimate_azure_storage_cost(parameters)
        elif 'storage-bucket' in template_name and 'gcp' in provider_type:
            estimate = estimate_gcp_storage_cost(parameters)
        else:
            # Generic estimate
            estimate = CostEstimate()
            estimate.add_component('Resource', 25.0, 'month', 'Generic estimate')
            estimate.add_note(f'No specific cost model for {template_name}')
            estimate.add_note('This is a rough estimate - actual costs may vary significantly')

        result = estimate.to_dict()
        result['template_name'] = template_name
        result['provider_type'] = provider_type

        return result

    except Exception as e:
        logger.error(f"Error estimating cost: {e}")
        return {
            'total_monthly_cost': 0.0,
            'breakdown': [],
            'notes': [f'Error calculating cost estimate: {str(e)}'],
            'currency': 'USD',
            'error': str(e)
        }


def estimate_deployment_cost_sync(
    template_name: str,
    provider_type: str,
    parameters: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Synchronous wrapper for estimate_deployment_cost.
    Uses asyncio.run() to execute the async function.

    This is a compatibility layer for non-async code.
    """
    try:
        return asyncio.run(estimate_deployment_cost(template_name, provider_type, parameters))
    except Exception as e:
        logger.error(f"Error in sync wrapper: {e}")
        return {
            'total_monthly_cost': 0.0,
            'breakdown': [],
            'notes': [f'Error calculating cost estimate: {str(e)}'],
            'currency': 'USD',
            'error': str(e)
        }
