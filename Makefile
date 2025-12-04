# Makefile for Multi-Cloud Infrastructure Management API
# Provides convenient commands for development, testing, and deployment

.PHONY: help install install-dev test test-unit test-integration test-e2e test-coverage lint format clean docker-build docker-run docker-stop docs

# Default target
.DEFAULT_GOAL := help

# Variables
PYTHON := python3
PIP := $(PYTHON) -m pip
PYTEST := $(PYTHON) -m pytest -c tests/pytest.ini
BLACK := $(PYTHON) -m black
ISORT := $(PYTHON) -m isort
FLAKE8 := $(PYTHON) -m flake8
MYPY := $(PYTHON) -m mypy
DOCKER_IMAGE := multicloud-api
DOCKER_TAG := latest

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Multi-Cloud Infrastructure Management API$(NC)"
	@echo "$(BLUE)=============================================$(NC)"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

# Installation targets
install: ## Install production dependencies
	@echo "$(BLUE)Installing production dependencies...$(NC)"
	$(PIP) install -r requirements.txt

install-dev: ## Install development and testing dependencies
	@echo "$(BLUE)Installing development dependencies...$(NC)"
	$(PIP) install -r requirements.txt
	$(PIP) install -r tests/requirements-test.txt

install-all: install install-dev ## Install all dependencies

# Testing targets
test: ## Run all tests
	@echo "$(BLUE)Running all tests...$(NC)"
	$(PYTEST)

test-unit: ## Run unit tests only
	@echo "$(BLUE)Running unit tests...$(NC)"
	$(PYTEST) tests/unit/ -v

test-integration: ## Run integration tests only
	@echo "$(BLUE)Running integration tests...$(NC)"
	$(PYTEST) tests/integration/ -v

test-e2e: ## Run end-to-end tests only
	@echo "$(BLUE)Running E2E tests...$(NC)"
	$(PYTEST) tests/e2e/ -v

test-coverage: ## Run tests with coverage report
	@echo "$(BLUE)Running tests with coverage...$(NC)"
	$(PYTEST) --cov=backend --cov-report=html --cov-report=term-missing
	@echo "$(GREEN)Coverage report generated in htmlcov/index.html$(NC)"

test-fast: ## Run only fast tests (skip slow and docker tests)
	@echo "$(BLUE)Running fast tests...$(NC)"
	$(PYTEST) -m "not slow and not docker" -v

test-smoke: ## Run smoke tests
	@echo "$(BLUE)Running smoke tests...$(NC)"
	$(PYTEST) -m "smoke" -v

test-watch: ## Run tests in watch mode (requires pytest-watch)
	@echo "$(BLUE)Running tests in watch mode...$(NC)"
	ptw -- -v

# Code quality targets
lint: ## Run linting checks
	@echo "$(BLUE)Running linting...$(NC)"
	$(FLAKE8) backend/ tests/
	$(PYLINT) backend/ || true

type-check: ## Run type checking with mypy
	@echo "$(BLUE)Running type checks...$(NC)"
	$(MYPY) backend/

format: ## Format code with black and isort
	@echo "$(BLUE)Formatting code...$(NC)"
	$(BLACK) backend/ tests/
	$(ISORT) backend/ tests/
	@echo "$(GREEN)Code formatted successfully$(NC)"

format-check: ## Check if code is properly formatted
	@echo "$(BLUE)Checking code formatting...$(NC)"
	$(BLACK) --check backend/ tests/
	$(ISORT) --check-only backend/ tests/

security: ## Run security checks
	@echo "$(BLUE)Running security checks...$(NC)"
	bandit -r backend/ -ll
	safety check

quality: lint type-check format-check security ## Run all quality checks

# Docker targets
docker-build: ## Build Docker image
	@echo "$(BLUE)Building Docker image...$(NC)"
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .
	@echo "$(GREEN)Docker image built: $(DOCKER_IMAGE):$(DOCKER_TAG)$(NC)"

docker-build-minimal: ## Build minimal Docker image (Azure only)
	@echo "$(BLUE)Building minimal Docker image...$(NC)"
	docker build -f Dockerfile.minimal -t $(DOCKER_IMAGE):minimal .
	@echo "$(GREEN)Minimal Docker image built: $(DOCKER_IMAGE):minimal$(NC)"

