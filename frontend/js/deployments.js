// Deployments management functions

async function loadDeployments() {
    // Show loading state
    const deploymentHistory = document.getElementById("deploymentHistory");
    if (deploymentHistory) {
        showLoading("Loading deployment history...");
        deploymentHistory.innerHTML = `
            <div class="text-center p-4">
                <div class="spinner-border text-primary" role="status">
                    <span class="visually-hidden">Loading...</span>
                </div>
                <p class="mt-2 text-muted">Loading deployment history...</p>
            </div>
        `;
    }

    try {
        const response = await fetch("/deployments");
        if (!response.ok) {
            console.error(
                "Failed to load deployments:",
                response.status,
                await response.text()
            );
            hideLoading();
            if (deploymentHistory) {
                deploymentHistory.innerHTML = "<p><i class=\"bi bi-exclamation-triangle-fill me-2\"></i>Error loading deployment history. Is Azure CLI logged in?</p>";
            }
            showError("Failed to load deployment history. Please check Azure CLI login.");
            return;        }
        const deployments = await response.json();
        
        hideLoading();
        
        if (deploymentHistory) {
            deploymentHistory.innerHTML = "";
            if (deployments.length === 0) {
                deploymentHistory.innerHTML = "<p class=\"text-muted\" style=\"text-align: center; padding: 20px;\"><i class=\"bi bi-clock-history\" style=\"font-size: 2rem; display: block; margin-bottom: 10px;\"></i>No deployment history found.</p>";
            } else {
                const deploymentCards = deployments.map(deployment => {
                    const timestamp = new Date(deployment.timestamp).toLocaleString();
                    const statusIcon = deployment.status === 'success' ? 'bi-check-circle-fill' : 'bi-x-circle-fill';
                    
                    return `
                        <div class="col-md-6 mb-3">
                            <div class="card">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between align-items-start mb-2">
                                        <h6 class="card-title mb-0">${deployment.template}</h6>
                                        <span class="badge ${deployment.status === 'success' ? 'bg-success' : 'bg-danger'}">
                                            <i class="bi ${statusIcon} me-1"></i>${deployment.status}
                                        </span>
                                    </div>
                                    <p class="card-text text-muted small mb-2">
                                        <i class="bi bi-clock me-1"></i>${timestamp}
                                    </p>
                                    <p class="card-text text-muted small mb-2">
                                        <i class="bi bi-box me-1"></i>Resource Group: ${deployment.parameters.resourceGroupName || 'N/A'}
                                    </p>
                                    <div class="deployment-id-container">
                                        <small class="text-muted">
                                            <i class="bi bi-hash me-1"></i>
                                            <span style="font-family: monospace; font-size: 0.8em;">${deployment.deployment_id ? deployment.deployment_id.split('/').pop() : 'N/A'}</span>
                                        </small>
                                    </div>
                                </div>
                            </div>
                        </div>
                    `;
                }).join('');
                
                deploymentHistory.innerHTML = `
                    <div class="row">
                        ${deploymentCards}
                    </div>
                `;
            }
        }    } catch (error) {
        console.error("Error loading deployments:", error);
        hideLoading();
        const deploymentHistory = document.getElementById("deploymentHistory");
        if (deploymentHistory) {
            deploymentHistory.innerHTML = "<p><i class=\"bi bi-exclamation-triangle-fill me-2\"></i>Error loading deployment history.</p>";
        }
        showError("Failed to load deployment history: " + error.message);
    }
}

