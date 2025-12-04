import { useState, useEffect } from 'react';
import axios from 'axios';
import LoadingSpinner from './LoadingSpinner';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

function CostPreview({ provider, templateName, parameters }) {
  const [cost, setCost] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!provider || !templateName || !parameters || Object.keys(parameters).length === 0) {
      return;
    }

    const fetchCostEstimate = async () => {
      setLoading(true);
      setError(null);

      try {
        const response = await axios.post(
          `${API_BASE_URL}/templates/${provider}/${templateName}/estimate-cost`,
          parameters
        );

        if (response.data.success) {
          setCost(response.data.data);
        }
      } catch (err) {
        console.error('Cost estimation error:', err);
        setError('Failed to estimate cost');
      } finally {
        setLoading(false);
      }
    };

    // Debounce API calls
    const timer = setTimeout(() => {
      fetchCostEstimate();
    }, 500);

    return () => clearTimeout(timer);
  }, [provider, templateName, JSON.stringify(parameters)]);

  if (loading) {
    return (
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div className="flex items-center">
          <LoadingSpinner size="sm" className="mr-2" />
          <span className="text-sm text-blue-800">Calculating cost estimate...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
        <div className="flex items-start">
          <svg className="w-5 h-5 text-yellow-400 mr-2 flex-shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
          <div>
            <p className="text-sm font-medium text-yellow-800">Cost Estimation Unavailable</p>
            <p className="text-xs text-yellow-700 mt-1">Unable to calculate cost estimate. Deployment can proceed.</p>
          </div>
        </div>
      </div>
    );
  }

  if (!cost) {
    return null;
  }

  return (
    <div className="bg-gradient-to-br from-green-50 to-emerald-50 border border-green-200 rounded-lg p-5 shadow-sm">
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center">
          <svg className="w-6 h-6 text-green-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <h3 className="text-lg font-semibold text-gray-900">Estimated Cost</h3>
        </div>
        <div className="text-right">
          <p className="text-2xl font-bold text-green-700">${cost.total_monthly_cost}</p>
          <p className="text-xs text-green-600">{cost.currency}/month</p>
        </div>
      </div>

      {/* Cost Breakdown */}
      {cost.breakdown && cost.breakdown.length > 0 && (
        <div className="mt-4 space-y-2">
          <p className="text-sm font-medium text-gray-700">Cost Breakdown:</p>
          {cost.breakdown.map((item, index) => (
            <div key={index} className="flex justify-between items-start text-sm bg-white bg-opacity-60 rounded px-3 py-2">
              <div className="flex-1">
                <p className="font-medium text-gray-800">{item.component}</p>
                {item.details && (
                  <p className="text-xs text-gray-600 mt-0.5">{item.details}</p>
                )}
              </div>
              <span className="font-semibold text-gray-800 ml-4">${item.cost}/{item.unit}</span>
            </div>
          ))}
        </div>
      )}

      {/* Notes */}
      {cost.notes && cost.notes.length > 0 && (
        <div className="mt-4 pt-3 border-t border-green-200">
          <p className="text-xs font-medium text-gray-700 mb-2">Notes:</p>
          <ul className="space-y-1">
            {cost.notes.map((note, index) => (
              <li key={index} className="text-xs text-gray-600 flex items-start">
                <span className="text-green-600 mr-1.5">•</span>
                <span>{note}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="mt-4 pt-3 border-t border-green-200">
        <p className="text-xs text-gray-600 italic">
          💡 This is an estimate based on standard pricing. Actual costs may vary based on usage patterns, regional pricing, and active discounts.
        </p>
      </div>
    </div>
  );
}

export default CostPreview;
