import { useState, useEffect } from 'react';
import { getDynamicOptions, templateAPI } from '../api/client';
import { formatParameterLabel } from '../utils/formatters';
import CostPreview from './CostPreview';

const STEPS = [
  { id: 1, name: 'Provider & Template', icon: '📦' },
  { id: 2, name: 'Core Configuration', icon: '⚙️' },
  { id: 3, name: 'Required Parameters', icon: '📝' },
  { id: 4, name: 'Review & Deploy', icon: '🚀' }
];

function DeploymentWizard({ template, provider, onCancel, onDeploy }) {
  const [currentStep, setCurrentStep] = useState(2); // Start at step 2 (template already selected)
  const [parameters, setParameters] = useState([]);
  const [formData, setFormData] = useState({});
  const [tags, setTags] = useState([]);
  const [tagInput, setTagInput] = useState('');
  const [loading, setLoading] = useState(true);
  const [errors, setErrors] = useState({});
  const [dynamicOptions, setDynamicOptions] = useState({}); // Store dynamic options for parameters
  const [loadingOptions, setLoadingOptions] = useState({}); // Track loading state per parameter
  const [createNewRG, setCreateNewRG] = useState(false); // Track if user wants to create new RG
  const [newRGName, setNewRGName] = useState(''); // New resource group name input

  // Format template name - remove dashes and capitalize
  const formatTemplateName = (name) => {
    return name
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  };

  // Fetch template parameters
  useEffect(() => {
    const fetchParameters = async () => {
      try {
        const response = await templateAPI.getParameters(provider, template.name);
        console.log('[DeploymentWizard] Fetched parameters:', response.data.data.parameters);
        console.log('[DeploymentWizard] Parameters with allowed_values:',
          response.data.data.parameters.filter(p => p.allowed_values).map(p => ({
            name: p.name,
            values: p.allowed_values
          }))
        );
        setParameters(response.data.data.parameters);

        // Set default values
        const defaults = {};
        response.data.data.parameters.forEach(param => {
          if (param.default !== undefined) {
            defaults[param.name] = param.default;
          }
        });

        // Load credentials from settings if "Use from .env" is selected
        const savedSettings = sessionStorage.getItem('cloudCredentials') || localStorage.getItem('cloudCredentials');
        if (savedSettings) {
          try {
            const settings = JSON.parse(savedSettings);

            // For Azure templates - auto-fill subscription_id if using env credentials
            if (provider.toLowerCase().includes('azure')) {
              if (settings.azure?.mode === 'env') {
                // If using .env, set subscription_id to a placeholder that backend will handle
                defaults['subscription_id'] = 'USE_ENV_CREDENTIALS';
              } else if (settings.azure?.mode === 'custom' && settings.azure?.subscriptionId) {
                // If custom, pre-fill with saved subscription ID
                defaults['subscription_id'] = settings.azure.subscriptionId;
              }
            }

            // For GCP templates - auto-fill project_id if using env credentials
            if (provider.toLowerCase().includes('gcp')) {
              if (settings.gcp?.mode === 'env') {
                defaults['project_id'] = 'USE_ENV_CREDENTIALS';
              } else if (settings.gcp?.mode === 'custom' && settings.gcp?.projectId) {
                defaults['project_id'] = settings.gcp.projectId;
              }
            }
          } catch (error) {
            console.error('Failed to load credentials from settings:', error);
          }
        }

        setFormData(defaults);
        setLoading(false);
      } catch (err) {
        console.error('Failed to fetch parameters:', err);
        setLoading(false);
      }
    };

    fetchParameters();
  }, [provider, template]);

  // Fetch dynamic options for specific parameters
  useEffect(() => {
    const fetchDynamicOptions = async () => {
      // Parameters that should have dynamic options
      const dynamicParamNames = ['vm_size', 'machine_type', 'location', 'region', 'zone', 'resource_group', 'resource_group_name'];

      for (const param of parameters) {
        // Check if this parameter should have dynamic options
        if (dynamicParamNames.includes(param.name) && !dynamicOptions[param.name]) {
          setLoadingOptions(prev => ({ ...prev, [param.name]: true }));

          try {
            // Build context for the API call
            const context = {
              location: formData.location,
              region: formData.region,
              zone: formData.zone
            };

            const options = await getDynamicOptions(provider, param.name, context);

            if (options && options.length > 0) {
              console.log(`[DeploymentWizard] Loaded ${options.length} dynamic options for ${param.name}`);
              setDynamicOptions(prev => ({
                ...prev,
                [param.name]: options
              }));
            }
          } catch (error) {
            console.error(`Failed to fetch dynamic options for ${param.name}:`, error);
          } finally {
            setLoadingOptions(prev => ({ ...prev, [param.name]: false }));
          }
        }
      }
    };

    if (parameters.length > 0) {
      fetchDynamicOptions();
    }
  }, [parameters, provider, formData.location, formData.region]); // Re-fetch when location/region changes

  // Categorize parameters
  // subscription_id and project_id are auto-populated from .env, so exclude them
  const coreParams = parameters.filter(p =>
    ['location', 'region', 'resource_group', 'resource_group_name'].includes(p.name)
  );

  const requiredParams = parameters.filter(p =>
    p.required && !coreParams.some(c => c.name === p.name)
  );

  const optionalParams = parameters.filter(p => !p.required);

  const handleInputChange = (paramName, value) => {
    setFormData(prev => ({
      ...prev,
      [paramName]: value
    }));
    // Clear error for this field
    setErrors(prev => ({
      ...prev,
      [paramName]: null
    }));
  };

  const validateStep = (step) => {
    const newErrors = {};
    let paramsToValidate = [];

    if (step === 2) {
      paramsToValidate = coreParams;
    } else if (step === 3) {
      paramsToValidate = requiredParams;
    }

    paramsToValidate.forEach(param => {
      if (param.required && !formData[param.name]) {
        newErrors[param.name] = 'This field is required';
      }
    });

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleNext = () => {
    if (validateStep(currentStep)) {
      setCurrentStep(prev => Math.min(prev + 1, 4));
    }
  };

  const handleBack = () => {
    setCurrentStep(prev => Math.max(prev - 1, 2));
  };

  const handleSubmit = () => {
    if (validateStep(currentStep)) {
      // Convert tags array to object
      // If tag contains ':', split it. Else use tag as key and 'true' as value.
      const tagsMap = {};
      tags.forEach(tag => {
        if (tag.includes(':')) {
          const [key, value] = tag.split(':').map(s => s.trim());
          if (key) tagsMap[key] = value || '';
        } else {
          tagsMap[tag] = 'true';
        }
      });

      // Include tags in form data
      const deploymentData = {
        ...formData,
        tags: tagsMap
      };
      onDeploy(deploymentData);
    }
  };

  const handleAddTag = () => {
    const trimmedTag = tagInput.trim();
    if (trimmedTag && !tags.includes(trimmedTag)) {
      setTags([...tags, trimmedTag]);
      setTagInput('');
    }
  };

  const handleRemoveTag = (tagToRemove) => {
    setTags(tags.filter(tag => tag !== tagToRemove));
  };

  const handleTagInputKeyPress = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleAddTag();
    }
  };

  const renderInput = (param) => {
    const value = formData[param.name] || '';
    const error = errors[param.name];

    const baseInputClass = `mt-1 block w-full rounded-md shadow-sm sm:text-sm ${error
        ? 'border-red-300 focus:border-red-500 focus:ring-red-500'
        : 'border-gray-300 focus:border-blue-500 focus:ring-blue-500'
      }`;

    let inputElement;

    // Check if we have dynamic options for this parameter
    const hasDynamicOptions = dynamicOptions[param.name] && dynamicOptions[param.name].length > 0;
    const isLoadingDynamicOptions = loadingOptions[param.name];

    // Special handling for resource_group_name with "Create New" option
    const isResourceGroupParam = param.name === 'resource_group' || param.name === 'resource_group_name';

    // Priority 1: Dynamic options from API (most accurate)
    if (hasDynamicOptions) {
      const options = dynamicOptions[param.name];

      // Special handling for resource group with create new option
      if (isResourceGroupParam && (createNewRG || value === '__create_new__')) {
        inputElement = (
          <div className="space-y-2">
            <select
              value="__create_new__"
              onChange={(e) => {
                if (e.target.value !== '__create_new__') {
                  setCreateNewRG(false);
                  setNewRGName('');
                  handleInputChange(param.name, e.target.value);
                }
              }}
              className={baseInputClass}
            >
              {options.map(option => (
                <option key={option.name} value={option.name}>
                  {option.name === '__create_new__' ? option.display_name : `${option.display_name} (${option.description})`}
                </option>
              ))}
            </select>
            <input
              type="text"
              value={newRGName}
              onChange={(e) => {
                setNewRGName(e.target.value);
                handleInputChange(param.name, e.target.value);
              }}
              className={baseInputClass}
              placeholder="Enter new resource group name (e.g., rg-myapp-prod)"
            />
            <p className="text-xs text-blue-600">
              The resource group will be created automatically if it doesn't exist.
            </p>
          </div>
        );
      } else {
        inputElement = (
          <select
            value={value}
            onChange={(e) => {
              if (e.target.value === '__create_new__') {
                setCreateNewRG(true);
                handleInputChange(param.name, '');
              } else {
                setCreateNewRG(false);
                setNewRGName('');
                handleInputChange(param.name, e.target.value);
              }
            }}
            className={baseInputClass}
            disabled={isLoadingDynamicOptions}
          >
            <option value="">
              {isLoadingDynamicOptions ? 'Loading options...' : `Select ${formatParameterLabel(param.name)}...`}
            </option>
            {options.map(option => {
              // Special display for Create New option
              if (option.name === '__create_new__') {
                return (
                  <option key={option.name} value={option.name}>
                    {option.display_name}
                  </option>
                );
              }
              // For locations/regions, show display_name with technical name in parentheses
              if (option.display_name && !option.vcpus && !option.memory_gb) {
                return (
                  <option key={option.name} value={option.name}>
                    {option.display_name} ({option.name})
                  </option>
                );
              }
              // For VM sizes/machine types, show name with specs
              return (
                <option key={option.name} value={option.name}>
                  {option.name} - {option.description || `${option.vcpus || option.memory_gb || ''}`}
                </option>
              );
            })}
          </select>
        );
      }
    }
    // Priority 2: Static allowed_values from template
    else if (param.allowed_values && param.allowed_values.length > 0) {
      console.log('[DeploymentWizard] Rendering dropdown for:', param.name, 'with values:', param.allowed_values);
      inputElement = (
        <select
          value={value}
          onChange={(e) => handleInputChange(param.name, e.target.value)}
          className={baseInputClass}
        >
          <option value="">Select {param.name}...</option>
          {param.allowed_values.map(option => (
            <option key={option} value={option}>{option}</option>
          ))}
        </select>
      );
    }
    // Priority 3: Regular input based on type
    else {
      // Original type-based rendering
      switch (param.type) {
        case 'bool':
          inputElement = (
            <div className="flex items-center mt-1">
              <input
                type="checkbox"
                checked={value === true || value === 'true'}
                onChange={(e) => handleInputChange(param.name, e.target.checked)}
                className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
              />
              <label className="ml-2 text-sm text-gray-600">{param.description}</label>
            </div>
          );
          break;

        case 'number':
          inputElement = (
            <input
              type="number"
              value={value}
              onChange={(e) => handleInputChange(param.name, e.target.value)}
              className={baseInputClass}
              placeholder={param.description}
            />
          );
          break;

        case 'array':
          inputElement = (
            <textarea
              value={Array.isArray(value) ? value.join('\n') : value}
              onChange={(e) => handleInputChange(param.name, e.target.value.split('\n').filter(Boolean))}
              rows={3}
              className={baseInputClass}
              placeholder="One item per line"
            />
          );
          break;

        case 'object':
          inputElement = (
            <textarea
              value={typeof value === 'object' ? JSON.stringify(value, null, 2) : value}
              onChange={(e) => {
                try {
                  const parsed = JSON.parse(e.target.value);
                  handleInputChange(param.name, parsed);
                } catch {
                  handleInputChange(param.name, e.target.value);
                }
              }}
              rows={4}
              className={`${baseInputClass} font-mono text-xs`}
              placeholder="{}"
            />
          );
          break;

        default:
          // Detect if field should be password type (sensitive or contains 'password' in name)
          const isPasswordField = param.sensitive || param.name.toLowerCase().includes('password');
          inputElement = (
            <input
              type={isPasswordField ? "password" : "text"}
              value={value}
              onChange={(e) => handleInputChange(param.name, e.target.value)}
              className={baseInputClass}
              placeholder={param.description}
            />
          );
      }
    }

    return (
      <div key={param.name} className="mb-4">
        <label className="block text-sm font-medium text-gray-700">
          {formatParameterLabel(param.name)}
          {param.required && <span className="text-red-500 ml-1">*</span>}
        </label>
        {param.type !== 'bool' && param.description && (
          <p className="mt-1 text-xs text-gray-500">{param.description}</p>
        )}
        {inputElement}
        {error && (
          <p className="mt-1 text-sm text-red-600">{error}</p>
        )}
      </div>
    );
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center py-12">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto">
      {/* Progress Steps */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          {STEPS.map((step, index) => (
            <div key={step.id} className="flex items-center flex-1">
              <div className="flex flex-col items-center flex-1">
                <div
                  className={`w-12 h-12 rounded-full flex items-center justify-center text-lg font-semibold transition-all ${currentStep === step.id
                      ? 'bg-blue-600 text-white shadow-lg scale-110'
                      : currentStep > step.id
                        ? 'bg-green-500 text-white'
                        : 'bg-gray-200 text-gray-500'
                    }`}
                >
                  {currentStep > step.id ? '✓' : step.icon}
                </div>
                <p
                  className={`mt-2 text-xs font-medium ${currentStep === step.id
                      ? 'text-blue-600'
                      : currentStep > step.id
                        ? 'text-green-600'
                        : 'text-gray-500'
                    }`}
                >
                  {step.name}
                </p>
              </div>
              {index < STEPS.length - 1 && (
                <div
                  className={`h-1 flex-1 mx-2 transition-all ${currentStep > step.id ? 'bg-green-500' : 'bg-gray-200'
                    }`}
                />
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Step Content */}
      <div className="bg-white rounded-2xl shadow-lg p-8 mb-6">
        {/* Step 2: Core Configuration */}
        {currentStep === 2 && (
          <div>
            <h3 className="text-2xl font-bold text-gray-900 mb-2">Core Configuration</h3>
            <p className="text-gray-600 mb-6">
              Configure the essential cloud provider settings for your deployment.
            </p>
            {coreParams.length > 0 ? (
              coreParams.map(param => renderInput(param))
            ) : (
              <p className="text-gray-500 italic">No core parameters required for this template.</p>
            )}
          </div>
        )}

        {/* Step 3: Required Parameters */}
        {currentStep === 3 && (
          <div>
            <h3 className="text-2xl font-bold text-gray-900 mb-2">Required Parameters</h3>
            <p className="text-gray-600 mb-6">
              Fill in all required parameters for this template.
            </p>
            {requiredParams.length > 0 ? (
              requiredParams.map(param => renderInput(param))
            ) : (
              <p className="text-gray-500 italic">No additional required parameters.</p>
            )}
          </div>
        )}

        {/* Step 4: Review & Optional Parameters */}
        {currentStep === 4 && (
          <div>
            <h3 className="text-2xl font-bold text-gray-900 mb-6">Review & Deploy</h3>

            {/* Summary */}
            <div className="bg-gradient-to-r from-blue-50 to-indigo-50 rounded-xl p-6 mb-6 border border-blue-200">
              <h4 className="font-semibold text-gray-900 mb-4">Deployment Summary</h4>
              <dl className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <dt className="text-gray-600 font-medium">Template</dt>
                  <dd className="text-gray-900 mt-1">{template.display_name || formatTemplateName(template.name)}</dd>
                </div>
                <div>
                  <dt className="text-gray-600 font-medium">Provider</dt>
                  <dd className="text-gray-900 mt-1">{provider}</dd>
                </div>
                {Object.entries(formData).slice(0, 6).map(([key, value]) => (
                  <div key={key}>
                    <dt className="text-gray-600 font-medium">{key}</dt>
                    <dd className="text-gray-900 mt-1 truncate">{String(value)}</dd>
                  </div>
                ))}
              </dl>
            </div>

            {/* Cost Estimation */}
            <div className="mb-6">
              <CostPreview
                provider={provider}
                templateName={template.name}
                parameters={formData}
              />
            </div>

            {/* Tags Section */}
            <div className="mb-6 bg-white rounded-xl p-6 border border-gray-200">
              <h4 className="font-semibold text-gray-900 mb-4">Tags (Optional)</h4>
              <p className="text-sm text-gray-600 mb-4">
                Add tags to organize and filter your deployments
              </p>

              {/* Tag Input */}
              <div className="flex items-center gap-2 mb-4">
                <input
                  type="text"
                  value={tagInput}
                  onChange={(e) => setTagInput(e.target.value)}
                  onKeyDown={handleTagInputKeyPress}
                  placeholder="Enter tag (e.g., production, testing)"
                  className="flex-1 px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm focus:ring-blue-500 focus:border-blue-500"
                />
                <button
                  type="button"
                  onClick={handleAddTag}
                  className="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 transition-colors"
                >
                  Add Tag
                </button>
              </div>

              {/* Display Tags */}
              {tags.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {tags.map((tag, index) => (
                    <span
                      key={index}
                      className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800"
                    >
                      {tag}
                      <button
                        type="button"
                        onClick={() => handleRemoveTag(tag)}
                        className="ml-2 text-blue-600 hover:text-blue-800 font-bold"
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              )}
            </div>

            {/* Optional Parameters */}
            {optionalParams.length > 0 && (
              <details className="mb-6">
                <summary className="cursor-pointer font-semibold text-gray-900 hover:text-blue-600 mb-4">
                  Optional Parameters ({optionalParams.length})
                </summary>
                <div className="pl-4 border-l-4 border-blue-200">
                  {optionalParams.map(param => renderInput(param))}
                </div>
              </details>
            )}
          </div>
        )}
      </div>

      {/* Navigation Buttons */}
      <div className="flex justify-between items-center">
        <button
          onClick={currentStep === 2 ? onCancel : handleBack}
          className="px-6 py-3 bg-gray-100 text-gray-700 font-semibold rounded-xl hover:bg-gray-200 transition-all"
        >
          {currentStep === 2 ? 'Cancel' : 'Back'}
        </button>

        {currentStep < 4 ? (
          <button
            onClick={handleNext}
            className="px-6 py-3 bg-gradient-to-r from-blue-600 to-blue-700 text-white font-semibold rounded-xl hover:from-blue-700 hover:to-blue-800 shadow-lg hover:shadow-xl transition-all"
          >
            Continue
          </button>
        ) : (
          <button
            onClick={handleSubmit}
            className="px-8 py-3 bg-gradient-to-r from-green-600 to-green-700 text-white font-bold rounded-xl hover:from-green-700 hover:to-green-800 shadow-lg hover:shadow-xl transition-all"
          >
            Deploy Now 🚀
          </button>
        )}
      </div>
    </div>
  );
}

export default DeploymentWizard;
