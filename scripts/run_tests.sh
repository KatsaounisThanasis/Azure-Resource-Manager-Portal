#!/bin/bash
# Test runner script with multiple options
# Usage: ./scripts/run_tests.sh [option]

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if pytest is installed
check_pytest() {
    if ! command -v pytest &> /dev/null; then
        print_error "pytest not found. Installing test dependencies..."
        pip install -r tests/requirements-test.txt
    fi
}

# Main test commands
run_all_tests() {
    print_header "Running All Tests"
    pytest -c tests/pytest.ini -v
}

run_unit_tests() {
    print_header "Running Unit Tests"
    pytest -c tests/pytest.ini tests/unit/ -v
}

run_integration_tests() {
    print_header "Running Integration Tests"
    pytest -c tests/pytest.ini tests/integration/ -v
}

run_e2e_tests() {
    print_header "Running E2E Tests"
    pytest -c tests/pytest.ini tests/e2e/ -v
}

run_fast_tests() {
    print_header "Running Fast Tests"
    pytest -c tests/pytest.ini -v -m "not slow and not docker"
}

run_with_coverage() {
    print_header "Running Tests with Coverage"
    pytest -c tests/pytest.ini --cov=backend --cov-report=html --cov-report=term-missing
    print_success "Coverage report generated at htmlcov/index.html"
}

run_specific_test() {
    print_header "Running Specific Test: $1"
    pytest -c tests/pytest.ini "$1" -v
}

run_by_marker() {
    print_header "Running Tests with Marker: $1"
    pytest -c tests/pytest.ini -v -m "$1"
}

# Docker tests
run_docker_tests() {
    print_header "Running Docker Tests"

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first."
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi

    pytest -c tests/pytest.ini tests/e2e/test_docker_container.py -v -m docker
}

# CI mode (strict)
run_ci_tests() {
    print_header "Running CI Tests"

    echo -e "${BLUE}1. Code Formatting Check${NC}"
    black --check backend/ tests/ || print_error "Code formatting check failed"

    echo -e "${BLUE}2. Import Sorting Check${NC}"
    isort --check-only backend/ tests/ || print_error "Import sorting check failed"

    echo -e "${BLUE}3. Linting${NC}"
    flake8 backend/ tests/ --max-line-length=120 || print_error "Linting failed"

    echo -e "${BLUE}4. Type Checking${NC}"
    mypy backend/ --ignore-missing-imports || print_warning "Type checking has issues"

    echo -e "${BLUE}5. Security Check${NC}"
    bandit -r backend/ -ll || print_warning "Security issues found"

    echo -e "${BLUE}6. Unit Tests${NC}"
    pytest -c tests/pytest.ini tests/unit/ -v --cov=backend

    echo -e "${BLUE}7. Integration Tests${NC}"
    pytest -c tests/pytest.ini tests/integration/ -v

    print_success "All CI checks completed"
}

# Watch mode (requires pytest-watch)
run_watch_mode() {
    print_header "Running Tests in Watch Mode"

    if ! command -v ptw &> /dev/null; then
        print_error "pytest-watch not found. Installing..."
        pip install pytest-watch
    fi

    ptw -- -c tests/pytest.ini -v
}

# Parallel execution (requires pytest-xdist)
run_parallel_tests() {
    print_header "Running Tests in Parallel"

    if ! python -c "import xdist" &> /dev/null; then
        print_error "pytest-xdist not found. Installing..."
        pip install pytest-xdist
    fi

    pytest -c tests/pytest.ini -v -n auto
}

# Show usage
show_usage() {
    cat << EOF
Test Runner Script
==================

Usage: ./scripts/run_tests.sh [option]

Options:
  all               Run all tests (default)
  unit              Run unit tests only
  integration       Run integration tests only
  e2e               Run end-to-end tests only
  fast              Run fast tests (skip slow and docker)
  coverage          Run tests with coverage report
  docker            Run Docker container tests
  ci                Run CI pipeline tests (strict)
  watch             Run tests in watch mode
  parallel          Run tests in parallel
  marker <name>     Run tests with specific marker
  file <path>       Run specific test file
  help              Show this help message

Examples:
  ./scripts/run_tests.sh                    # Run all tests
  ./scripts/run_tests.sh unit               # Run unit tests
  ./scripts/run_tests.sh coverage           # Run with coverage
  ./scripts/run_tests.sh marker slow        # Run slow tests
  ./scripts/run_tests.sh file tests/unit/test_provider_factory.py

Available markers:
  unit, integration, e2e, slow, docker, azure, aws, gcp, smoke

EOF
}

# Main script logic
main() {
    # Check dependencies
    check_pytest

    # Parse command line arguments
    case "${1:-all}" in
        all)
            run_all_tests
            ;;
        unit)
            run_unit_tests
            ;;
        integration)
            run_integration_tests
            ;;
        e2e)
            run_e2e_tests
            ;;
        fast)
            run_fast_tests
            ;;
        coverage)
            run_with_coverage
            ;;
        docker)
            run_docker_tests
            ;;
        ci)
            run_ci_tests
            ;;
        watch)
            run_watch_mode
            ;;
        parallel)
            run_parallel_tests
            ;;
        marker)
            if [ -z "$2" ]; then
                print_error "Please specify a marker name"
                exit 1
            fi
            run_by_marker "$2"
            ;;
        file)
            if [ -z "$2" ]; then
                print_error "Please specify a test file path"
                exit 1
            fi
            run_specific_test "$2"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac

    # Print summary
    if [ $? -eq 0 ]; then
        print_success "Tests completed successfully!"
    else
        print_error "Tests failed!"
        exit 1
    fi
}

# Run main function
main "$@"
