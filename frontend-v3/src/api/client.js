import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

// Create axios instance with default config
const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Add interceptor to inject token if available
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('auth_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
}, (error) => {
  return Promise.reject(error);
});

// Add interceptor to handle auth errors (401)
api.interceptors.response.use((response) => {
  return response;
}, (error) => {
  if (error.response && error.response.status === 401) {
    // Optional: Redirect to login or clear storage
    // window.location.href = '/login';
    // Don't force redirect here as it might interfere with login page itself
  }
  return Promise.reject(error);
});

// ============================================================================
// Auth API
// ============================================================================
export const authAPI = {
  login: (email, password) => api.post('/auth/login', { email, password }),
  register: (data) => api.post('/auth/register', data),
  getCurrentUser: () => api.get('/auth/me'),
  updateUser: (email, data) => api.put(`/auth/users/${email}`, data),
  listUsers: () => api.get('/auth/users'),
  deleteUser: (email) => api.delete(`/auth/users/${email}`),
};

// ============================================================================
// Deployment API
// ============================================================================
export const deploymentAPI = {
  // Get all deployments with optional filters
  getAll: (params) => api.get('/deployments', { params }),

  // Get deployment by ID
  getById: (id) => api.get(`/deployments/${id}`),

  // Get deployment status
  getStatus: (id) => api.get(`/deployments/${id}/status`),

  // Get task status (includes phase information)
  getTaskStatus: (taskId) => api.get(`/tasks/${taskId}/status`),

  // Stream deployment logs (URL for EventSource)
  getLogsStreamUrl: (id) => `${API_BASE_URL}/deployments/${id}/logs`,

  // Create new deployment
  create: (data) => api.post('/deploy', data),

  // Delete deployment record
  delete: (id) => api.delete(`/deployments/${id}`),

  // Update deployment tags
  updateTags: (id, tags) => api.put(`/deployments/${id}/tags`, tags),

  // Get all available tags
  getAllTags: () => api.get('/deployments/tags'),
};

// ============================================================================
// Template API
// ============================================================================
export const templateAPI = {
  // Get templates (filtered by cloud/provider)
  // Fixed: backend expects query param 'cloud' or 'provider_type', not path param
  getTemplates: (cloud) => api.get('/templates', { params: { cloud } }),

  // Get specific template details
  getTemplate: (providerType, templateName) => 
    api.get(`/templates/${providerType}/${templateName}`),

  // Get template parameters
  getParameters: (providerType, templateName) => 
    api.get(`/templates/${providerType}/${templateName}/parameters`),
    
  // Get template metadata
  getMetadata: (providerType, templateName) =>
    api.get(`/templates/${providerType}/${templateName}/metadata`),
};

// ============================================================================
// Cloud Options API (Dynamic Options)
// ============================================================================
export const cloudAPI = {
  // Azure
  getAzureVMSizes: (location) => api.get('/api/azure/vm-sizes', { params: { location } }),
  getAzureLocations: () => api.get('/api/azure/locations'),
  getAzureResourceGroups: () => api.get('/api/azure/resource-groups'),

  // GCP
  getGCPMachineTypes: (zone, region) => api.get('/api/gcp/machine-types', { params: { zone, region } }),
  getGCPZones: (region) => api.get('/api/gcp/zones', { params: { region } }),
  getGCPRegions: () => api.get('/api/gcp/regions'),
  getGCPProjects: () => api.get('/api/gcp/projects'),
};

// Helper for DynamicForm to fetch options generically
export const getDynamicOptions = async (provider, paramName, context = {}) => {
  const providerLower = provider.toLowerCase();

  try {
    // Azure Options
    if (providerLower.includes('azure')) {
      if (paramName === 'vm_size') {
        const location = context.location || 'eastus';
        const res = await cloudAPI.getAzureVMSizes(location);
        return res.data.success ? res.data.data.vm_sizes : [];
      }
      if (paramName === 'location' || paramName === 'region') {
        const res = await cloudAPI.getAzureLocations();
        return res.data.success ? res.data.data.locations : [];
      }
      if (paramName === 'resource_group' || paramName === 'resource_group_name') {
        const res = await cloudAPI.getAzureResourceGroups();
        if (res.data.success) {
          // Return resource groups with a special format that allows creating new
          const rgs = res.data.data.resource_groups.map(rg => ({
            name: rg.name,
            display_name: rg.name,
            description: rg.location || 'Existing resource group'
          }));
          // Add option to create new at the beginning
          return [
            { name: '__create_new__', display_name: '+ Create New Resource Group', description: 'Will be created automatically' },
            ...rgs
          ];
        }
        return [];
      }
    }

    // GCP Options
    if (providerLower.includes('gcp')) {
      if (paramName === 'machine_type') {
        const res = await cloudAPI.getGCPMachineTypes(context.zone, context.region);
        return res.data.success ? res.data.data.machine_types : [];
      }
      if (paramName === 'zone') {
        const res = await cloudAPI.getGCPZones(context.region);
        return res.data.success ? res.data.data.zones : [];
      }
      if (paramName === 'region') {
        const res = await cloudAPI.getGCPRegions();
        return res.data.success ? res.data.data.regions : [];
      }
      if (paramName === 'project_id') {
        const res = await cloudAPI.getGCPProjects();
        if (res.data.success) {
          return res.data.data.projects.map(p => ({
            name: p.project_id,
            display_name: p.name || p.project_id,
            description: p.state || 'GCP Project'
          }));
        }
        return [];
      }
    }
  } catch (error) {
    console.error(`Error fetching dynamic options for ${paramName}:`, error);
    // Fallback/Empty on error
    return [];
  }

  return null;
};

// ============================================================================
// Resource Group API
// ============================================================================
export const resourceGroupAPI = {
  list: (providerType, subscriptionId) => 
    api.get('/resource-groups', { params: { provider_type: providerType, subscription_id: subscriptionId } }),
    
  create: (data) => api.post('/resource-groups', data),
  
  delete: (name, providerType, subscriptionId) => 
    api.delete(`/resource-groups/${name}`, { params: { provider_type: providerType, subscription_id: subscriptionId } }),
    
  listResources: (groupName, providerType, subscriptionId) =>
    api.get(`/resource-groups/${groupName}/resources`, { params: { provider_type: providerType, subscription_id: subscriptionId } }),
};

export default api;