// utils.js - Utility functions and global variables

// Global variables
const apiBaseUrl = "http://localhost:8000";
let subscriptions = []; // Store loaded subscriptions
let isLoading = false;
let selectedTemplate = null;

// Template icons mapping - simplified and optimized
const templateIcons = {
    // Core Azure services
    "storage account": "bi-hdd-stack",
    "web app": "bi-globe", 
    "virtual machine": "bi-pc-display",
    "virtual machine ss": "bi-pc-display-horizontal",
    "virtual network": "bi-diagram-3",
    "function app": "bi-code-slash",
    "sql": "bi-server",
    "cosmos db": "bi-server",
    "keyvault": "bi-lock",
    "key vault": "bi-key",
    "load balancer": "bi-share",
    "public ip": "bi-globe",
    "nsg": "bi-shield-check",
    "network security group": "bi-shield-check",
    "aks": "bi-boxes",
    "log analytics": "bi-graph-up-arrow",
    "diagnostic settings": "bi-activity",
    
    // Default fallback for unknown templates
    "default": "bi-file-earmark"
};

// Azure Portal-style configuration options
const VM_IMAGES = [
    // Windows
    { os: 'Windows', publisher: 'MicrosoftWindowsServer', offer: 'WindowsServer', sku: '2019-Datacenter', version: 'latest' },
    { os: 'Windows', publisher: 'MicrosoftWindowsServer', offer: 'WindowsServer', sku: '2022-Datacenter', version: 'latest' },
    { os: 'Windows', publisher: 'MicrosoftWindowsServer', offer: 'WindowsServer', sku: '2016-Datacenter', version: 'latest' },
    // Linux
    { os: 'Linux', publisher: 'Canonical', offer: 'UbuntuServer', sku: '20_04-lts', version: 'latest' },
    { os: 'Linux', publisher: 'Canonical', offer: 'UbuntuServer', sku: '18_04-lts', version: 'latest' },
    { os: 'Linux', publisher: 'RedHat', offer: 'RHEL', sku: '8_6', version: 'latest' },
    { os: 'Linux', publisher: 'SUSE', offer: 'SLES', sku: '15-sp3', version: 'latest' },
];

// App Service Plan options (Azure Portal style)
if (!window.APP_SERVICE_PLANS) {
    window.APP_SERVICE_PLANS = [
        { os: 'Windows', tier: 'Free', sku: 'F1' },
        { os: 'Windows', tier: 'Basic', sku: 'B1' },
        { os: 'Windows', tier: 'Standard', sku: 'S1' },
        { os: 'Windows', tier: 'PremiumV2', sku: 'P1v2' },
        { os: 'Linux', tier: 'Basic', sku: 'B1' },
        { os: 'Linux', tier: 'Standard', sku: 'S1' },
        { os: 'Linux', tier: 'PremiumV3', sku: 'P1v3' },
    ];
}

// SQL Database options (Azure Portal style)
if (!window.SQL_EDITIONS) {
    window.SQL_EDITIONS = [
        { edition: 'Basic', compute: '5 DTUs', version: '12.0' },
        { edition: 'Standard', compute: 'S0', version: '12.0' },
        { edition: 'Standard', compute: 'S1', version: '12.0' },
        { edition: 'Premium', compute: 'P1', version: '12.0' },
        { edition: 'Premium', compute: 'P2', version: '12.0' },
        { edition: 'GeneralPurpose', compute: 'Gen5', version: '12.0' },
        { edition: 'BusinessCritical', compute: 'Gen5', version: '12.0' },
    ];
}

// Storage Account options (Azure Portal style)
if (!window.STORAGE_ACCOUNTS) {
    window.STORAGE_ACCOUNTS = [
        { kind: 'StorageV2', replication: 'LRS', performance: 'Standard' },
        { kind: 'StorageV2', replication: 'GRS', performance: 'Standard' },
        { kind: 'StorageV2', replication: 'ZRS', performance: 'Standard' },
        { kind: 'StorageV2', replication: 'LRS', performance: 'Premium' },
        { kind: 'BlobStorage', replication: 'LRS', performance: 'Standard' },
        { kind: 'FileStorage', replication: 'LRS', performance: 'Premium' },
    ];
}

// Helper functions
function showLoading(elementId, message = 'Loading...') {
    const element = document.getElementById(elementId);
    if (element) {
        element.innerHTML = `
            <div class="text-center p-4">
                <div class="spinner-border text-primary mb-3" role="status">
                    <span class="visually-hidden">Loading...</span>
                </div>
                <p class="text-muted">${message}</p>
            </div>
        `;
    }
}

