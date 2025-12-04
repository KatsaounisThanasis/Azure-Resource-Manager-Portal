import { useState, useEffect } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { deploymentAPI } from '../api/client';
import Tooltip from '../components/Tooltip';
import { SkeletonCard } from '../components/Skeleton';
import EmptyState from '../components/EmptyState';

function Dashboard() {
  const [searchParams] = useSearchParams();
  const [deployments, setDeployments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [searchTerm, setSearchTerm] = useState(searchParams.get('search') || '');
  const [statusFilter, setStatusFilter] = useState('all');
  const [providerFilter, setProviderFilter] = useState('all');

  // Format template name - remove dashes and capitalize
  const formatTemplateName = (name) => {
    if (!name) return name;
    return name
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  };

  const fetchDeployments = async () => {
    try {
      const response = await deploymentAPI.getAll();
      setDeployments(response.data.data.deployments || []);
      setError(null);
    } catch (err) {
      setError(err.message || 'Failed to fetch deployments');
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteDeployment = async (deploymentId) => {
    if (!confirm(`Are you sure you want to delete deployment ${deploymentId}?`)) {
      return;
    }

    try {
      await deploymentAPI.delete(deploymentId);
      // Remove from local state
      setDeployments(prev => prev.filter(d => d.deployment_id !== deploymentId));
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to delete deployment');
    }
  };

  useEffect(() => {
    fetchDeployments();
    const interval = setInterval(fetchDeployments, 5000);
    return () => clearInterval(interval);
  }, []);

  const getStatusColor = (status) => {
    const statusLower = status?.toLowerCase();
    switch (statusLower) {
      case 'completed':
        return 'bg-green-100 text-green-800 border-green-200';
      case 'pending':
        return 'bg-yellow-100 text-yellow-800 border-yellow-200';
      case 'running':
        return 'bg-blue-100 text-blue-800 border-blue-200';
      case 'failed':
        return 'bg-red-100 text-red-800 border-red-200';
      default:
        return 'bg-gray-100 text-gray-800 border-gray-200';
    }
  };

  const getProviderIcon = (provider) => {
    if (provider === 'azure' || provider === 'bicep') return '☁️';
    if (provider === 'gcp' || provider?.includes('terraform-gcp')) return '🌐';
    if (provider?.includes('terraform')) return '🔧';
    return '☁️';
  };

  // Format provider type for display - hide backend implementation details
  const formatProviderType = (providerType) => {
    if (!providerType) return 'Unknown';
    // Map all Azure variants to just "Azure"
    if (providerType === 'bicep' || providerType === 'terraform-azure' || providerType === 'azure') {
      return 'Azure';
    }
    // Map all GCP variants to just "Google Cloud"
    if (providerType === 'terraform-gcp' || providerType === 'gcp') {
      return 'Google Cloud';
    }
    return providerType;
  };

  // Calculate stats
  const stats = {
    total: deployments.length,
    completed: deployments.filter(d => d.status?.toLowerCase() === 'completed').length,
    running: deployments.filter(d => d.status?.toLowerCase() === 'running').length,
    failed: deployments.filter(d => d.status?.toLowerCase() === 'failed').length,
    pending: deployments.filter(d => d.status?.toLowerCase() === 'pending').length,
  };

  const successRate = stats.total > 0
    ? ((stats.completed / stats.total) * 100).toFixed(1)
    : 0;

  // Filter deployments
  const filteredDeployments = deployments.filter(deployment => {
    const matchesSearch = deployment.deployment_id?.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         deployment.template_name?.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesStatus = statusFilter === 'all' || deployment.status?.toLowerCase() === statusFilter;
    const matchesProvider = providerFilter === 'all' || deployment.provider_type === providerFilter;

    return matchesSearch && matchesStatus && matchesProvider;
  });

  // Get unique providers for filter
  const uniqueProviders = [...new Set(deployments.map(d => d.provider_type))];

  if (loading) {
    return (
      <div className="px-4 sm:px-6 lg:px-8 py-8">
        <div className="sm:flex sm:items-center sm:justify-between mb-10">
          <div className="sm:flex-auto">
            <h1 className="text-4xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
              Deployments
            </h1>
            <p className="mt-2 text-base text-gray-600">
              Loading your deployments...
            </p>
          </div>
        </div>

        {/* Stats skeleton */}
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-5 mb-8">
          {[1, 2, 3, 4, 5].map((i) => (
            <div key={i} className="rounded-2xl bg-white p-6 shadow-lg border border-gray-100 animate-pulse">
              <div className="h-4 bg-gray-200 rounded w-1/2 mb-4"></div>
              <div className="h-8 bg-gray-200 rounded w-16"></div>
            </div>
          ))}
        </div>

        {/* Deployment cards skeleton */}
        <div className="space-y-4">
          {[1, 2, 3].map((i) => (
            <SkeletonCard key={i} />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-8">
      {/* Header with gradient */}
      <div className="sm:flex sm:items-center sm:justify-between">
        <div className="sm:flex-auto">
          <h1 className="text-4xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
            Deployments
          </h1>
          <p className="mt-2 text-base text-gray-600">
            Manage and monitor your multi-cloud infrastructure deployments
          </p>
        </div>
        <div className="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
          <Link
            to="/deploy"
            className="inline-flex items-center justify-center rounded-xl bg-gradient-to-r from-blue-600 to-blue-700 px-6 py-3 text-sm font-semibold text-white shadow-lg hover:shadow-xl hover:scale-105 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200"
          >
            <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
            New Deployment
          </Link>
        </div>
      </div>

      {error && (
        <div className="mt-6 rounded-xl bg-gradient-to-r from-red-50 to-red-100 border border-red-300 p-4 shadow-md">
          <div className="flex items-center">
            <svg className="w-5 h-5 text-red-600 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <p className="text-sm text-red-800 font-medium">{error}</p>
          </div>
        </div>
      )}

      {/* Stats Overview - Modern Cards with Gradients */}
      <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-5">
        {/* Total Card */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-slate-500 to-slate-700 p-6 shadow-xl hover:shadow-2xl transition-all duration-300 hover:scale-105">
          <div className="absolute top-0 right-0 -mt-4 -mr-4 h-24 w-24 rounded-full bg-white opacity-10"></div>
          <div className="relative">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-slate-200">Total</p>
                <p className="mt-2 text-3xl font-bold text-white">{stats.total}</p>
              </div>
              <div className="rounded-xl bg-white bg-opacity-20 p-3 backdrop-blur-sm">
                <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
              </div>
            </div>
          </div>
        </div>

        {/* Completed Card */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-emerald-500 to-green-700 p-6 shadow-xl hover:shadow-2xl transition-all duration-300 hover:scale-105">
          <div className="absolute top-0 right-0 -mt-4 -mr-4 h-24 w-24 rounded-full bg-white opacity-10"></div>
          <div className="relative">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-emerald-100">Completed</p>
                <p className="mt-2 text-3xl font-bold text-white">{stats.completed}</p>
              </div>
              <div className="rounded-xl bg-white bg-opacity-20 p-3 backdrop-blur-sm">
                <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
            </div>
          </div>
        </div>

        {/* Running Card with Pulse */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-blue-500 to-indigo-700 p-6 shadow-xl hover:shadow-2xl transition-all duration-300 hover:scale-105">
          <div className="absolute top-0 right-0 -mt-4 -mr-4 h-24 w-24 rounded-full bg-white opacity-10"></div>
          {stats.running > 0 && (
            <div className="absolute top-2 right-2">
              <span className="relative flex h-3 w-3">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-white opacity-75"></span>
                <span className="relative inline-flex rounded-full h-3 w-3 bg-white"></span>
              </span>
            </div>
          )}
          <div className="relative">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-blue-100">Running</p>
                <p className="mt-2 text-3xl font-bold text-white">{stats.running}</p>
              </div>
              <div className="rounded-xl bg-white bg-opacity-20 p-3 backdrop-blur-sm">
                <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              </div>
            </div>
          </div>
        </div>

        {/* Failed Card */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-rose-500 to-red-700 p-6 shadow-xl hover:shadow-2xl transition-all duration-300 hover:scale-105">
          <div className="absolute top-0 right-0 -mt-4 -mr-4 h-24 w-24 rounded-full bg-white opacity-10"></div>
          <div className="relative">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-rose-100">Failed</p>
                <p className="mt-2 text-3xl font-bold text-white">{stats.failed}</p>
              </div>
              <div className="rounded-xl bg-white bg-opacity-20 p-3 backdrop-blur-sm">
                <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
            </div>
          </div>
        </div>

        {/* Success Rate Card */}
        <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-violet-500 to-purple-700 p-6 shadow-xl hover:shadow-2xl transition-all duration-300 hover:scale-105">
          <div className="absolute top-0 right-0 -mt-4 -mr-4 h-24 w-24 rounded-full bg-white opacity-10"></div>
          <div className="relative">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-violet-100">Success Rate</p>
                <p className="mt-2 text-3xl font-bold text-white">{successRate}%</p>
              </div>
              <div className="rounded-xl bg-white bg-opacity-20 p-3 backdrop-blur-sm">
                <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
                </svg>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Filters - Modern Glass Morphism */}
      <div className="mt-10 bg-white/80 backdrop-blur-xl p-6 rounded-2xl shadow-xl border border-gray-200">
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-3">
          <div>
            <label htmlFor="search" className="block text-sm font-semibold text-gray-700 mb-2">
              Search
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <svg className="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </div>
              <input
                type="text"
                id="search"
                placeholder="Search by ID or template..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="block w-full pl-10 pr-3 py-3 border border-gray-300 rounded-xl text-sm placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
              />
            </div>
          </div>

          <div>
            <label htmlFor="status" className="block text-sm font-semibold text-gray-700 mb-2">
              Status
            </label>
            <div className="relative">
              <select
                id="status"
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="block w-full px-4 py-3 border border-gray-300 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all appearance-none bg-white"
              >
                <option value="all">All Statuses</option>
                <option value="completed">✓ Completed</option>
                <option value="running">⚡ Running</option>
                <option value="pending">⏳ Pending</option>
                <option value="failed">✗ Failed</option>
              </select>
              <div className="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
                <svg className="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </div>
            </div>
          </div>

          <div>
            <label htmlFor="provider" className="block text-sm font-semibold text-gray-700 mb-2">
              Provider
            </label>
            <div className="relative">
              <select
                id="provider"
                value={providerFilter}
                onChange={(e) => setProviderFilter(e.target.value)}
                className="block w-full px-4 py-3 border border-gray-300 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all appearance-none bg-white"
              >
                <option value="all">All Providers</option>
                {uniqueProviders.map(provider => (
                  <option key={provider} value={provider}>{formatProviderType(provider)}</option>
                ))}
              </select>
              <div className="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
                <svg className="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Deployments Grid */}
      {deployments.length === 0 && !error ? (
        <div className="mt-8 space-y-8">
          {/* Hero Empty State */}
          <div className="text-center bg-gradient-to-br from-blue-50 via-indigo-50 to-purple-50 rounded-2xl shadow-lg p-12 border border-blue-100">
            <div className="mx-auto w-24 h-24 bg-gradient-to-br from-blue-600 to-purple-600 rounded-2xl flex items-center justify-center shadow-lg mb-6 animate-pulse">
              <svg className="w-12 h-12 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 15a4 4 0 004 4h9a5 5 0 10-.1-9.999 5.002 5.002 0 10-9.78 2.096A4.001 4.001 0 003 15z" />
              </svg>
            </div>
            <h3 className="text-3xl font-bold text-gray-900 mb-3">Welcome to Multi-Cloud Manager</h3>
            <p className="text-lg text-gray-600 mb-8 max-w-2xl mx-auto">
              Deploy and manage infrastructure across Azure and Google Cloud Platform with ease.
              Get started by choosing a template below or create a custom deployment.
            </p>
            <div className="flex gap-4 justify-center">
              <Link
                to="/deploy"
                className="inline-flex items-center px-8 py-4 bg-gradient-to-r from-blue-600 to-purple-600 text-white text-base font-bold rounded-xl shadow-lg hover:shadow-2xl hover:scale-105 transition-all duration-200"
              >
                <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                </svg>
                Create Your First Deployment
              </Link>
              <button
                onClick={() => window.open('https://docs.claude.com', '_blank')}
                className="inline-flex items-center px-6 py-4 bg-white text-gray-700 text-base font-semibold rounded-xl border-2 border-gray-300 hover:border-blue-500 hover:text-blue-600 transition-all duration-200"
              >
                <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
                </svg>
                View Documentation
              </button>
            </div>
          </div>

          {/* Popular Starter Templates */}
          <div className="bg-white rounded-2xl shadow-lg border border-gray-200 p-8">
            <div className="mb-6">
              <h4 className="text-2xl font-bold text-gray-900 mb-2">Popular Starter Templates</h4>
              <p className="text-gray-600">Quick-start your infrastructure with these commonly used templates</p>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
              {/* Azure VM */}
              <Link
                to="/deploy"
                className="group bg-gradient-to-br from-blue-50 to-indigo-50 rounded-xl p-6 border-2 border-blue-200 hover:border-blue-500 hover:shadow-xl transition-all duration-200 cursor-pointer"
              >
                <div className="text-4xl mb-4">☁️</div>
                <h5 className="text-lg font-bold text-gray-900 mb-2 group-hover:text-blue-600">Azure Virtual Machine</h5>
                <p className="text-sm text-gray-600 mb-4">Deploy a Windows or Linux VM with networking</p>
                <span className="text-xs font-semibold text-blue-600">Azure • Bicep</span>
              </Link>

              {/* GCP Compute */}
              <Link
                to="/deploy"
                className="group bg-gradient-to-br from-green-50 to-emerald-50 rounded-xl p-6 border-2 border-green-200 hover:border-green-500 hover:shadow-xl transition-all duration-200 cursor-pointer"
              >
                <div className="text-4xl mb-4">🌐</div>
                <h5 className="text-lg font-bold text-gray-900 mb-2 group-hover:text-green-600">GCP Compute Instance</h5>
                <p className="text-sm text-gray-600 mb-4">Create a GCE instance with firewall rules</p>
                <span className="text-xs font-semibold text-green-600">GCP • Terraform</span>
              </Link>

              {/* Azure Storage */}
              <Link
                to="/deploy"
                className="group bg-gradient-to-br from-purple-50 to-pink-50 rounded-xl p-6 border-2 border-purple-200 hover:border-purple-500 hover:shadow-xl transition-all duration-200 cursor-pointer"
              >
                <div className="text-4xl mb-4">💾</div>
                <h5 className="text-lg font-bold text-gray-900 mb-2 group-hover:text-purple-600">Azure Storage Account</h5>
                <p className="text-sm text-gray-600 mb-4">Blob storage with containers and access policies</p>
                <span className="text-xs font-semibold text-purple-600">Azure • Bicep</span>
              </Link>

              {/* GCP Cloud Run */}
              <Link
                to="/deploy"
                className="group bg-gradient-to-br from-orange-50 to-red-50 rounded-xl p-6 border-2 border-orange-200 hover:border-orange-500 hover:shadow-xl transition-all duration-200 cursor-pointer"
              >
                <div className="text-4xl mb-4">🚀</div>
                <h5 className="text-lg font-bold text-gray-900 mb-2 group-hover:text-orange-600">GCP Cloud Run</h5>
                <p className="text-sm text-gray-600 mb-4">Serverless container deployment with autoscaling</p>
                <span className="text-xs font-semibold text-orange-600">GCP • Terraform</span>
              </Link>
            </div>
          </div>

          {/* Quick Tips */}
          <div className="bg-gradient-to-r from-blue-50 to-indigo-50 rounded-xl p-6 border border-blue-200">
            <div className="flex items-start space-x-4">
              <div className="flex-shrink-0">
                <svg className="h-8 w-8 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <div className="flex-1">
                <h5 className="text-lg font-semibold text-gray-900 mb-2">Pro Tips</h5>
                <ul className="space-y-2 text-sm text-gray-700">
                  <li className="flex items-start">
                    <span className="text-blue-600 mr-2">•</span>
                    <span>Press <kbd className="px-2 py-1 bg-white border border-gray-300 rounded text-xs font-mono">?</kbd> to view keyboard shortcuts</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 mr-2">•</span>
                    <span>Use <kbd className="px-2 py-1 bg-white border border-gray-300 rounded text-xs font-mono">/</kbd> to quickly search deployments</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 mr-2">•</span>
                    <span>All deployments are tracked and can be monitored in real-time</span>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div className="mt-10">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-lg font-semibold text-gray-700">
              Showing <span className="text-blue-600">{filteredDeployments.length}</span> of {deployments.length} deployments
            </h2>
          </div>
          {filteredDeployments.length === 0 ? (
            <EmptyState
              icon="search"
              title="No deployments found"
              description={
                searchTerm || statusFilter !== 'all' || providerFilter !== 'all'
                  ? 'Try adjusting your search or filters to find what you\'re looking for.'
                  : 'Get started by creating your first deployment.'
              }
              actionLabel={searchTerm || statusFilter !== 'all' || providerFilter !== 'all' ? null : 'Create Deployment'}
              actionTo={searchTerm || statusFilter !== 'all' || providerFilter !== 'all' ? null : '/deploy'}
            />
          ) : (
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {filteredDeployments.map((deployment) => (
              <div
                key={deployment.deployment_id}
                className="group relative bg-white overflow-hidden rounded-2xl border border-gray-200 hover:border-blue-300 shadow-lg hover:shadow-2xl transition-all duration-300 hover:-translate-y-1"
              >
                {/* Gradient Top Border */}
                <div className={`h-1.5 ${
                  deployment.status?.toLowerCase() === 'completed' ? 'bg-gradient-to-r from-emerald-500 to-green-600' :
                  deployment.status?.toLowerCase() === 'running' ? 'bg-gradient-to-r from-blue-500 to-indigo-600' :
                  deployment.status?.toLowerCase() === 'failed' ? 'bg-gradient-to-r from-rose-500 to-red-600' :
                  'bg-gradient-to-r from-yellow-500 to-orange-600'
                }`}></div>

                <div className="p-6">
                  {/* Status Badge and Provider Icon */}
                  <div className="flex items-center justify-between mb-4">
                    <span
                      className={`inline-flex items-center rounded-full px-3 py-1.5 text-xs font-bold uppercase tracking-wide border-2 ${getStatusColor(
                        deployment.status
                      )}`}
                    >
                      {deployment.status}
                    </span>
                    <div className="flex items-center space-x-2">
                      {deployment.status?.toLowerCase() === 'running' && (
                        <span className="relative flex h-2.5 w-2.5">
                          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
                          <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-blue-500"></span>
                        </span>
                      )}
                      <span className="text-2xl">{getProviderIcon(deployment.provider_type)}</span>
                    </div>
                  </div>

                  {/* Template Name */}
                  <h3 className="text-xl font-bold text-gray-900 mb-3 group-hover:text-blue-600 transition-colors">
                    {formatTemplateName(deployment.template_name)}
                  </h3>

                  {/* Deployment Info */}
                  <div className="space-y-2.5 text-sm mb-5">
                    <div className="flex items-start">
                      <svg className="w-4 h-4 text-gray-400 mr-2 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
                      </svg>
                      <div className="flex-1 min-w-0">
                        <span className="font-medium text-gray-500 text-xs uppercase tracking-wide">ID</span>
                        <p className="font-mono text-xs text-gray-900 truncate">{deployment.deployment_id}</p>
                      </div>
                    </div>
                    <div className="flex items-start">
                      <svg className="w-4 h-4 text-gray-400 mr-2 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 15a4 4 0 004 4h9a5 5 0 10-.1-9.999 5.002 5.002 0 10-9.78 2.096A4.001 4.001 0 003 15z" />
                      </svg>
                      <div className="flex-1 min-w-0">
                        <span className="font-medium text-gray-500 text-xs uppercase tracking-wide">Provider</span>
                        <p className="text-gray-900 truncate">{formatProviderType(deployment.provider_type)}</p>
                      </div>
                    </div>
                    <div className="flex items-start">
                      <svg className="w-4 h-4 text-gray-400 mr-2 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                      <div className="flex-1 min-w-0">
                        <span className="font-medium text-gray-500 text-xs uppercase tracking-wide">Location</span>
                        <p className="text-gray-900 truncate">{deployment.location || 'N/A'}</p>
                      </div>
                    </div>
                    <div className="flex items-start">
                      <svg className="w-4 h-4 text-gray-400 mr-2 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      <div className="flex-1 min-w-0">
                        <span className="font-medium text-gray-500 text-xs uppercase tracking-wide">Created</span>
                        <p className="text-gray-900">{new Date(deployment.created_at).toLocaleString()}</p>
                      </div>
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex gap-3 pt-4 border-t border-gray-100">
                    <Link
                      to={`/deployments/${deployment.deployment_id}`}
                      className="flex-1 inline-flex justify-center items-center px-4 py-2.5 bg-gradient-to-r from-blue-600 to-blue-700 text-white text-sm font-semibold rounded-xl hover:from-blue-700 hover:to-blue-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-all duration-200 shadow-md hover:shadow-lg"
                    >
                      <svg className="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                      </svg>
                      View Details
                    </Link>
                    <Tooltip content="Delete this deployment permanently">
                      <button
                        onClick={() => handleDeleteDeployment(deployment.deployment_id)}
                        className="inline-flex items-center justify-center px-3 py-2.5 bg-red-50 border border-red-200 text-red-600 text-sm font-semibold rounded-xl hover:bg-red-100 hover:border-red-300 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 transition-all duration-200"
                      >
                        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                      </button>
                    </Tooltip>
                  </div>
                </div>
              </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default Dashboard;
