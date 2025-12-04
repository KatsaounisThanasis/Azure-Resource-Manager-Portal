import { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import ServiceCatalog from '../components/ServiceCatalog';
import DeploymentWizard from '../components/DeploymentWizard';
import DeploymentLogStream from '../components/DeploymentLogStream';
import Breadcrumbs from '../components/Breadcrumbs';
import LoadingState from '../components/LoadingState';
import { formatTemplateName, formatProviderName } from '../utils/formatters';
import { useToast } from '../contexts/ToastContext';
import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

function Deploy() {
  const navigate = useNavigate();
  const { provider, template } = useParams();
  const { addToast } = useToast();
  const [selectedTemplate, setSelectedTemplate] = useState(null);
  const [deploying, setDeploying] = useState(false);
  const [deploymentId, setDeploymentId] = useState(null);
  const [error, setError] = useState(null);

  // Handle deep linking
  useEffect(() => {
    if (provider && template && !selectedTemplate) {
      setSelectedTemplate({
        name: template,
        cloud_provider: provider,
        // Description and other fields will be missing but Wizard fetches what it needs
        description: `Deep linked ${provider} ${template} template`
      });
    }
  }, [provider, template]);

  // Clean template description - remove separator lines
  const cleanDescription = (description) => {
    if (!description) return '';
    return description
      .replace(/^[=\-_]+$/gm, '')  // Remove lines with only separators
      .replace(/^\s*$/gm, '')       // Remove empty lines
      .trim();
  };

  // Get current credentials info
  const getCredentialsInfo = () => {
    const savedSettings = sessionStorage.getItem('cloudCredentials') || localStorage.getItem('cloudCredentials');
    if (!savedSettings) return null;

    try {
      const settings = JSON.parse(savedSettings);
      const provider = selectedTemplate?.cloud_provider;

      if (provider === 'azure' && settings.azure?.mode === 'custom') {
        return {
          provider: 'Azure',
          type: 'Custom',
          id: settings.azure.subscriptionId?.substring(0, 8) + '...'
        };
      } else if (provider === 'gcp' && settings.gcp?.mode === 'custom') {
        return {
          provider: 'GCP',
          type: 'Custom',
          id: settings.gcp.projectId
        };
      }
    } catch (err) {
      console.error('Failed to parse credentials info:', err);
    }

    return null;
  };

  const credInfo = getCredentialsInfo();

  const handleSelectTemplate = (template) => {
    setSelectedTemplate(template);
    setError(null);
  };

  const handleBackToCatalog = () => {
    setSelectedTemplate(null);
    setDeploying(false);
    setDeploymentId(null);
    setError(null);
  };

  const handleDeploy = async (formData) => {
    setDeploying(true);
    setError(null);

    try {
      // Map frontend provider names to backend provider types
      const providerTypeMap = {
        'azure': 'terraform-azure',
        'gcp': 'terraform-gcp'
      };
      const providerType = providerTypeMap[selectedTemplate.cloud_provider] || selectedTemplate.cloud_provider;

      // Extract core fields that API expects at top level
      const {
        subscription_id,
        project_id,
        resource_group,
        resource_group_name,
        location,
        region,
        zone,
        ...templateParameters
      } = formData;

      // Map template parameters to API expectations
      // subscription_id/project_id are now auto-populated from .env in backend
      let coreResourceGroup = resource_group || resource_group_name || '';
      const coreLocation = location || region || zone || '';

      // For GCP, resource_group is not typically used but required by API validation
      if (!coreResourceGroup && providerType.includes('gcp')) {
        coreResourceGroup = 'default';
      }

      // Check for custom credentials from settings
      const savedSettings = sessionStorage.getItem('cloudCredentials') || localStorage.getItem('cloudCredentials');
      let customSubscriptionId = null;

      if (savedSettings) {
        try {
          const settings = JSON.parse(savedSettings);

          if (providerType.includes('azure') && settings.azure?.mode === 'custom') {
            customSubscriptionId = settings.azure.subscriptionId;
            console.log('[Deploy] Using custom Azure subscription from settings');
          } else if (providerType.includes('gcp') && settings.gcp?.mode === 'custom') {
            customSubscriptionId = settings.gcp.projectId;
            console.log('[Deploy] Using custom GCP project from settings');
          }
        } catch (err) {
          console.error('[Deploy] Failed to parse saved settings:', err);
        }
      }

      const payload = {
        provider_type: providerType,
        template_name: selectedTemplate.name,
        // Use custom credentials if set, otherwise backend will use env vars
        ...(customSubscriptionId && { subscription_id: customSubscriptionId }),
        resource_group: coreResourceGroup,
        location: coreLocation,
        parameters: templateParameters  // Only template-specific params
      };

      console.log('[Deploy] Sending payload:', payload);

      const response = await axios.post(`${API_BASE_URL}/deploy`, payload);

      if (response.data.success) {
        // Set deployment ID to start log streaming
        const newDeploymentId = response.data.data.deployment_id;
        setDeploymentId(newDeploymentId);

        // Show success toast
        addToast('Deployment created successfully! Starting deployment...', 'success', 4000);
      }
    } catch (err) {
      console.error('[Deploy] Error:', err.response?.data);

      let errorMessage = 'Failed to create deployment';

      // Handle Pydantic validation errors (422)
      if (err.response?.status === 422 && Array.isArray(err.response?.data?.detail)) {
        const validationErrors = err.response.data.detail.map(error => {
          const field = error.loc?.join('.') || 'unknown';
          return `${field}: ${error.msg}`;
        }).join(', ');
        errorMessage = `Validation Error: ${validationErrors}`;
      } else if (err.response?.data?.error) {
        // Handle error object or string
        if (typeof err.response.data.error === 'object') {
          errorMessage = err.response.data.error.message ||
            err.response.data.error.details ||
            JSON.stringify(err.response.data.error);
        } else {
          errorMessage = err.response.data.error;
        }
      } else if (err.response?.data?.message) {
        errorMessage = err.response.data.message;
      } else if (err.response?.data?.detail && typeof err.response.data.detail === 'string') {
        errorMessage = err.response.data.detail;
      } else if (err.message) {
        errorMessage = err.message;
      }

      setError(errorMessage);
      setDeploying(false);

      // Show error toast
      addToast(errorMessage, 'error', 6000);
    }
  };

  const handleDeploymentComplete = (result) => {
    // Navigate to deployment details when complete
    if (result.status === 'completed') {
      // Show success toast
      addToast('Deployment completed successfully!', 'success', 5000);

      setTimeout(() => {
        navigate(`/deployments/${deploymentId}`);
      }, 2000); // Wait 2 seconds to show final logs
    } else if (result.status === 'failed') {
      const errorMsg = result.error || 'Deployment failed';
      setError(errorMsg);
      setDeploying(false);

      // Show error toast
      addToast(errorMsg, 'error', 6000);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Breadcrumbs />

        {/* Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">
                {selectedTemplate ? 'Configure Deployment' : 'New Deployment'}
              </h1>
              <p className="mt-2 text-sm text-gray-600">
                {selectedTemplate
                  ? `Deploy ${formatTemplateName(selectedTemplate.name)} to ${formatProviderName(selectedTemplate.cloud_provider)}`
                  : 'Select a template from the service catalog below'}
              </p>
              {/* Credentials indicator */}
              {credInfo && (
                <div className="mt-3 inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800 border border-blue-200">
                  <svg className="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.121 17.804A13.937 13.937 0 0112 16c2.5 0 4.847.655 6.879 1.804M15 10a3 3 0 11-6 0 3 3 0 016 0zm6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  Using {credInfo.type} {credInfo.provider} credentials ({credInfo.id})
                </div>
              )}
              {!credInfo && selectedTemplate && (
                <div className="mt-3 inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-700 border border-gray-200">
                  <svg className="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                  Using environment credentials from .env
                </div>
              )}
            </div>
            {selectedTemplate && (
              <button
                onClick={handleBackToCatalog}
                className="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                ← Back to Catalog
              </button>
            )}
          </div>
        </div>

        {/* Error Message */}
        {error && (
          <div className="mb-6 rounded-lg bg-red-50 p-4 border border-red-200">
            <div className="flex">
              <div className="flex-shrink-0">
                <svg className="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
                </svg>
              </div>
              <div className="ml-3">
                <h3 className="text-sm font-medium text-red-800">Deployment Error</h3>
                <div className="mt-2 text-sm text-red-700">
                  <p>{error}</p>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Content */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          {!selectedTemplate ? (
            // Service Catalog View
            <ServiceCatalog onSelectTemplate={handleSelectTemplate} />
          ) : (
            // Configuration Form View
            <div className="max-w-4xl mx-auto">
              {/* Template Info Card */}
              <div className="mb-8 bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg p-6 border border-blue-100">
                <div className="flex items-start justify-between">
                  <div>
                    <h3 className="text-xl font-semibold text-gray-900">
                      {formatTemplateName(selectedTemplate.name)}
                    </h3>
                    <div className="mt-2 flex items-center space-x-2 text-sm">
                      <span className="inline-flex items-center px-3 py-1 rounded-full bg-blue-100 text-blue-800 font-medium">
                        <span className="mr-1.5">
                          {selectedTemplate.cloud_provider === 'azure' ? '☁️' : '🌩️'}
                        </span>
                        {selectedTemplate.cloud_provider === 'azure' ? 'Microsoft Azure' : 'Google Cloud'}
                      </span>
                    </div>
                    {selectedTemplate.description && cleanDescription(selectedTemplate.description) && (
                      <p className="mt-2 text-sm text-gray-700">
                        {cleanDescription(selectedTemplate.description)}
                      </p>
                    )}
                  </div>
                </div>
              </div>

              {/* Deployment Wizard or Log Stream */}
              {deploying && deploymentId ? (
                <div>
                  <DeploymentLogStream
                    deploymentId={deploymentId}
                    onComplete={handleDeploymentComplete}
                  />
                  <div className="mt-4 flex justify-center">
                    <button
                      onClick={handleBackToCatalog}
                      className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-all"
                    >
                      Back to Catalog
                    </button>
                  </div>
                </div>
              ) : deploying ? (
                <LoadingState
                  message="Creating Deployment..."
                  subMessage="This may take a few moments"
                />
              ) : (
                <DeploymentWizard
                  provider={selectedTemplate.cloud_provider}
                  template={selectedTemplate}
                  onDeploy={handleDeploy}
                  onCancel={handleBackToCatalog}
                />
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default Deploy;