function hideLoading() {
    // Remove any loading overlays
    const loadingOverlay = document.querySelector('.loading-overlay');
    if (loadingOverlay) {
        loadingOverlay.style.display = 'none';
    }
}

function showError(message) {
    const toast = document.createElement('div');
    toast.className = 'toast error-message';
    toast.innerHTML = `
        <div class="toast-header bg-danger text-white">
            <i class="bi bi-exclamation-triangle-fill me-2"></i>
            <strong class="me-auto">Error</strong>
            <button type="button" class="btn-close btn-close-white" data-bs-dismiss="toast"></button>
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

function showSuccess(message) {
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.innerHTML = `
        <div class="toast-header bg-success text-white">
            <i class="bi bi-check-circle-fill me-2"></i>
            <strong class="me-auto">Success</strong>
            <button type="button" class="btn-close btn-close-white" data-bs-dismiss="toast"></button>
        </div>
        <div class="toast-body">
            ${message}
        </div>
    `;
    const deploymentStatus = document.querySelector('.deployment-status');
    if (deploymentStatus) {
        deploymentStatus.appendChild(toast);
        const bsToast = new bootstrap.Toast(toast, { delay: 4000 });
        bsToast.show();
        toast.addEventListener('hidden.bs.toast', () => toast.remove());
    }
}

function collectParameters() {
    const parameters = {};
    
    // First, collect from the main resource group form (Deploy tab)
    const resourceGroupField = document.getElementById('resourceGroup');
    const locationField = document.getElementById('location');
    const subscriptionField = document.getElementById('subscription');
    
    if (resourceGroupField) {
        parameters.resourceGroupName = resourceGroupField.value || '';
    }
    if (locationField) {
        parameters.location = locationField.value || '';
    }
    if (subscriptionField) {
        parameters.subscription = subscriptionField.value || '';
    }
    
    // Then, collect from the parameters modal form (template-specific parameters)
    const form = document.getElementById('parametersForm');
    if (form) {
        const inputs = form.querySelectorAll('input, select, textarea');
        inputs.forEach(input => {
            if (input.name) { // Only process inputs with name attributes
                // Always include the parameter, even if empty
                if (input.name === 'tags') {
                    try {
                        const tagsValue = input.value.trim();
                        if (tagsValue) {
                            // Only try to parse if it looks like JSON
                            if (tagsValue.startsWith('{') && tagsValue.endsWith('}')) {
                                parameters[input.name] = JSON.parse(tagsValue);
                            } else {
                                // Treat as empty object if not valid JSON format
                                parameters[input.name] = {};
                            }
                        } else {
                            parameters[input.name] = {};
                        }                    } catch (e) {
                        // Invalid JSON for tags parameter - set to empty object
                        parameters[input.name] = {};
                    }
                } else if (["imagePublisher", "imageOffer", "imageSku"].includes(input.name)) {
                    parameters[input.name] = String(input.value || '');
                } else {
                    // Always include the parameter, even if empty
                    parameters[input.name] = input.value || '';
                }
            }
        });
    }
    
    return parameters;
}

// Dropdown management functions
function updateAppServicePlanDropdowns() {
    const osSelect = document.getElementById('param_os');
    const tierSelect = document.getElementById('param_tier');
    const skuSelect = document.getElementById('param_sku');
    if (!osSelect || !tierSelect || !skuSelect) return;
    
    const selectedOs = osSelect.value;
    const filteredByOs = window.APP_SERVICE_PLANS.filter(x => x.os === selectedOs);
    
    // Tier
    const tiers = [...new Set(filteredByOs.map(x => x.tier))];
    tierSelect.innerHTML = tiers.map(t => `<option value="${t}">${t}</option>`).join('');
    
    // SKU
    const selectedTier = tierSelect.value || tiers[0];
    const filteredByTier = filteredByOs.filter(x => x.tier === selectedTier);
    const skus = [...new Set(filteredByTier.map(x => x.sku))];
    skuSelect.innerHTML = skus.map(s => `<option value="${s}">${s}</option>`).join('');
    
    // Set values
    tierSelect.value = selectedTier;
    skuSelect.value = skus[0];
}

function setupAppServicePlanDropdownListeners() {
    const osSelect = document.getElementById('param_os');
    const tierSelect = document.getElementById('param_tier');
    if (osSelect) osSelect.addEventListener('change', updateAppServicePlanDropdowns);
    if (tierSelect) tierSelect.addEventListener('change', updateAppServicePlanDropdowns);
}

function updateSqlDropdowns() {
    const editionSelect = document.getElementById('param_edition');
    const computeSelect = document.getElementById('param_compute');
    const versionSelect = document.getElementById('param_version');
    if (!editionSelect || !computeSelect || !versionSelect) return;
    
    const selectedEdition = editionSelect.value;
    const filteredByEdition = window.SQL_EDITIONS.filter(x => x.edition === selectedEdition);
    
    // Compute
    const computes = [...new Set(filteredByEdition.map(x => x.compute))];
    computeSelect.innerHTML = computes.map(c => `<option value="${c}">${c}</option>`).join('');
    
    // Version
    const selectedCompute = computeSelect.value || computes[0];
    const filteredByCompute = filteredByEdition.filter(x => x.compute === selectedCompute);
    const versions = [...new Set(filteredByCompute.map(x => x.version))];
    versionSelect.innerHTML = versions.map(v => `<option value="${v}">${v}</option>`).join('');
    
    // Set values
    computeSelect.value = selectedCompute;
    versionSelect.value = versions[0];
}

function setupSqlDropdownListeners() {
    const editionSelect = document.getElementById('param_edition');
    const computeSelect = document.getElementById('param_compute');
    if (editionSelect) editionSelect.addEventListener('change', updateSqlDropdowns);
    if (computeSelect) computeSelect.addEventListener('change', updateSqlDropdowns);
}

function updateStorageDropdowns() {
    const kindSelect = document.getElementById('param_kind');
    const replicationSelect = document.getElementById('param_replication');
    const performanceSelect = document.getElementById('param_performance');
    if (!kindSelect || !replicationSelect || !performanceSelect) return;
    
    const selectedKind = kindSelect.value;
    const filteredByKind = window.STORAGE_ACCOUNTS.filter(x => x.kind === selectedKind);
    
    // Replication
    const replications = [...new Set(filteredByKind.map(x => x.replication))];
    replicationSelect.innerHTML = replications.map(r => `<option value="${r}">${r}</option>`).join('');
    
    // Performance
    const selectedReplication = replicationSelect.value || replications[0];
    const filteredByReplication = filteredByKind.filter(x => x.replication === selectedReplication);
    const performances = [...new Set(filteredByReplication.map(x => x.performance))];
    performanceSelect.innerHTML = performances.map(p => `<option value="${p}">${p}</option>`).join('');
    
    // Set values
    replicationSelect.value = selectedReplication;
    performanceSelect.value = performances[0];
}

function setupStorageDropdownListeners() {
    const kindSelect = document.getElementById('param_kind');
    const replicationSelect = document.getElementById('param_replication');
    if (kindSelect) kindSelect.addEventListener('change', updateStorageDropdowns);
    if (replicationSelect) replicationSelect.addEventListener('change', updateStorageDropdowns);
}

// Unified subscription loading function
async function loadSubscriptions(targetSelectId = 'subscription') {
    const selectElement = document.getElementById(targetSelectId);
    
    try {
        // Show loading state
        if (selectElement) {
            selectElement.innerHTML = '<option value="">Loading subscriptions...</option>';
            selectElement.disabled = true;
        }
          const response = await fetch("/subscriptions");
        if (!response.ok) {
            if (selectElement) {
                selectElement.innerHTML = '<option value="">Error loading subscriptions. Is Azure CLI logged in?</option>';
                selectElement.disabled = false;
            }
            return [];
        }
        
        const subscriptions = await response.json();
        
        if (selectElement) {
            selectElement.innerHTML = '<option value="">Select a subscription</option>';
            subscriptions.forEach((sub) => {
                const option = document.createElement("option");
                option.value = sub.id;
                option.textContent = sub.name;
                selectElement.appendChild(option);
            });
            selectElement.disabled = false;
        }
          return subscriptions;
    } catch (error) {
        if (selectElement) {
            selectElement.innerHTML = '<option value="">Failed to load subscriptions</option>';
            selectElement.disabled = false;
        }
        showError('Failed to load subscriptions: ' + error.message);
        return [];
    }
}

// Load subscriptions for modal with auto-population from main form
async function loadSubscriptionsForModal() {
    const subscriptions = await loadSubscriptions('newResourceGroupSubscription');
    
    // Pre-select the subscription if it's already selected in the main form
    const mainSubscriptionSelect = document.getElementById("subscription");
    const modalSubscriptionSelect = document.getElementById("newResourceGroupSubscription");
    
    if (mainSubscriptionSelect && modalSubscriptionSelect && mainSubscriptionSelect.value) {
        modalSubscriptionSelect.value = mainSubscriptionSelect.value;
    }
    
    return subscriptions;
}

// Confirmation dialog for destructive actions
function showConfirmDialog(title, message, confirmText = 'Confirm', cancelText = 'Cancel') {
    return new Promise((resolve) => {
        // Create modal HTML
        const modalHTML = `
            <div class="modal fade" id="confirmModal" tabindex="-1" aria-hidden="true">
                <div class="modal-dialog">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h5 class="modal-title">
                                <i class="bi bi-exclamation-triangle-fill text-warning me-2"></i>
                                ${title}
                            </h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                        </div>
                        <div class="modal-body">
                            <p>${message}</p>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">${cancelText}</button>
                            <button type="button" class="btn btn-danger" id="confirmBtn">${confirmText}</button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // Remove existing modal if any
        const existingModal = document.getElementById('confirmModal');
        if (existingModal) {
            existingModal.remove();
        }

        // Add modal to DOM
        document.body.insertAdjacentHTML('beforeend', modalHTML);

        // Get modal elements
        const modal = document.getElementById('confirmModal');
        const confirmBtn = document.getElementById('confirmBtn');
        const bootstrapModal = new bootstrap.Modal(modal);

        // Set up event listeners
        confirmBtn.addEventListener('click', () => {
            bootstrapModal.hide();
            resolve(true);
        });

        modal.addEventListener('hidden.bs.modal', () => {
            modal.remove();
            resolve(false);
        });

        // Show modal
        bootstrapModal.show();
    });
}

