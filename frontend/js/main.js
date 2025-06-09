// Main application initialization and event listeners

document.addEventListener('DOMContentLoaded', function () {
    // Initialize enhanced features
    setupFormValidation();
    const autoSaveInstance = setupAutoSave();
    
    // Load initial data
    loadTemplates();
    loadSubscriptions(); // Now uses unified function from utils.js

    // Template editing functionality
    const editTemplateBtn = document.getElementById('editTemplateBtn');
    if (editTemplateBtn) {
        editTemplateBtn.addEventListener('click', async () => {
            try {
                const response = await fetch(`/templates/${selectedTemplate}/content`);
                if (!response.ok) throw new Error('Failed to load template content');
                const templateContent = await response.text();
                document.getElementById('templateEditor').value = templateContent;
                const templateEditorModal = new bootstrap.Modal(document.getElementById('templateEditorModal'));
                templateEditorModal.show();
            } catch (error) {
                showError('Failed to load template content: ' + error.message);
            }
        });
    }

    const saveTemplateBtn = document.getElementById('saveTemplateBtn');
    if (saveTemplateBtn) {
        saveTemplateBtn.addEventListener('click', async () => {
            const templateContent = document.getElementById('templateEditor').value;
            try {
                const response = await fetch(`/templates/${selectedTemplate}`, {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ content: templateContent })
                });
                if (!response.ok) throw new Error('Failed to save template');
                showSuccess('Template saved successfully');
                bootstrap.Modal.getInstance(document.getElementById('templateEditorModal')).hide();
            } catch (error) {
                showError('Failed to save template: ' + error.message);
            }
        });
    }

    const saveParamsBtn = document.getElementById('saveParamsBtn');
    if (saveParamsBtn) {
        saveParamsBtn.addEventListener('click', () => {
            const saveParamsModal = new bootstrap.Modal(document.getElementById('saveParamsModal'));
            saveParamsModal.show();
        });
    }

    const submitSaveParams = document.getElementById('submitSaveParams');
    if (submitSaveParams) {
        submitSaveParams.addEventListener('click', async () => {
            const name = document.getElementById('paramSetName').value.trim();
            const description = document.getElementById('paramSetDescription').value.trim();
            const parameters = collectParameters();

            try {
                const response = await fetch('/saved-parameters', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        name,
                        description,
                        template: selectedTemplate,
                        parameters
                    })
                });

                if (!response.ok) throw new Error('Failed to save parameters');
                showSuccess('Parameters saved successfully');
                bootstrap.Modal.getInstance(document.getElementById('saveParamsModal')).hide();
                loadSavedParameters();
            } catch (error) {
                showError('Failed to save parameters: ' + error.message);
            }
        });
    }

    const exportJsonBtn = document.getElementById('exportJsonBtn');
    if (exportJsonBtn) {
        exportJsonBtn.addEventListener('click', () => {
            const parameters = collectParameters();
            const jsonString = JSON.stringify(parameters, null, 2);
            const blob = new Blob([jsonString], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `${selectedTemplate}-parameters.json`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        });
    }

    // Tab navigation functionality
    const deployTab = document.getElementById('deploy-tab');
    const deploymentHistoryTab = document.getElementById('history-tab');
    const resourceGroupsTab = document.getElementById('resources-tab');
    
    if (deployTab) {        deployTab.addEventListener('click', () => {
            document.getElementById('deploy').style.display = 'block';
            document.getElementById('history').style.display = 'none';
            document.getElementById('resources').style.display = 'none';
            loadTemplates();
            loadSubscriptions(); // Unified function from utils.js
        });
    }

    if (deploymentHistoryTab) {
        deploymentHistoryTab.addEventListener('click', () => {
            document.getElementById('deploy').style.display = 'none';
            document.getElementById('history').style.display = 'block';
            document.getElementById('resources').style.display = 'none';
            loadDeployments();
        });
    }

    if (resourceGroupsTab) {
        resourceGroupsTab.addEventListener('click', () => {
            document.getElementById('deploy').style.display = 'none';
            document.getElementById('history').style.display = 'none';
            document.getElementById('resources').style.display = 'block';
            loadResourceGroups();
        });
    }

    // Deploy button event listener
    const deployButton = document.getElementById('deployButton');
    if (deployButton) {
        deployButton.addEventListener('click', deployTemplate);
    }    // Create Resource Group button event listener
    const createResourceGroupBtn = document.getElementById('createResourceGroupBtn');
    if (createResourceGroupBtn) {
        createResourceGroupBtn.addEventListener('click', () => {
            // Load subscriptions in the modal when it's opened
            loadSubscriptionsForModal();
            const createResourceGroupModal = new bootstrap.Modal(document.getElementById('createResourceGroupModal'));
            createResourceGroupModal.show();
        });
    }// Create Resource Group button from Resources tab event listener
    const createResourceGroupBtnFromResources = document.getElementById('createResourceGroupBtnFromResources');
    if (createResourceGroupBtnFromResources) {
        createResourceGroupBtnFromResources.addEventListener('click', () => {
            // Load subscriptions in the modal when it's opened
            loadSubscriptionsForModal();
            const createResourceGroupModal = new bootstrap.Modal(document.getElementById('createResourceGroupModal'));
            createResourceGroupModal.show();
        });
    }

    // Submit Create Resource Group event listener
    const submitCreateResourceGroup = document.getElementById('submitCreateResourceGroup');
    if (submitCreateResourceGroup) {
        submitCreateResourceGroup.addEventListener('click', createResourceGroup);
    }

    // Modal event listeners for cascade setup
    const parametersModal = document.getElementById('parametersModal');
    if (parametersModal) {
        parametersModal.addEventListener('shown.bs.modal', function () {
            // Setup cascade dropdowns when modal is shown
            setupDropdownCascades();
        });
    }

    // Form validation helpers
    function validateForm() {
        const requiredFields = document.querySelectorAll('[required]');
        let isValid = true;
        
        requiredFields.forEach(field => {
            if (!field.value.trim()) {
                field.classList.add('is-invalid');
                isValid = false;
            } else {
                field.classList.remove('is-invalid');
            }
        });
        
        return isValid;
    }

    // Add form validation to all forms
    const forms = document.querySelectorAll('form');
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            if (!validateForm()) {
                e.preventDefault();
                e.stopPropagation();
                showError('Please fill in all required fields');
            }
        });
    });    // Real-time validation feedback
    const inputs = document.querySelectorAll('input[required], select[required], textarea[required]');
    inputs.forEach(input => {
        input.addEventListener('blur', function() {
            if (!this.value.trim()) {
                this.classList.add('is-invalid');
            } else {
                this.classList.remove('is-invalid');
            }
        });

        input.addEventListener('input', function() {
            if (this.classList.contains('is-invalid') && this.value.trim()) {
                this.classList.remove('is-invalid');
            }
        });
    });

    // Essential keyboard shortcuts only
    document.addEventListener('keydown', function(e) {
        // Escape to close modals
        if (e.key === 'Escape') {
            const modals = document.querySelectorAll('.modal.show');
            modals.forEach(modal => {
                const modalInstance = bootstrap.Modal.getInstance(modal);
                if (modalInstance) {
                    modalInstance.hide();
                }
            });
        }
    });

    // Enhanced Global error boundary and monitoring
    let errorCount = 0;
    const maxErrors = 5;
    const errorResetTime = 300000; // 5 minutes

    function resetErrorCount() {
        errorCount = 0;
    }

    // Reset error count every 5 minutes
    setInterval(resetErrorCount, errorResetTime);

    window.addEventListener('error', function(e) {
        errorCount++;
        console.error('Global error:', e.error);
        
        if (errorCount <= maxErrors) {
            showError(`An unexpected error occurred: ${e.error?.message || 'Unknown error'}. Please try again.`);
        } else {
            showError('Multiple errors detected. Please refresh the page.');        }
        
        if (window.console && window.console.error) {
            console.error('Error details:', {
                message: e.error?.message,
                stack: e.error?.stack,
                filename: e.filename,
                lineno: e.lineno,
                colno: e.colno
            });
        }
    });

    // Handle unhandled promise rejections
    window.addEventListener('unhandledrejection', function(e) {
        errorCount++;
        console.error('Unhandled promise rejection:', e.reason);
        
        if (errorCount <= maxErrors) {
            showError(`Operation failed: ${e.reason?.message || 'Network or server error'}. Please try again.`);
        }
        
        // Prevent the default browser error handling
        e.preventDefault();
    });

    // Network status monitoring
    function updateNetworkStatus() {
        if (navigator.onLine) {
            hideLoading();
            // Only show success if we were previously offline
            if (document.body.classList.contains('offline')) {
                showSuccess('Connection restored');
                document.body.classList.remove('offline');
            }
        } else {
            showError('No internet connection. Please check your network.');
            document.body.classList.add('offline');
        }
    }

    window.addEventListener('online', function() {
        updateNetworkStatus();
        // Retry failed operations
        retryFailedOperations();
    });

    window.addEventListener('offline', function() {
        updateNetworkStatus();
    });

    // Initial network status check
    updateNetworkStatus();

    // Failed operations retry mechanism
    let failedOperations = [];

    function addFailedOperation(operation) {
        failedOperations.push({
            operation,
            timestamp: Date.now()
        });
    }

    function retryFailedOperations() {
        const currentTime = Date.now();
        const retryWindow = 60000; // 1 minute
        
        failedOperations = failedOperations.filter(item => {
            if (currentTime - item.timestamp < retryWindow) {
                try {
                    item.operation();
                    return false; // Remove from failed operations
                } catch (error) {
                    console.error('Retry failed:', error);
                    return true; // Keep in failed operations
                }
            }
            return false; // Remove old operations
        });    }

    // Performance monitoring
    function monitorPerformance() {
        if ('performance' in window) {
            const loadTime = performance.now();
            // Monitor load time silently
        }
    }

    // Monitor performance after page load
    setTimeout(monitorPerformance, 1000);
});
