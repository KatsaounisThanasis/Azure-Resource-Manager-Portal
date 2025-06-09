#!/usr/bin/env python3
"""
Direct test of parameter transformation logic without API calls.
This test verifies that our parameter type conversion is working correctly.
"""

import json
import os
import sys

def load_arm_template():
    """Load and compile the Virtual Network Bicep template to get parameter types."""
    template_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "templates", "Virtual Network.bicep")
    
    if not os.path.exists(template_path):
        print(f"❌ Template file not found: {template_path}")
        return None
    
    # Read the compiled JSON file
    json_path = template_path.replace('.bicep', '.json')
    if os.path.exists(json_path):
        try:
            with open(json_path, 'r') as f:
                arm_template = json.load(f)
            return arm_template
        except Exception as e:
            print(f"❌ Error reading compiled template: {e}")
            return None
    else:
        print(f"❌ Compiled template not found: {json_path}")
        return None

def transform_parameters(arm_template, request_parameters):
    """Transform parameters using the same logic as the backend."""
    azure_parameters = {}
    template_parameters = arm_template.get("parameters", {})
    
    for param_name, param_value in request_parameters.items():
        # Handle cases where the value might be None
        if param_value is not None:
            # "Flatten" nested {"value": ...} structures
            actual_value = param_value
            while isinstance(actual_value, dict) and "value" in actual_value:
                actual_value = actual_value["value"]

            # Get the expected parameter type from the ARM template
            param_type = template_parameters.get(param_name, {}).get("type", "string").lower()
            
            print(f"\n🔄 Processing parameter '{param_name}' (expected type: {param_type})")
            print(f"   Input value: {repr(actual_value)}")
            
            # Convert the value to the correct type based on ARM template definition
            try:
                if param_type == "array":
                    # Parse string as JSON array, or use as-is if already an array
                    if isinstance(actual_value, str):
                        if actual_value.strip() == "":
                            actual_value = []
                            print(f"   ✅ Empty string → empty array: {actual_value}")
                        else:
                            try:
                                actual_value = json.loads(actual_value)
                                print(f"   ✅ JSON parsed array: {actual_value}")
                            except json.JSONDecodeError:
                                # If JSON parsing fails, try to split by comma and clean up
                                actual_value = [item.strip().strip('"\'') for item in actual_value.split(',') if item.strip()]
                                print(f"   ⚠️  JSON parse failed, comma split: {actual_value}")
                    elif not isinstance(actual_value, list):
                        actual_value = [actual_value]
                        print(f"   ✅ Single value → array: {actual_value}")
                    else:
                        print(f"   ✅ Already an array: {actual_value}")
                
                elif param_type == "object":
                    # Parse string as JSON object, or use as-is if already an object
                    if isinstance(actual_value, str):
                        if actual_value.strip() == "":
                            actual_value = {}
                            print(f"   ✅ Empty string → empty object: {actual_value}")
                        else:
                            actual_value = json.loads(actual_value)
                            print(f"   ✅ JSON parsed object: {actual_value}")
                    elif not isinstance(actual_value, dict):
                        actual_value = {}
                        print(f"   ⚠️  Non-dict converted to empty object: {actual_value}")
                    else:
                        print(f"   ✅ Already an object: {actual_value}")
                
                elif param_type == "bool":
                    # Convert string to boolean
                    if isinstance(actual_value, str):
                        actual_value = actual_value.lower() in ('true', '1', 'yes', 'on')
                        print(f"   ✅ String → boolean: {actual_value}")
                    else:
                        actual_value = bool(actual_value)
                        print(f"   ✅ Value → boolean: {actual_value}")
                
                elif param_type == "int":
                    # Convert to integer
                    if isinstance(actual_value, str):
                        actual_value = int(actual_value) if actual_value.strip() else 0
                        print(f"   ✅ String → integer: {actual_value}")
                    else:
                        actual_value = int(actual_value)
                        print(f"   ✅ Value → integer: {actual_value}")
                
                else:
                    print(f"   ✅ String type, no conversion needed: {repr(actual_value)}")
                
            except (json.JSONDecodeError, ValueError) as e:
                print(f"   ❌ Conversion failed: {e}. Using original value.")
                # If conversion fails, use the original value

            # Wrap the actual value in the {"value": ...} format required by Azure
            azure_parameters[param_name] = {"value": actual_value}
    
    return azure_parameters

def test_parameter_transformation():
    """Test the parameter transformation logic directly."""
    print("🧪 Testing Parameter Transformation Logic")
    print("=" * 50)
    
    # Load ARM template and parameters
    arm_template = load_arm_template()
    if not arm_template:
        assert False, "Failed to load ARM template"
    
    request_parameters = {
        "vnetName": "test-vnet",
        "vnetAddressPrefix": "10.0.0.0/16", 
        "subnetName": "default",
        "subnetAddressPrefix": "10.0.1.0/24",
        "additionalSubnets": "[\"subnet1\", \"subnet2\"]",
        "dnsServers": "[\"8.8.8.8\", \"8.8.4.4\"]",
        "enableDdosProtection": "false",
        "enableVmProtection": "true",
        "tags": "{\"environment\": \"test\", \"project\": \"portal\"}",
        "emptyObject": "{}",
        "someIntValue": "42"
    }    
    # Get parameter types from the ARM template
    template_parameters = arm_template.get("parameters", {})
    
    print("📋 ARM Template Parameter Definitions:")
    for param_name, param_def in template_parameters.items():
        param_type = param_def.get("type", "unknown")
        print(f"  - {param_name}: {param_type}")
    
    print(f"\n📥 Input Parameters (simulating frontend form data):")
    for param_name, param_value in request_parameters.items():
        print(f"  - {param_name}: {repr(param_value)}")
    
    # Transform parameters using the same logic as the backend
    azure_parameters = transform_parameters(arm_template, request_parameters)
    
    print(f"\n📤 Final Azure Parameters (backend output):")
    print(json.dumps(azure_parameters, indent=2))
    
    # Validate the results
    assert "vnetName" in azure_parameters
    assert azure_parameters["vnetName"]["value"] == "test-vnet"
    assert "additionalSubnets" in azure_parameters
    assert isinstance(azure_parameters["additionalSubnets"]["value"], list)
    assert azure_parameters["additionalSubnets"]["value"] == ["subnet1", "subnet2"]
    assert azure_parameters["enableDdosProtection"]["value"] is False
    assert azure_parameters["enableVmProtection"]["value"] is True
    assert isinstance(azure_parameters["tags"]["value"], dict)
    assert azure_parameters["tags"]["value"]["environment"] == "test"
    
    print("✅ All parameter transformations validated successfully!")


def main():
    """For standalone testing."""
    test_parameter_transformation()

if __name__ == "__main__":
    main()
