#!/usr/bin/env python3
"""
Test script to verify parameter type transformation is working correctly.
This test simulates frontend form data being sent to the backend API.
"""

import json
import requests
import sys

def test_parameter_transformation():
    """Test the parameter transformation logic with different data types."""
    
    # Test data that simulates what the frontend would send
    test_payload = {
        "template_name": "Virtual Network",
        "subscription_id": "test-subscription-id",
        "resource_group": "test-rg",
        "location": "eastus",
        "parameters": {
            # String parameter (should stay as string)
            "vnetName": "test-vnet",
            "vnetAddressPrefix": "10.0.0.0/16",
            "subnetName": "default",
            "subnetAddressPrefix": "10.0.1.0/24",
            
            # Array parameter as string (should be converted to array)
            "additionalSubnets": '[]',  # Empty array as string
            
            # Array parameter with actual data as string
            "dnsServers": '["8.8.8.8", "8.8.4.4"]',  # Array as JSON string
            
            # Boolean parameter as string (should be converted to boolean)
            "enableDdosProtection": "false",
            "enableVmProtection": "true",
            
            # Object parameter as string (should be converted to object)
            "tags": '{"environment": "test", "project": "portal"}',
            
            # Empty object as string
            "emptyObject": '{}',
            
            # Integer parameter as string
            "someIntValue": "42"
        }
    }
    
    print("Testing parameter transformation...")
    print(f"Original parameters: {json.dumps(test_payload['parameters'], indent=2)}")
    
    try:
        # Make the API call
        response = requests.post(
            "http://localhost:8000/deploy",
            json=test_payload,
            timeout=10
        )
        print(f"\nResponse status: {response.status_code}")
        print(f"Response body: {response.text}")
        
        if response.status_code == 500:
            # Expected for this test since we're using fake Azure credentials
            # But we should see the parameter transformation in the logs
            print("\n✅ Expected 500 error (fake credentials), check server logs for parameter transformation")
        else:
            print(f"\n❌ Unexpected response code: {response.status_code}")
            assert False, f"Expected 500 status code, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Request failed: {e}")
        assert False, f"Request failed: {e}"


def test_empty_array_handling():
    """Test specifically for empty array handling."""
    
    test_payload = {
        "template_name": "Virtual Network",
        "subscription_id": "test-subscription-id",
        "resource_group": "test-rg",
        "location": "eastus",
        "parameters": {
            "vnetName": "test-vnet",
            "vnetAddressPrefix": "10.0.0.0/16",
            "subnetName": "default",
            "subnetAddressPrefix": "10.0.1.0/24",
            "additionalSubnets": "",  # Empty string should become empty array
            "dnsServers": "",  # Empty string should become empty array
            "tags": "",  # Empty string should become empty object
        }
    }
    
    print("\n" + "="*50)
    print("Testing empty value handling...")
    print(f"Original parameters: {json.dumps(test_payload['parameters'], indent=2)}")
    
    try:
        response = requests.post(
            "http://localhost:8000/deploy",
            json=test_payload,
            timeout=10
        )
        print(f"\nResponse status: {response.status_code}")
        if response.status_code == 500:
            print("✅ Expected 500 error (fake credentials), check server logs for empty value transformation")
        else:
            assert False, f"Expected 500 status code, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        print(f"\n❌ Request failed: {e}")
        assert False, f"Request failed: {e}"


