// Templates management functions

async function loadTemplates() {
    // Show loading state
    const templateList = document.getElementById("templatesContainer");
    if (templateList) {
        showLoading("Loading templates...");
        templateList.innerHTML = `
            <div class="text-center p-4">
                <div class="spinner-border text-primary" role="status">
                    <span class="visually-hidden">Loading...</span>
                </div>
                <p class="mt-2 text-muted">Loading templates...</p>
            </div>
        `;
    }

    try {
        const response = await fetch("/templates");
        if (!response.ok) {
            hideLoading();
            if (templateList) {
                templateList.innerHTML = "<p class=\"text-muted\" style=\"text-align: center; padding: 20px;\"><i class=\"bi bi-exclamation-triangle-fill\" style=\"font-size: 2rem; display: block; margin-bottom: 10px;\"></i>Error loading templates. Check backend connection.</p>";
            }
            showError("Failed to load templates. Please check your connection.");
            return;
        }
        const templates = await response.json();
        
        hideLoading();
        templateList.innerHTML = "";
        
        if (templates.length === 0) {
            templateList.innerHTML = "<p class=\"text-muted\" style=\"text-align: center; padding: 20px;\"><i class=\"bi bi-box\" style=\"font-size: 2rem; display: block; margin-bottom: 10px;\"></i>No templates found.</p>";        } else {
            templates.forEach((template) => {
                const templateNameClean = template.template.toLowerCase().replace(/\s+/g, '');
                let iconClass = template.icon || templateIcons[templateNameClean] || templateIcons[template.template.toLowerCase()] || "bi-file-earmark";                if (iconClass && !iconClass.startsWith('bi-')) {
                    iconClass = 'bi-' + iconClass;
                }

                const templateCard = `
                    <div class="col-md-4 mb-3">
                        <div class="card template-card" data-template="${template.template}">
                            <div class="card-body text-center">
                                <i class="bi ${iconClass}" style="font-size: 3rem; color: #0078d4;"></i>
                                <h5 class="card-title mt-3">${template.template}</h5>
                                <button class="btn btn-primary select-template-btn" data-template="${template.template}">
                                    Select Template
                                </button>
                            </div>
                        </div>
                    </div>
                `;
                templateList.innerHTML += templateCard;
            });            // Add event listeners for template selection
            document.querySelectorAll('.select-template-btn').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    selectedTemplate = e.target.getAttribute('data-template');
                    showTemplateParameters(selectedTemplate);
                });
            });
        }
    } catch (error) {
        hideLoading();
        const templateList = document.getElementById("templatesContainer");
        if (templateList) {
            templateList.innerHTML = "<p class=\"text-muted\" style=\"text-align: center; padding: 20px;\"><i class=\"bi bi-exclamation-triangle-fill\" style=\"font-size: 2rem; display: block; margin-bottom: 10px;\"></i>Error loading templates.</p>";
        }
        showError("Failed to load templates: " + error.message);
    }
}

async function showTemplateParameters(templateName) {
    showLoading("Loading template parameters...");
    
    try {
        const response = await fetch(`/templates/${templateName}/parameters`);
        if (!response.ok) throw new Error('Failed to load template parameters');
        const parameters = await response.json();
        
        hideLoading();
        
        // Show the parameters modal
        const parametersModal = new bootstrap.Modal(document.getElementById('parametersModal'));
        parametersModal.show();
        
        // Populate the form with parameters
        const form = document.getElementById('parametersForm');
        if (form) {
            form.innerHTML = ''; // Clear existing form
            Object.entries(parameters).forEach(([name, param]) => {
                const formGroup = document.createElement('div');
                formGroup.className = 'mb-3';
                
                // Handle different parameter types
                let inputElement = '';
                if (param.allowedValues && param.allowedValues.length > 0) {
                    // Create dropdown for parameters with allowed values
                    const options = param.allowedValues.map(value => 
                        `<option value="${value}" ${value === param.defaultValue ? 'selected' : ''}>${value}</option>`
                    ).join('');
                    inputElement = `
                        <select class="form-select" id="param_${name}" name="${name}">
                            ${options}
                        </select>
                    `;
                } else if (param.type === 'bool') {
                    // Create checkbox for boolean parameters
                    inputElement = `
                        <div class="form-check">
                            <input class="form-check-input" type="checkbox" id="param_${name}" name="${name}" 
                                ${param.defaultValue === true ? 'checked' : ''}>
                            <label class="form-check-label" for="param_${name}">
                                ${param.metadata?.description || name}
                            </label>
                        </div>
                    `;                } else if (param.type === 'array') {
                    // Create textarea for array parameters
                    const defaultValue = param.defaultValue ? JSON.stringify(param.defaultValue, null, 2) : '[]';
                    inputElement = `
                        <textarea class="form-control" id="param_${name}" name="${name}" rows="3" 
                            placeholder='${param.metadata?.description || 'Enter JSON array, e.g., ["subnet1", "subnet2"] or leave empty for []'}'>${defaultValue}</textarea>
                        <small class="form-text text-muted">
                            <strong>Array format:</strong> JSON array like ["item1", "item2"] or empty for []. 
                            <br><strong>Examples:</strong> [] (empty), ["subnet1", "subnet2"] (strings), [8080, 443] (numbers)
                        </small>
                    `;
                } else if (param.type === 'object' || name === 'tags') {
                    // Create textarea for object/tags parameters
                    const defaultValue = param.defaultValue ? JSON.stringify(param.defaultValue, null, 2) : '{}';
                    inputElement = `
                        <textarea class="form-control" id="param_${name}" name="${name}" rows="3" 
                            placeholder="${param.metadata?.description || 'Enter JSON object'}">${defaultValue}</textarea>
                        <small class="form-text text-muted">Format: JSON object like {"key": "value"}</small>
                    `;
                } else {
                    // Default text input
                    inputElement = `
                        <input type="text" class="form-control" id="param_${name}" name="${name}" 
                            value="${param.defaultValue || ''}" 
                            placeholder="${param.metadata?.description || ''}">
                    `;
                }

                formGroup.innerHTML = `
                    <label for="param_${name}" class="form-label">${name}${param.type ? ` (${param.type})` : ''}</label>
                    ${inputElement}
                    <small class="form-text text-muted">${param.metadata?.description || ''}</small>
                `;
                form.appendChild(formGroup);
            });

            // Setup cascade dropdowns if needed
            setupDropdownCascades();
            
            // Load saved parameters for this template
            loadSavedParameters();
        }    } catch (error) {
        hideLoading();
        showError('Failed to load template parameters: ' + error.message);
    }
}

