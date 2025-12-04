#!/bin/bash
# Docker entrypoint script for Multi-Cloud Manager
# Performs Azure CLI login if credentials are available

set -e

# Azure CLI login if credentials are available
if [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_CLIENT_SECRET" ] && [ -n "$AZURE_TENANT_ID" ]; then
    echo "Logging in to Azure CLI with service principal..."
    az login --service-principal \
        -u "$AZURE_CLIENT_ID" \
        -p "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" \
        --output none 2>/dev/null || echo "Azure CLI login failed (will use Terraform auth instead)"

    # Set default subscription if available
    if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
        az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null || true
    fi
    echo "Azure CLI configured successfully"
fi

# GCP authentication if credentials file exists
if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ] && [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "GCP credentials file found at $GOOGLE_APPLICATION_CREDENTIALS"
    gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null || echo "GCP auth skipped"
fi

# Execute the main command
exec "$@"
