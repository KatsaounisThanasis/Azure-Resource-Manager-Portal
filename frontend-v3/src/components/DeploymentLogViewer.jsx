import { useState, useEffect, useRef } from 'react';

const LOG_LEVELS = ['ALL', 'INFO', 'WARNING', 'ERROR', 'DEBUG'];
const LOG_PHASES = ['ALL', 'INITIALIZATION', 'VALIDATING', 'PLANNING', 'APPLYING', 'FINALIZING', 'FAILED'];

function DeploymentLogViewer({ deploymentId, apiBaseUrl }) {
  const [logs, setLogs] = useState([]);
  const [filteredLogs, setFilteredLogs] = useState([]);
  const [levelFilter, setLevelFilter] = useState('ALL');
  const [phaseFilter, setPhaseFilter] = useState('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [autoScroll, setAutoScroll] = useState(true);
  const logsEndRef = useRef(null);
  const eventSourceRef = useRef(null);

  // Scroll to bottom when new logs arrive
  useEffect(() => {
    if (autoScroll && logsEndRef.current) {
      logsEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [filteredLogs, autoScroll]);

  // Connect to SSE stream
  useEffect(() => {
    const eventSource = new EventSource(`${apiBaseUrl}/deployments/${deploymentId}/logs`);
    eventSourceRef.current = eventSource;

    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);

      if (data.type === 'log') {
        setLogs((prevLogs) => [
          ...prevLogs,
          {
            timestamp: data.timestamp,
            level: data.level || 'INFO',
            phase: data.phase || 'unknown',
            message: data.message,
            details: data.details,
          },
        ]);
      } else if (data.type === 'complete' || data.type === 'done') {
        eventSource.close();
      }
    };

    eventSource.onerror = (error) => {
      console.error('SSE error:', error);
      eventSource.close();
    };

    return () => {
      eventSource.close();
    };
  }, [deploymentId, apiBaseUrl]);

  // Apply filters
  useEffect(() => {
    let filtered = logs;

    // Level filter
    if (levelFilter !== 'ALL') {
      filtered = filtered.filter((log) => log.level === levelFilter);
    }

    // Phase filter
    if (phaseFilter !== 'ALL') {
      filtered = filtered.filter((log) => log.phase.toUpperCase() === phaseFilter);
    }

    // Search filter
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(
        (log) =>
          log.message.toLowerCase().includes(query) ||
          log.level.toLowerCase().includes(query) ||
          log.phase.toLowerCase().includes(query)
      );
    }

    setFilteredLogs(filtered);
  }, [logs, levelFilter, phaseFilter, searchQuery]);

  const getLevelColor = (level) => {
    switch (level) {
      case 'ERROR':
        return 'text-red-600 bg-red-50';
      case 'WARNING':
        return 'text-yellow-700 bg-yellow-50';
      case 'INFO':
        return 'text-blue-600 bg-blue-50';
      case 'DEBUG':
        return 'text-gray-600 bg-gray-50';
      default:
        return 'text-gray-800 bg-gray-50';
    }
  };

  const getPhaseColor = (phase) => {
    const phaseUpper = phase?.toUpperCase() || 'UNKNOWN';
    switch (phaseUpper) {
      case 'INITIALIZATION':
        return 'text-purple-600 bg-purple-50';
      case 'VALIDATING':
        return 'text-blue-600 bg-blue-50';
      case 'PLANNING':
        return 'text-cyan-600 bg-cyan-50';
      case 'APPLYING':
        return 'text-green-600 bg-green-50';
      case 'FINALIZING':
        return 'text-indigo-600 bg-indigo-50';
      case 'FAILED':
        return 'text-red-600 bg-red-50';
      default:
        return 'text-gray-600 bg-gray-50';
    }
  };

  const formatTimestamp = (timestamp) => {
    try {
      const date = new Date(timestamp);
      return date.toLocaleTimeString('en-US', { hour12: false });
    } catch {
      return timestamp;
    }
  };

  return (
    <div className="bg-white shadow overflow-hidden sm:rounded-lg">
      {/* Header with Filters */}
      <div className="px-4 py-5 sm:px-6 border-b border-gray-200">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg leading-6 font-medium text-gray-900">Deployment Logs</h3>
          <div className="flex items-center space-x-2">
            <label className="inline-flex items-center">
              <input
                type="checkbox"
                checked={autoScroll}
                onChange={(e) => setAutoScroll(e.target.checked)}
                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span className="ml-2 text-sm text-gray-700">Auto-scroll</span>
            </label>
            <span className="text-sm text-gray-500">
              {filteredLogs.length} / {logs.length} logs
            </span>
          </div>
        </div>

        {/* Filters */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Search */}
          <div>
            <input
              type="text"
              placeholder="Search logs..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 text-sm"
            />
          </div>

          {/* Level Filter */}
          <div>
            <select
              value={levelFilter}
              onChange={(e) => setLevelFilter(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 text-sm"
            >
              {LOG_LEVELS.map((level) => (
                <option key={level} value={level}>
                  Level: {level}
                </option>
              ))}
            </select>
          </div>

          {/* Phase Filter */}
          <div>
            <select
              value={phaseFilter}
              onChange={(e) => setPhaseFilter(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 text-sm"
            >
              {LOG_PHASES.map((phase) => (
                <option key={phase} value={phase}>
                  Phase: {phase}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Log Display */}
      <div className="bg-gray-900 text-gray-100 p-4 font-mono text-sm max-h-96 overflow-y-auto">
        {filteredLogs.length === 0 ? (
          <div className="text-gray-400 text-center py-8">
            {logs.length === 0 ? 'Waiting for logs...' : 'No logs match the current filters'}
          </div>
        ) : (
          filteredLogs.map((log, index) => (
            <div key={index} className="flex items-start space-x-2 mb-1 hover:bg-gray-800 px-2 py-1 rounded">
              {/* Timestamp */}
              <span className="text-gray-500 flex-shrink-0">{formatTimestamp(log.timestamp)}</span>

              {/* Level Badge */}
              <span
                className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium flex-shrink-0 ${getLevelColor(
                  log.level
                )}`}
              >
                {log.level}
              </span>

              {/* Phase Badge */}
              <span
                className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium flex-shrink-0 ${getPhaseColor(
                  log.phase
                )}`}
              >
                {log.phase}
              </span>

              {/* Message */}
              <span className="flex-1 break-words">{log.message}</span>

              {/* Details (if present) */}
              {log.details && (
                <details className="flex-shrink-0">
                  <summary className="cursor-pointer text-blue-400 text-xs">📋</summary>
                  <pre className="mt-1 text-xs bg-gray-800 p-2 rounded overflow-x-auto">
                    {JSON.stringify(log.details, null, 2)}
                  </pre>
                </details>
              )}
            </div>
          ))
        )}
        <div ref={logsEndRef} />
      </div>
    </div>
  );
}

export default DeploymentLogViewer;
