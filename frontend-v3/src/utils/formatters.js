/**
 * Formatting utilities for consistent UI presentation
 */

// Acronyms that should be uppercase
const ACRONYMS = new Set([
  'API', 'AKS', 'ACR', 'VM', 'VPN', 'DNS', 'CDN', 'SQL', 'NSG',
  'GCP', 'GKE', 'IP', 'ID', 'URL', 'HTTP', 'HTTPS', 'SSL', 'TLS',
  'OS', 'CPU', 'RAM', 'SSD', 'HDD', 'VPC', 'IAM', 'SDK'
]);

// Special cases for proper formatting
const SPECIAL_CASES = {
  'db': 'DB',
  'postgresql': 'PostgreSQL',
  'mysql': 'MySQL',
  'mongodb': 'MongoDB',
  'redis': 'Redis',
  'cosmos': 'Cosmos',
  'bigquery': 'BigQuery',
  'pubsub': 'Pub/Sub',
  'oauth': 'OAuth',
  'json': 'JSON',
  'xml': 'XML',
  'yaml': 'YAML'
};

/**
 * Format template name for display
 * Handles acronyms, special cases, and proper capitalization
 *
 * @param {string} name - Template name (e.g., "storage-account", "aks-cluster")
 * @returns {string} - Formatted display name (e.g., "Storage Account", "AKS Cluster")
 */
export function formatTemplateName(name) {
  if (!name) return '';

  return name
    .split('-')
    .map(word => {
      const lower = word.toLowerCase();
      const upper = word.toUpperCase();

      // Check if it's an acronym
      if (ACRONYMS.has(upper)) {
        return upper;
      }

      // Check special cases
      if (SPECIAL_CASES[lower]) {
        return SPECIAL_CASES[lower];
      }

      // Default: capitalize first letter
      return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
    })
    .join(' ');
}

/**
 * Format cloud provider name
 *
 * @param {string} provider - Provider name (e.g., "azure", "gcp", "terraform-azure")
 * @returns {string} - Formatted provider name (e.g., "Azure", "GCP")
 */
export function formatProviderName(provider) {
  if (!provider) return '';

  // Remove prefix if present
  const cleanProvider = provider.replace(/^terraform-/, '');

  const upper = cleanProvider.toUpperCase();
  if (ACRONYMS.has(upper)) {
    return upper;
  }

  return cleanProvider.charAt(0).toUpperCase() + cleanProvider.slice(1).toLowerCase();
}

/**
 * Format parameter label
 * Converts snake_case to Title Case
 *
 * @param {string} paramName - Parameter name (e.g., "storage_account_name")
 * @returns {string} - Formatted label (e.g., "Storage Account Name")
 */
export function formatParameterLabel(paramName) {
  if (!paramName) return '';

  return paramName
    .split('_')
    .map(word => {
      const lower = word.toLowerCase();
      const upper = word.toUpperCase();

      // Check if it's an acronym
      if (ACRONYMS.has(upper)) {
        return upper;
      }

      // Check special cases
      if (SPECIAL_CASES[lower]) {
        return SPECIAL_CASES[lower];
      }

      // Default: capitalize first letter
      return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
    })
    .join(' ');
}

/**
 * Format file size for display
 *
 * @param {number} bytes - Size in bytes
 * @returns {string} - Formatted size (e.g., "1.5 MB")
 */
export function formatFileSize(bytes) {
  if (!bytes || bytes === 0) return '0 Bytes';

  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}

/**
 * Format date for display
 *
 * @param {string|Date} date - Date to format
 * @returns {string} - Formatted date
 */
export function formatDate(date) {
  if (!date) return '';

  const d = new Date(date);
  return d.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}
