import { useState, useEffect } from 'react';
import { getDynamicOptions, templateAPI } from '../api/client';

function DynamicForm({ provider, template, onSubmit, onCancel }) {
  const [parameters, setParameters] = useState([]);
  const [formData, setFormData] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [validationErrors, setValidationErrors] = useState({});
  const [dynamicOptions, setDynamicOptions] = useState({}); // Store dynamic options for parameters
  const [loadingOptions, setLoadingOptions] = useState({}); // Track loading state per parameter

  useEffect(() => {
    if (template) {
      fetchTemplateParameters();
      initializeFormData();
    }
  }, [template]);

  const initializeFormData = () => {
    // Set default values based on provider
    const defaults = {};

    if (provider === 'azure') {
      defaults.subscription_id = 'USE_ENV_CREDENTIALS';
      defaults.resource_group_name = `rg-${template.name}-${Date.now()}`;
      // location will be populated from dynamic options
    } else if (provider === 'gcp') {
      defaults.project_id = 'USE_ENV_CREDENTIALS';
      // region will be populated from dynamic options
    }

    setFormData(defaults);
  };

  const fetchTemplateParameters = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await templateAPI.getParameters(provider, template.name);

      if (response.data.success) {
        const params = response.data.data.parameters;
        console.log('[DynamicForm] Fetched parameters:', params);
        console.log('[DynamicForm] Parameters with allowed_values:',
          params.filter(p => p.allowed_values).map(p => ({ name: p.name, values: p.allowed_values }))
        );
        setParameters(params);

        // Set default values from parameters
        const defaults = { ...formData };
        params.forEach(param => {
          if (param.default !== undefined && param.default !== null) {
            defaults[param.name] = param.default;
          }
        });
        setFormData(defaults);
      }
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to load template parameters');
    } finally {
      setLoading(false);
    }
  };

  // Fetch dynamic options for specific parameters
  useEffect(() => {
    const fetchDynamicOptions = async () => {
      // Parameters that should have dynamic options
      const dynamicParamNames = ['vm_size', 'machine_type', 'location', 'region', 'zone'];

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
              console.log(`[DynamicForm] Loaded ${options.length} dynamic options for ${param.name}`);
              setDynamicOptions(prev => ({
                ...prev,
                [param.name]: options
              }));

              // Set first option as default if no value is set
              if (!formData[param.name] && options.length > 0) {
                setFormData(prev => ({
                  ...prev,
                  [param.name]: options[0].name
                }));
              }
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

  const handleChange = (paramName, value) => {
    setFormData(prev => ({
      ...prev,
      [paramName]: value
    }));

    // Validate on change
    const error = validateParameter(paramName, value);
    setValidationErrors(prev => ({
      ...prev,
      [paramName]: error
    }));
  };

  // Validation function
  const validateParameter = (paramName, value) => {
    const param = parameters.find(p => p.name === paramName);
    if (!param) return null;

    // Required check
    if (param.required && (!value || value === '')) {
      return 'This field is required';
    }

    // Skip validation for empty optional fields
    if (!value || value === '') return null;

    // Azure-specific validations
    if (provider === 'azure' || provider === 'terraform-azure') {
      if (paramName === 'storage_account_name' || paramName.includes('storage') && paramName.includes('name')) {
        if (!/^[a-z0-9]{3,24}$/.test(value)) {
          return '3-24 lowercase letters and numbers only';
        }
      }

      if (paramName === 'resource_group_name' || paramName === 'resource_group') {
        if (value.length < 1 || value.length > 90) {
          return 'Must be 1-90 characters';
        }
        if (value.endsWith('.')) {
          return 'Cannot end with a period';
        }
        if (!/^[\w\-\.\(\)]+$/.test(value)) {
          return 'Can only contain alphanumerics, underscores, hyphens, periods, and parentheses';
        }
      }
    }

    // GCP-specific validations
    if (provider === 'gcp' || provider === 'terraform-gcp') {
      if (paramName === 'bucket_name' || paramName === 'instance_name' || paramName === 'cluster_name') {
        if (value.length < 3 || value.length > 63) {
          return 'Must be 3-63 characters';
        }
        if (!/^[a-z]([-a-z0-9]*[a-z0-9])?$/.test(value)) {
          return 'Lowercase letters, numbers, hyphens; must start with letter';
        }
      }

      if (paramName === 'project_id') {
        if (value.length < 6 || value.length > 30) {
          return 'Must be 6-30 characters';
        }
        if (!/^[a-z]([-a-z0-9]*[a-z0-9])?$/.test(value)) {
          return 'Lowercase letters, numbers, hyphens; must start with letter';
        }
      }
    }

    // Common validations for all providers
    if (paramName === 'cidr_block' || paramName.includes('cidr') || paramName === 'address_space') {
      if (!/^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/([0-9]|[12][0-9]|3[0-2])$/.test(value)) {
        return 'Must be valid CIDR notation (e.g., 10.0.0.0/16)';
      }
    }

    if (paramName === 'ip_address' || (paramName.includes('ip') && !paramName.includes('cidr'))) {
      if (!/^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/.test(value)) {
        return 'Must be valid IPv4 address (e.g., 192.168.1.1)';
      }
    }

    if (paramName === 'email' || paramName.includes('email')) {
      if (!/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(value)) {
        return 'Must be a valid email address';
      }
    }

    // Type-based validations
    if (param.type === 'number' || param.type === 'int') {
      if (isNaN(value)) {
        return 'Must be a number';
      }
      if (param.min_value !== undefined && value < param.min_value) {
        return `Must be at least ${param.min_value}`;
      }
      if (param.max_value !== undefined && value > param.max_value) {
        return `Must be at most ${param.max_value}`;
      }
    }

    if (param.type === 'string') {
      if (param.min_length !== undefined && value.length < param.min_length) {
        return `Must be at least ${param.min_length} characters`;
      }
      if (param.max_length !== undefined && value.length > param.max_length) {
        return `Must be at most ${param.max_length} characters`;
      }
    }

    return null;
  };

  // Generate smart placeholder examples based on field name
  const getPlaceholderExample = (param) => {
    if (param.default) return param.default;

    const name = param.name.toLowerCase();

    // Common Azure/GCP patterns
    if (name.includes('name')) {
      if (name.includes('storage')) return 'mystorageacct123';
      if (name.includes('vm') || name.includes('machine')) return 'my-vm-001';
      if (name.includes('resource_group') || name.includes('rg')) return 'rg-myproject-prod';
      if (name.includes('database') || name.includes('db')) return 'mydb-prod';
      if (name.includes('bucket')) return 'my-gcs-bucket-123';
      return 'my-resource-name';
    }

    if (name.includes('project_id')) return 'my-gcp-project-123';
    if (name.includes('subscription')) return '00000000-0000-0000-0000-000000000000';
    if (name.includes('sku') || name.includes('tier')) return 'Standard';
    if (name.includes('size')) return 'Standard_B2s';
    if (name.includes('version')) return '1.0.0';
    if (name.includes('port')) return '443';
    if (name.includes('cpu') || name.includes('cores')) return '2';
    if (name.includes('memory') || name.includes('ram')) return '4096';
    if (name.includes('disk') || name.includes('storage_gb')) return '100';
    if (name.includes('cidr') || name.includes('address_space')) return '10.0.0.0/16';
    if (name.includes('subnet')) return '10.0.1.0/24';
    if (name.includes('ip') && name.includes('address')) return '10.0.0.4';
    if (name.includes('dns')) return 'mydomain.com';
    if (name.includes('email')) return 'admin@example.com';
    if (name.includes('username') || name.includes('admin')) return 'azureadmin';
    if (name.includes('password')) return '••••••••';
    if (name.includes('tag') || name.includes('label')) return 'production';

    return '';
  };

  const handleSubmit = (e) => {
    e.preventDefault();

    // Validate all fields before submission
    const errors = {};
    parameters.forEach(param => {
      const error = validateParameter(param.name, formData[param.name]);
      if (error) {
        errors[param.name] = error;
      }
    });

    if (Object.keys(errors).length > 0) {
      setValidationErrors(errors);
      // Scroll to first error
      const firstErrorField = document.getElementById(Object.keys(errors)[0]);
      if (firstErrorField) {
        firstErrorField.scrollIntoView({ behavior: 'smooth', block: 'center' });
        firstErrorField.focus();
      }
      return;
    }

    onSubmit(formData);
  };

  const renderInput = (param) => {
    const value = formData[param.name] || '';
    const hasError = validationErrors[param.name];
    const inputClasses = `mt-1 block w-full rounded-md shadow-sm sm:text-sm ${hasError
        ? 'border-red-300 focus:ring-red-500 focus:border-red-500'
        : 'border-gray-300 focus:ring-blue-500 focus:border-blue-500'
      }`;

    // Check if we have dynamic options for this parameter
    const hasDynamicOptions = dynamicOptions[param.name] && dynamicOptions[param.name].length > 0;
    const isLoadingDynamicOptions = loadingOptions[param.name];

    // Priority 1: Dynamic options from API (most accurate)
    if (hasDynamicOptions) {
      const options = dynamicOptions[param.name];
      return (
        <select
          id={param.name}
          value={value}
          onChange={(e) => handleChange(param.name, e.target.value)}
          required={param.required}
          className={inputClasses}
          disabled={isLoadingDynamicOptions}
        >
          <option value="">
            {isLoadingDynamicOptions ? 'Loading options...' : `Select ${param.name}...`}
          </option>
          {options.map(option => {
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

    // Priority 2: Static allowed_values from template
    if (param.allowed_values && param.allowed_values.length > 0) {
      return (
        <select
          id={param.name}
          value={value}
          onChange={(e) => handleChange(param.name, e.target.value)}
          required={param.required}
          className={inputClasses}
        >
          <option value="">Select {param.name}...</option>
          {param.allowed_values.map(option => (
            <option key={option} value={option}>{option}</option>
          ))}
        </select>
      );
    }

    // Type-based rendering
    switch (param.type) {
      case 'bool':
      case 'boolean':
        return (
          <div className="flex items-center mt-1">
            <input
              type="checkbox"
              id={param.name}
              checked={value === true || value === 'true'}
              onChange={(e) => handleChange(param.name, e.target.checked)}
              className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
            />
            <label htmlFor={param.name} className="ml-2 text-sm text-gray-700">
              {param.description}
            </label>
          </div>
        );

      case 'number':
      case 'int':
        return (
          <input
            type="number"
            id={param.name}
            value={value}
            onChange={(e) => handleChange(param.name, parseInt(e.target.value) || 0)}
            required={param.required}
            className={inputClasses}
            placeholder={getPlaceholderExample(param)}
          />
        );

      case 'array':
      case 'list':
        return (
          <textarea
            id={param.name}
            value={Array.isArray(value) ? value.join('\n') : value}
            onChange={(e) => handleChange(param.name, e.target.value.split('\n').filter(Boolean))}
            required={param.required}
            rows={3}
            className={inputClasses}
            placeholder="Enter one item per line"
          />
        );

      case 'object':
      case 'map':
        return (
          <textarea
            id={param.name}
            value={typeof value === 'object' ? JSON.stringify(value, null, 2) : value}
            onChange={(e) => {
              try {
                const parsed = JSON.parse(e.target.value);
                handleChange(param.name, parsed);
              } catch {
                handleChange(param.name, e.target.value);
              }
            }}
            required={param.required}
            rows={4}
            className={`${inputClasses} font-mono text-xs`}
            placeholder="{}"
          />
        );

      case 'string':
      default:
        // Check if there's a validation pattern suggesting password/secret
        const isSecret = param.name.toLowerCase().includes('password') ||
          param.name.toLowerCase().includes('secret') ||
          param.name.toLowerCase().includes('key');

        return (
          <input
            type={isSecret ? 'password' : 'text'}
            id={param.name}
            value={value}
            onChange={(e) => handleChange(param.name, e.target.value)}
            required={param.required}
            className={inputClasses}
            placeholder={getPlaceholderExample(param)}
          />
        );
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-gray-200 border-t-blue-600"></div>
          <p className="mt-2 text-sm text-gray-600">Loading form...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-md bg-red-50 p-4">
        <p className="text-sm text-red-800">{error}</p>
      </div>
    );
  }

  // Group parameters by category
  const coreParams = parameters.filter(p =>
    ['subscription_id', 'project_id', 'location', 'region', 'resource_group_name'].includes(p.name)
  );

  const requiredParams = parameters.filter(p =>
    p.required && !coreParams.some(cp => cp.name === p.name)
  );

  const optionalParams = parameters.filter(p =>
    !p.required && !coreParams.some(cp => cp.name === p.name)
  );

  return (
    <form onSubmit={handleSubmit} className="space-y-8">
      {/* Core Configuration */}
      {coreParams.length > 0 && (
        <div>
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Core Configuration</h3>
          <div className="space-y-4">
            {coreParams.map(param => (
              <div key={param.name}>
                <label htmlFor={param.name} className="block text-sm font-medium text-gray-700">
                  {param.name.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')}
                  {param.required && <span className="text-red-500 ml-1">*</span>}
                </label>
                {renderInput(param)}
                {validationErrors[param.name] && (
                  <p className="mt-1 text-sm text-red-600 flex items-center">
                    <svg className="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                    </svg>
                    {validationErrors[param.name]}
                  </p>
                )}
                {!validationErrors[param.name] && param.description && param.type !== 'bool' && (
                  <p className="mt-1 text-sm text-gray-500">{param.description}</p>
                )}
                {!validationErrors[param.name] && param.validation_message && (
                  <p className="mt-1 text-xs text-gray-400">{param.validation_message}</p>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Required Parameters */}
      {requiredParams.length > 0 && (
        <div>
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Required Parameters</h3>
          <div className="space-y-4">
            {requiredParams.map(param => (
              <div key={param.name}>
                <label htmlFor={param.name} className="block text-sm font-medium text-gray-700">
                  {param.name.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')}
                  <span className="text-red-500 ml-1">*</span>
                </label>
                {renderInput(param)}
                {validationErrors[param.name] && (
                  <p className="mt-1 text-sm text-red-600 flex items-center">
                    <svg className="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                    </svg>
                    {validationErrors[param.name]}
                  </p>
                )}
                {!validationErrors[param.name] && param.description && param.type !== 'bool' && (
                  <p className="mt-1 text-sm text-gray-500">{param.description}</p>
                )}
                {!validationErrors[param.name] && param.validation_message && (
                  <p className="mt-1 text-xs text-gray-400">{param.validation_message}</p>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Optional Parameters */}
      {optionalParams.length > 0 && (
        <details className="border border-gray-200 rounded-lg">
          <summary className="px-4 py-3 cursor-pointer hover:bg-gray-50 rounded-lg">
            <span className="text-sm font-medium text-gray-700">
              Optional Parameters ({optionalParams.length})
            </span>
          </summary>
          <div className="px-4 pb-4 space-y-4 mt-2">
            {optionalParams.map(param => (
              <div key={param.name}>
                <label htmlFor={param.name} className="block text-sm font-medium text-gray-700">
                  {param.name.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')}
                </label>
                {renderInput(param)}
                {validationErrors[param.name] && (
                  <p className="mt-1 text-sm text-red-600 flex items-center">
                    <svg className="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                    </svg>
                    {validationErrors[param.name]}
                  </p>
                )}
                {!validationErrors[param.name] && param.description && param.type !== 'bool' && (
                  <p className="mt-1 text-sm text-gray-500">{param.description}</p>
                )}
                {!validationErrors[param.name] && param.validation_message && (
                  <p className="mt-1 text-xs text-gray-400">{param.validation_message}</p>
                )}
              </div>
            ))}
          </div>
        </details>
      )}

      {/* Action Buttons */}
      <div className="flex justify-end space-x-3 pt-4 border-t">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          Cancel
        </button>
        <button
          type="submit"
          className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          Deploy
        </button>
      </div>
    </form>
  );
}

export default DynamicForm;
