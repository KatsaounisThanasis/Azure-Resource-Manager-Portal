# Multi-Cloud Infrastructure Management API - Docker Image
# This Dockerfile creates a production-ready container with all dependencies

# Use official Python runtime as base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Required for Azure CLI
    curl \
    gnupg \
    lsb-release \
    # Required for Terraform
    wget \
    unzip \
    # Required for Bicep (.NET runtime)
    libicu-dev \
    # Git for potential future use
    git \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI (includes Bicep)
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Terraform
ARG TERRAFORM_VERSION=1.6.6
RUN wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && terraform --version

# Copy requirements first (for Docker layer caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY backend/ ./backend/
COPY templates/ ./templates/

# Copy and setup entrypoint script
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Create logs directory
RUN mkdir -p logs

# Create non-root user for security (but keep az cli access)
# chmod entrypoint BEFORE creating user to ensure root ownership
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
    useradd -m -u 1000 apiuser && \
    chown -R apiuser:apiuser /app && \
    mkdir -p /home/apiuser/.azure && \
    chown -R apiuser:apiuser /home/apiuser/.azure

# Switch to non-root user
USER apiuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Set default command (no entrypoint - Azure login done via docker-compose command)
CMD ["uvicorn", "backend.api.routes:app", "--host", "0.0.0.0", "--port", "8000"]
