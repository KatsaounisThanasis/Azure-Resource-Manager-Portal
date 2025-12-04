import { useState, useEffect } from 'react';
import { useToast } from '../contexts/ToastContext';
import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

function Settings() {
  const { addToast } = useToast();
  // Azure Settings
  const [azureMode, setAzureMode] = useState('env'); // 'env' or 'custom'
  const [azureSubscriptionId, setAzureSubscriptionId] = useState('');
  const [azureTenantId, setAzureTenantId] = useState('');
  const [azureClientId, setAzureClientId] = useState('');
  const [azureClientSecret, setAzureClientSecret] = useState('');

  // GCP Settings
  const [gcpMode, setGcpMode] = useState('env'); // 'env' or 'custom'
  const [gcpProjectId, setGcpProjectId] = useState('');
  const [gcpRegion, setGcpRegion] = useState('');

  const [saveStatus, setSaveStatus] = useState(null); // 'success' or 'error'
  const [saveMessage, setSaveMessage] = useState('');

  // Load settings from localStorage on mount
  useEffect(() => {
    const savedSettings = localStorage.getItem('cloudCredentials');
    if (savedSettings) {
      try {
        const parsed = JSON.parse(savedSettings);

        // Azure
        if (parsed.azure) {
          setAzureMode(parsed.azure.mode || 'env');
          if (parsed.azure.mode === 'custom') {
            setAzureSubscriptionId(parsed.azure.subscriptionId || '');
            setAzureTenantId(parsed.azure.tenantId || '');
            setAzureClientId(parsed.azure.clientId || '');
            // Don't load secret from localStorage for security
          }
        }

        // GCP
        if (parsed.gcp) {
          setGcpMode(parsed.gcp.mode || 'env');
          if (parsed.gcp.mode === 'custom') {
            setGcpProjectId(parsed.gcp.projectId || '');
            setGcpRegion(parsed.gcp.region || '');
          }
        }
      } catch (err) {
        console.error('Failed to load saved settings:', err);
      }
    }
  }, []);

  const handleSave = () => {
    const settings = {
      azure: {
        mode: azureMode,
        ...(azureMode === 'custom' && {
          subscriptionId: azureSubscriptionId,
          tenantId: azureTenantId,
          clientId: azureClientId,
          clientSecret: azureClientSecret
        })
      },
      gcp: {
        mode: gcpMode,
        ...(gcpMode === 'custom' && {
          projectId: gcpProjectId,
          region: gcpRegion
        })
      }
    };

    // Save to localStorage (excluding secrets)
    const settingsForStorage = {
      azure: {
        mode: azureMode,
        ...(azureMode === 'custom' && {
          subscriptionId: azureSubscriptionId,
          tenantId: azureTenantId,
          clientId: azureClientId
          // Don't save clientSecret to localStorage
        })
      },
      gcp: {
        mode: gcpMode,
        ...(gcpMode === 'custom' && {
          projectId: gcpProjectId,
          region: gcpRegion
        })
      }
    };

    localStorage.setItem('cloudCredentials', JSON.stringify(settingsForStorage));

    // Also save to sessionStorage for current session (including secrets)
    sessionStorage.setItem('cloudCredentials', JSON.stringify(settings));

    setSaveStatus('success');
    setSaveMessage('Settings saved successfully! These will be used for your deployments.');

    // Show success toast
    addToast('Settings saved successfully!', 'success', 4000);

    setTimeout(() => {
      setSaveStatus(null);
      setSaveMessage('');
    }, 3000);
  };

  const handleReset = () => {
    setAzureMode('env');
    setAzureSubscriptionId('');
    setAzureTenantId('');
    setAzureClientId('');
    setAzureClientSecret('');

    setGcpMode('env');
    setGcpProjectId('');
    setGcpRegion('');

    localStorage.removeItem('cloudCredentials');
    sessionStorage.removeItem('cloudCredentials');

    setSaveStatus('success');
    setSaveMessage('Settings reset! Using default environment credentials.');

    // Show info toast
    addToast('Settings reset! Using default credentials.', 'info', 4000);

    setTimeout(() => {
      setSaveStatus(null);
      setSaveMessage('');
    }, 3000);
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900">Cloud Provider Settings</h1>
          <p className="mt-2 text-sm text-gray-600">
            Configure your cloud provider credentials. By default, credentials from the .env file are used.
          </p>
        </div>

        {/* Save Status Message */}
        {saveStatus && (
          <div className={`mb-6 rounded-lg p-4 ${
            saveStatus === 'success' ? 'bg-green-50 border border-green-200' : 'bg-red-50 border border-red-200'
          }`}>
            <div className="flex">
              <div className="flex-shrink-0">
                {saveStatus === 'success' ? (
                  <svg className="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                  </svg>
                ) : (
                  <svg className="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
                  </svg>
                )}
              </div>
              <div className="ml-3">
                <p className={`text-sm font-medium ${
                  saveStatus === 'success' ? 'text-green-800' : 'text-red-800'
                }`}>
                  {saveMessage}
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Azure Settings Card */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6">
          <div className="flex items-center mb-6">
            <span className="text-3xl mr-3">☁️</span>
            <div>
              <h2 className="text-xl font-bold text-gray-900">Microsoft Azure</h2>
              <p className="text-sm text-gray-600">Configure your Azure subscription and credentials</p>
            </div>
          </div>

          {/* Mode Selection */}
          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-700 mb-3">Credentials Source</label>
            <div className="space-y-3">
              <label className="flex items-start p-4 border-2 rounded-lg cursor-pointer transition-all hover:bg-gray-50"
                style={{ borderColor: azureMode === 'env' ? '#3B82F6' : '#E5E7EB' }}>
                <input
                  type="radio"
                  name="azureMode"
                  value="env"
                  checked={azureMode === 'env'}
                  onChange={(e) => setAzureMode(e.target.value)}
                  className="mt-1 h-4 w-4 text-blue-600 focus:ring-blue-500"
                />
                <div className="ml-3">
                  <div className="text-sm font-medium text-gray-900">Use Environment (.env file)</div>
                  <div className="text-xs text-gray-600 mt-1">
                    Automatically use AZURE_SUBSCRIPTION_ID and other credentials from the server's .env file.
                    Recommended for development and single-tenant scenarios.
                  </div>
                </div>
              </label>

              <label className="flex items-start p-4 border-2 rounded-lg cursor-pointer transition-all hover:bg-gray-50"
                style={{ borderColor: azureMode === 'custom' ? '#3B82F6' : '#E5E7EB' }}>
                <input
                  type="radio"
                  name="azureMode"
                  value="custom"
                  checked={azureMode === 'custom'}
                  onChange={(e) => setAzureMode(e.target.value)}
                  className="mt-1 h-4 w-4 text-blue-600 focus:ring-blue-500"
                />
                <div className="ml-3">
                  <div className="text-sm font-medium text-gray-900">Custom Credentials</div>
                  <div className="text-xs text-gray-600 mt-1">
                    Provide your own Azure subscription and service principal credentials.
                    Use this for multi-tenant or when you need different credentials than the .env file.
                  </div>
                </div>
              </label>
            </div>
          </div>

          {/* Custom Azure Fields */}
          {azureMode === 'custom' && (
            <div className="space-y-4 pl-7 border-l-4 border-blue-200">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Subscription ID <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={azureSubscriptionId}
                  onChange={(e) => setAzureSubscriptionId(e.target.value)}
                  placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Tenant ID <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={azureTenantId}
                  onChange={(e) => setAzureTenantId(e.target.value)}
                  placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Client ID (Application ID) <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={azureClientId}
                  onChange={(e) => setAzureClientId(e.target.value)}
                  placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Client Secret <span className="text-red-500">*</span>
                </label>
                <input
                  type="password"
                  value={azureClientSecret}
                  onChange={(e) => setAzureClientSecret(e.target.value)}
                  placeholder="Enter client secret"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                />
                <p className="mt-1 text-xs text-gray-500">
                  ⚠️ Stored in browser session only (not persisted to disk)
                </p>
              </div>
            </div>
          )}
        </div>

        {/* GCP Settings Card */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6">
          <div className="flex items-center mb-6">
            <span className="text-3xl mr-3">🌩️</span>
            <div>
              <h2 className="text-xl font-bold text-gray-900">Google Cloud Platform</h2>
              <p className="text-sm text-gray-600">Configure your GCP project and credentials</p>
            </div>
          </div>

          {/* Mode Selection */}
          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-700 mb-3">Credentials Source</label>
            <div className="space-y-3">
              <label className="flex items-start p-4 border-2 rounded-lg cursor-pointer transition-all hover:bg-gray-50"
                style={{ borderColor: gcpMode === 'env' ? '#10B981' : '#E5E7EB' }}>
                <input
                  type="radio"
                  name="gcpMode"
                  value="env"
                  checked={gcpMode === 'env'}
                  onChange={(e) => setGcpMode(e.target.value)}
                  className="mt-1 h-4 w-4 text-green-600 focus:ring-green-500"
                />
                <div className="ml-3">
                  <div className="text-sm font-medium text-gray-900">Use Environment (.env file)</div>
                  <div className="text-xs text-gray-600 mt-1">
                    Automatically use GOOGLE_PROJECT_ID from the server's .env file.
                    Recommended for development and single-project scenarios.
                  </div>
                </div>
              </label>

              <label className="flex items-start p-4 border-2 rounded-lg cursor-pointer transition-all hover:bg-gray-50"
                style={{ borderColor: gcpMode === 'custom' ? '#10B981' : '#E5E7EB' }}>
                <input
                  type="radio"
                  name="gcpMode"
                  value="custom"
                  checked={gcpMode === 'custom'}
                  onChange={(e) => setGcpMode(e.target.value)}
                  className="mt-1 h-4 w-4 text-green-600 focus:ring-green-500"
                />
                <div className="ml-3">
                  <div className="text-sm font-medium text-gray-900">Custom Credentials</div>
                  <div className="text-xs text-gray-600 mt-1">
                    Provide your own GCP project ID. Use this for multi-project scenarios.
                  </div>
                </div>
              </label>
            </div>
          </div>

          {/* Custom GCP Fields */}
          {gcpMode === 'custom' && (
            <div className="space-y-4 pl-7 border-l-4 border-green-200">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Project ID <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={gcpProjectId}
                  onChange={(e) => setGcpProjectId(e.target.value)}
                  placeholder="my-gcp-project-id"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-green-500 focus:border-green-500"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Default Region
                </label>
                <input
                  type="text"
                  value={gcpRegion}
                  onChange={(e) => setGcpRegion(e.target.value)}
                  placeholder="us-central1"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-green-500 focus:border-green-500"
                />
                <p className="mt-1 text-xs text-gray-500">Optional - can be overridden per deployment</p>
              </div>
            </div>
          )}
        </div>

        {/* Action Buttons */}
        <div className="flex justify-between items-center">
          <button
            onClick={handleReset}
            className="px-6 py-3 bg-gray-100 text-gray-700 font-semibold rounded-lg hover:bg-gray-200 transition-all"
          >
            Reset to Defaults
          </button>

          <button
            onClick={handleSave}
            className="px-8 py-3 bg-gradient-to-r from-blue-600 to-purple-600 text-white font-bold rounded-lg hover:from-blue-700 hover:to-purple-700 shadow-lg hover:shadow-xl transition-all"
          >
            Save Settings
          </button>
        </div>

        {/* Info Box */}
        <div className="mt-8 bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <svg className="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-blue-800">Security Notice</h3>
              <div className="mt-2 text-sm text-blue-700">
                <ul className="list-disc list-inside space-y-1">
                  <li>Custom credentials are stored in your browser's localStorage/sessionStorage</li>
                  <li>Secrets (like client secret) are only stored for the current session</li>
                  <li>For production use, consider using environment variables or a secure secrets manager</li>
                  <li>These settings apply to deployments made from this browser only</li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default Settings;