async function loadSavedParameters() {
    try {
        const response = await fetch(`/saved-parameters/${selectedTemplate}`);
        if (!response.ok) throw new Error('Failed to load saved parameters');
        const savedParams = await response.json();
        const container = document.querySelector('.saved-params-list');
        if (container) {
            container.innerHTML = savedParams.map(param => `
                <div class="saved-param-item" data-param-id="${param.id}">
                    <h6>${param.name}</h6>
                    <p class="text-muted mb-0">${param.description || 'No description'}</p>
                    <div class="mt-2">
                        <button class="btn btn-sm btn-outline-primary load-param" data-param-id="${param.id}">Load</button>
                        <button class="btn btn-sm btn-outline-danger delete-param" data-param-id="${param.id}">Delete</button>
                    </div>
                </div>
            `).join('');

            // Show the saved parameters section if there are any
            const savedParamsSection = document.querySelector('.saved-params-section');
            if (savedParamsSection) {
                savedParamsSection.style.display = savedParams.length > 0 ? 'block' : 'none';
            }

            // Add event listeners for the new buttons
            container.querySelectorAll('.load-param').forEach(button => {
                button.addEventListener('click', async (e) => {
                    const paramId = e.target.getAttribute('data-param-id');
                    await loadParameterSet(paramId);
                });
            });

            container.querySelectorAll('.delete-param').forEach(button => {
                button.addEventListener('click', async (e) => {
                    const paramId = e.target.getAttribute('data-param-id');                    if (confirm('Are you sure you want to delete this parameter set?')) {
                        await deleteParameterSet(paramId);
                    }
                });
            });
        }
    } catch (error) {
        // Error loading saved parameters - not critical
    }
}

async function loadParameterSet(paramId) {
    try {
        const response = await fetch(`/saved-parameters/load/${paramId}`);
        if (!response.ok) throw new Error('Failed to load parameter set');
        const paramSet = await response.json();
        
        // Populate form with saved parameters
        Object.entries(paramSet.parameters).forEach(([name, value]) => {
            const input = document.querySelector(`#param_${name}`);
            if (input) {
                if (input.type === 'checkbox') {
                    input.checked = value;
                } else if (typeof value === 'object') {
                    input.value = JSON.stringify(value, null, 2);
                } else {
                    input.value = value;
                }
            }
        });
        
        showSuccess('Parameter set loaded successfully');
    } catch (error) {
        showError('Failed to load parameter set: ' + error.message);
    }
}

async function deleteParameterSet(paramId) {
    try {
        const response = await fetch(`/saved-parameters/${paramId}`, {
            method: 'DELETE'
        });
        if (!response.ok) throw new Error('Failed to delete parameter set');
        
        showSuccess('Parameter set deleted successfully');
        loadSavedParameters();
    } catch (error) {
        showError('Failed to delete parameter set: ' + error.message);
    }
}

function setupDropdownCascades() {
    // Setup cascade dropdowns for Azure resources
    setupAppServicePlanDropdownListeners();
    setupSqlDropdownListeners();
    setupStorageDropdownListeners();
    
    // Call initial updates if dropdowns exist
    if (document.getElementById('param_os')) updateAppServicePlanDropdowns();
    if (document.getElementById('param_edition')) updateSqlDropdowns();
    if (document.getElementById('param_kind')) updateStorageDropdowns();
}