async function deployTemplate() {
    const parameters = collectParameters();
    
    // Enhanced validation with visual feedback
    const validationErrors = validateDeploymentParameters(parameters);
    if (validationErrors.length > 0) {
        showError('Please fix the following errors:\n• ' + validationErrors.join('\n• '));
        highlightValidationErrors(validationErrors);
        return;
    }

    // Show loading state with progress indicator
    const deployButton = document.getElementById('deployButton');
    const originalText = deployButton.innerHTML;
    deployButton.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status"></span>Deploying...';
    deployButton.disabled = true;
    
    showLoading("Deploying template... This may take several minutes.");    try {
        // Extract required fields for the backend API
        const subscriptionId = parameters.subscription || '';
        const resourceGroupName = parameters.resourceGroupName || '';
        const location = parameters.location || '';
        
        // Remove these fields from parameters since they're now top-level
        const templateParameters = { ...parameters };
        delete templateParameters.subscription;
        delete templateParameters.resourceGroupName;
        delete templateParameters.location;
        
        const deploymentData = {
            template_name: selectedTemplate,
            subscription_id: subscriptionId,
            resource_group: resourceGroupName,
            location: location,            parameters: templateParameters
        };

        const response = await fetch('/deploy', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(deploymentData)
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Deployment failed: ${errorText}`);
        }        const result = await response.json();
        
        hideLoading();
        showSuccess('Deployment initiated successfully! Monitoring deployment progress...');
        
        // Start monitoring the deployment if we have a deployment ID
        if (result.deployment_id) {
            monitorDeployment(result.deployment_id, selectedTemplate);
        }
        
        // Start polling for general deployment updates
        startDeploymentPolling();
        
        // Hide the parameters modal
        const parametersModal = bootstrap.Modal.getInstance(document.getElementById('parametersModal'));
        if (parametersModal) {
            parametersModal.hide();
        }
        
        // Reload deployments to show the new one
        setTimeout(() => {
            loadDeployments();
        }, 2000);

    } catch (error) {
        console.error('Deployment error:', error);
        hideLoading();
        showError('Deployment failed: ' + error.message);
    } finally {
        // Reset button state
        deployButton.innerHTML = originalText;
        deployButton.disabled = false;
    }
}

// Enhanced validation functions
function validateDeploymentParameters(parameters) {
    const errors = [];
    
    if (!selectedTemplate) {
        errors.push('Please select a template first');
    }
    
    // Check if resourceGroupName exists and is not empty after trimming
    const resourceGroupName = parameters.resourceGroupName || '';
    if (!resourceGroupName.trim()) {
        errors.push('Resource Group Name is required');
    }
    
    // Check if location exists and is not empty after trimming  
    const location = parameters.location || '';
    if (!location.trim()) {
        errors.push('Location is required');
    }
    
    // Validate resource group name format if it exists
    if (resourceGroupName.trim()) {
        const rgNamePattern = /^[a-zA-Z0-9._-]+$/;
        if (!rgNamePattern.test(resourceGroupName.trim())) {
            errors.push('Resource Group Name can only contain letters, numbers, periods, underscores, and hyphens');
        }
        if (resourceGroupName.trim().length > 90) {
            errors.push('Resource Group Name must be 90 characters or less');
        }
    }
    
    return errors;
}

function highlightValidationErrors(errors) {
    // Clear previous highlights
    document.querySelectorAll('.form-control.is-invalid').forEach(el => {
        el.classList.remove('is-invalid');
    });
    
    // Highlight specific fields based on error messages
    errors.forEach(error => {
        if (error.includes('Resource Group Name')) {
            const rgField = document.getElementById('param_resourceGroupName');
            if (rgField) {
                rgField.classList.add('is-invalid');
            }
        }
        if (error.includes('Location')) {
            const locationField = document.getElementById('param_location');
            if (locationField) {
                locationField.classList.add('is-invalid');
            }
        }
    });
}

// Real-time form validation
function setupFormValidation() {
    document.addEventListener('input', function(e) {
        if (e.target.matches('#param_resourceGroupName')) {
            validateResourceGroupName(e.target);
        }
        if (e.target.matches('#param_location')) {
            validateLocation(e.target);
        }
    });
}

function validateResourceGroupName(field) {
    const value = field.value.trim();
    const rgNamePattern = /^[a-zA-Z0-9._-]+$/;
    
    field.classList.remove('is-invalid', 'is-valid');
    
    if (value === '') {
        field.classList.add('is-invalid');
        showFieldError(field, 'Resource Group Name is required');
    } else if (!rgNamePattern.test(value)) {
        field.classList.add('is-invalid');
        showFieldError(field, 'Only letters, numbers, periods, underscores, and hyphens allowed');
    } else if (value.length > 90) {
        field.classList.add('is-invalid');
        showFieldError(field, 'Must be 90 characters or less');
    } else {
        field.classList.add('is-valid');
        hideFieldError(field);
    }
}

function validateLocation(field) {
    const value = field.value.trim();
    
    field.classList.remove('is-invalid', 'is-valid');
    
    if (value === '') {
        field.classList.add('is-invalid');
        showFieldError(field, 'Location is required');
    } else {
        field.classList.add('is-valid');
        hideFieldError(field);
    }
}

function showFieldError(field, message) {
    hideFieldError(field); // Clear existing error
    const errorDiv = document.createElement('div');
    errorDiv.className = 'invalid-feedback';
    errorDiv.textContent = message;
    field.parentNode.appendChild(errorDiv);
}

function hideFieldError(field) {
    const existingError = field.parentNode.querySelector('.invalid-feedback');
    if (existingError) {
        existingError.remove();
    }
}

// Deployment status polling
let deploymentPollingInterval = null;

function startDeploymentPolling() {
    // Poll every 30 seconds for deployment updates
    if (deploymentPollingInterval) {
        clearInterval(deploymentPollingInterval);
    }
    
    deploymentPollingInterval = setInterval(async () => {
        try {
            await loadDeployments();
        } catch (error) {
            console.error('Error polling deployments:', error);
        }
    }, 30000); // 30 seconds
}

function stopDeploymentPolling() {
    if (deploymentPollingInterval) {
        clearInterval(deploymentPollingInterval);
        deploymentPollingInterval = null;
    }
}

// Enhanced deployment monitoring
async function monitorDeployment(deploymentId, templateName) {
    const maxAttempts = 20; // Maximum 10 minutes (20 * 30 seconds)
    let attempts = 0;
    
    const checkStatus = async () => {
        try {
            const response = await fetch(`/deployments/${deploymentId}/status`);
            if (response.ok) {
                const status = await response.json();
                
                if (status.provisioningState === 'Succeeded') {
                    showSuccess(`Deployment of '${templateName}' completed successfully!`);
                    loadDeployments(); // Refresh the deployment list
                    return true; // Stop monitoring
                }
                
                if (status.provisioningState === 'Failed') {
                    showError(`Deployment of '${templateName}' failed. Check deployment history for details.`);
                    loadDeployments(); // Refresh the deployment list
                    return true; // Stop monitoring
                }
                
                // Still in progress
                console.log(`Deployment ${deploymentId} status:`, status.provisioningState);
            }
        } catch (error) {
            console.error('Error checking deployment status:', error);
        }
        
        attempts++;
        if (attempts >= maxAttempts) {
            showWarning(`Deployment monitoring timed out. Please check deployment history manually.`);
            return true; // Stop monitoring
        }
        
        return false; // Continue monitoring
    };
    
    // Initial check
    const shouldStop = await checkStatus();
    if (shouldStop) return;
    
    // Set up periodic checking
    const monitoringInterval = setInterval(async () => {
        const shouldStop = await checkStatus();
        if (shouldStop) {
            clearInterval(monitoringInterval);
        }
    }, 30000); // Check every 30 seconds
}

// Warning message function
function showWarning(message) {
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.innerHTML = `
        <div class="toast-header bg-warning text-dark">
            <i class="bi bi-exclamation-triangle-fill me-2"></i>
            <strong class="me-auto">Warning</strong>
            <button type="button" class="btn-close" data-bs-dismiss="toast"></button>
        </div>
        <div class="toast-body">
            ${message}
        </div>
    `;
    const deploymentStatus = document.querySelector('.deployment-status');
    if (deploymentStatus) {
        deploymentStatus.appendChild(toast);
        const bsToast = new bootstrap.Toast(toast, { delay: 5000 });
        bsToast.show();
        toast.addEventListener('hidden.bs.toast', () => toast.remove());
    }
}