// Progress dialog for long-running operations
function showProgressDialog(title, message) {
    const modalHTML = `
        <div class="modal fade" id="progressModal" tabindex="-1" aria-hidden="true" data-bs-backdrop="static">
            <div class="modal-dialog">
                <div class="modal-content">
                    <div class="modal-header">
                        <h5 class="modal-title">
                            <i class="bi bi-hourglass-split text-primary me-2"></i>
                            ${title}
                        </h5>
                    </div>
                    <div class="modal-body text-center">
                        <div class="spinner-border text-primary mb-3" role="status">
                            <span class="visually-hidden">Loading...</span>
                        </div>
                        <p id="progressMessage">${message}</p>
                        <div class="progress mt-3" style="display: none;">
                            <div class="progress-bar progress-bar-striped progress-bar-animated" 
                                 role="progressbar" style="width: 0%" id="progressBar"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    `;

    // Remove existing modal if any
    const existingModal = document.getElementById('progressModal');
    if (existingModal) {
        existingModal.remove();
    }

    // Add modal to DOM
    document.body.insertAdjacentHTML('beforeend', modalHTML);

    const modal = document.getElementById('progressModal');
    const bootstrapModal = new bootstrap.Modal(modal);
    bootstrapModal.show();

    return {
        updateMessage: (newMessage) => {
            const messageEl = document.getElementById('progressMessage');
            if (messageEl) messageEl.textContent = newMessage;
        },
        updateProgress: (percentage) => {
            const progressContainer = modal.querySelector('.progress');
            const progressBar = document.getElementById('progressBar');
            if (progressContainer && progressBar) {
                progressContainer.style.display = 'block';
                progressBar.style.width = percentage + '%';
            }
        },
        close: () => {
            bootstrapModal.hide();
            setTimeout(() => modal.remove(), 300);
        }
    };
}

// Auto-save functionality enhancement
function setupAutoSave() {
    let autoSaveTimer;
    const AUTOSAVE_DELAY = 30000; // 30 seconds

    function triggerAutoSave() {
        clearTimeout(autoSaveTimer);
        autoSaveTimer = setTimeout(() => {
            saveCurrentParameters();
        }, AUTOSAVE_DELAY);
    }

    // Listen for form changes
    document.addEventListener('input', (e) => {
        if (e.target.matches('#parametersForm input, #parametersForm select, #parametersForm textarea')) {
            triggerAutoSave();
        }
    });

    return {
        save: () => saveCurrentParameters(),
        disable: () => clearTimeout(autoSaveTimer)
    };
}

// Auto-save current parameters to local storage
function saveCurrentParameters() {
    try {
        if (selectedTemplate) {
            const parameters = collectParameters();
            const autoSaveKey = `autosave_${selectedTemplate}`;
            localStorage.setItem(autoSaveKey, JSON.stringify({
                parameters,
                timestamp: Date.now(),
                template: selectedTemplate
            }));
        }
    } catch (error) {
        console.warn('Failed to auto-save parameters:', error);
    }
}