docker-run: ## Run Docker container
	@echo "$(BLUE)Starting Docker container...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)Container started. API available at http://localhost:8000$(NC)"

docker-run-dev: ## Run Docker container in development mode
	@echo "$(BLUE)Starting Docker container in dev mode...$(NC)"
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d
	@echo "$(GREEN)Dev container started with hot reload$(NC)"

docker-stop: ## Stop Docker container
	@echo "$(BLUE)Stopping Docker containers...$(NC)"
	docker-compose down

docker-logs: ## View Docker container logs
	docker-compose logs -f

docker-test: ## Run tests in Docker container
	@echo "$(BLUE)Running tests in Docker...$(NC)"
	docker-compose run --rm api pytest

docker-shell: ## Open shell in Docker container
	docker-compose exec api /bin/bash

docker-clean: ## Remove Docker images and containers
	@echo "$(BLUE)Cleaning Docker resources...$(NC)"
	docker-compose down -v
	docker rmi $(DOCKER_IMAGE):$(DOCKER_TAG) $(DOCKER_IMAGE):minimal 2>/dev/null || true

# Development targets
dev: ## Start development server with hot reload
	@echo "$(BLUE)Starting development server...$(NC)"
	uvicorn backend.api_rest:app --reload --host 0.0.0.0 --port 8000

run: ## Run production server
	@echo "$(BLUE)Starting production server...$(NC)"
	uvicorn backend.api_rest:app --host 0.0.0.0 --port 8000

# Cleaning targets
clean: ## Clean generated files
	@echo "$(BLUE)Cleaning generated files...$(NC)"
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name ".coverage" -delete
	rm -rf htmlcov/ .pytest_cache/ .mypy_cache/ .coverage coverage.xml
	@echo "$(GREEN)Cleanup complete$(NC)"

clean-all: clean docker-clean ## Clean everything including Docker

# Documentation targets
docs: ## Generate documentation
	@echo "$(BLUE)Generating documentation...$(NC)"
	@echo "Documentation available in docs/ folder"

docs-api: ## Open API documentation in browser
	@echo "$(BLUE)Opening API documentation...$(NC)"
	@echo "Swagger UI: http://localhost:8000/docs"
	@echo "ReDoc: http://localhost:8000/redoc"

# CI/CD targets
ci-test: install-dev test-coverage lint type-check ## Run all CI tests

ci-build: docker-build ## Build for CI/CD

# Setup targets
setup: install-dev ## Initial setup for development
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@echo "$(GREEN)Setup complete! Run 'make dev' to start development server$(NC)"

# Deployment targets
deploy-local: docker-build docker-run ## Deploy locally with Docker

health-check: ## Check if API is healthy
	@echo "$(BLUE)Checking API health...$(NC)"
	@curl -f http://localhost:8000/health || echo "$(RED)API is not responding$(NC)"

# Database targets (for future use)
# db-migrate: ## Run database migrations
# db-reset: ## Reset database

# Utility targets
requirements: ## Update requirements.txt from installed packages
	$(PIP) freeze > requirements.txt

check-deps: ## Check for outdated dependencies
	$(PIP) list --outdated

version: ## Show version information
	@echo "Python: $$($(PYTHON) --version)"
	@echo "pip: $$($(PIP) --version)"
	@echo "Docker: $$(docker --version 2>/dev/null || echo 'Not installed')"
	@echo "docker-compose: $$(docker-compose --version 2>/dev/null || echo 'Not installed')"

info: ## Show project information
	@echo "$(BLUE)Project Information$(NC)"
	@echo "===================="
	@echo "Name: Multi-Cloud Infrastructure Management API"
	@echo "Location: $$(pwd)"
	@echo "Python: $$(which $(PYTHON))"
	@echo "Virtual Environment: $${VIRTUAL_ENV:-Not activated}"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make install-dev    - Install dependencies"
	@echo "  2. make test           - Run tests"
	@echo "  3. make dev            - Start dev server"
