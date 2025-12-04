import { useState, useEffect, useRef } from 'react';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

function DeploymentLogStream({ deploymentId, onComplete }) {
  const [logs, setLogs] = useState([]);
  const [status, setStatus] = useState('connecting');
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState(null);
  const eventSourceRef = useRef(null);
  const logsEndRef = useRef(null);

  // Auto-scroll to bottom
  const scrollToBottom = () => {
    logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [logs]);

  useEffect(() => {
    if (!deploymentId) return;

    // Create EventSource connection
    const eventSource = new EventSource(
      `${API_BASE_URL}/deployments/${deploymentId}/logs`
    );
    eventSourceRef.current = eventSource;

    eventSource.onopen = () => {
      setStatus('connected');
      setLogs(prev => [...prev, {
        type: 'system',
        message: 'Connected to deployment stream',
        timestamp: new Date().toISOString()
      }]);
    };

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        switch (data.type) {
          case 'log':
            setLogs(prev => [...prev, {
              type: 'log',
              message: data.message,
              timestamp: data.timestamp
            }]);
            break;

          case 'status':
            setStatus(data.status);
            setLogs(prev => [...prev, {
              type: 'status',
              message: data.message,
              timestamp: new Date().toISOString()
            }]);
            break;

          case 'progress':
            setProgress(data.progress);
            break;

          case 'complete':
            setStatus('completed');
            setProgress(100);
            setLogs(prev => [...prev, {
              type: 'success',
              message: data.message,
              timestamp: new Date().toISOString()
            }]);
            if (onComplete) {
              onComplete({ status: 'completed', outputs: data.outputs });
            }
            eventSource.close();
            break;

          case 'error':
            setError(data.message);
            setStatus('failed');
            setLogs(prev => [...prev, {
              type: 'error',
              message: data.message,
              timestamp: new Date().toISOString()
            }]);
            if (onComplete) {
              onComplete({ status: 'failed', error: data.message });
            }
            eventSource.close();
            break;

          case 'done':
            eventSource.close();
            break;

          default:
            console.log('Unknown event type:', data.type);
        }
      } catch (err) {
        console.error('Error parsing SSE data:', err);
      }
    };

    eventSource.onerror = (err) => {
      console.error('EventSource error:', err);
      setStatus('error');
      setError('Connection lost');
      setLogs(prev => [...prev, {
        type: 'error',
        message: 'Lost connection to deployment stream',
        timestamp: new Date().toISOString()
      }]);
      eventSource.close();
    };

    // Cleanup
    return () => {
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
      }
    };
  }, [deploymentId, onComplete]);

  const getStatusColor = () => {
    switch (status) {
      case 'connecting':
        return 'bg-gray-100 text-gray-600';
      case 'connected':
      case 'running':
        return 'bg-blue-100 text-blue-600';
      case 'completed':
        return 'bg-green-100 text-green-600';
      case 'failed':
      case 'error':
        return 'bg-red-100 text-red-600';
      default:
        return 'bg-gray-100 text-gray-600';
    }
  };

  const getStatusIcon = () => {
    switch (status) {
      case 'connecting':
        return '🔄';
      case 'connected':
      case 'running':
        return '⚙️';
      case 'completed':
        return '✓';
      case 'failed':
      case 'error':
        return '✗';
      default:
        return '•';
    }
  };

  const getLogTypeStyle = (type) => {
    switch (type) {
      case 'error':
        return 'text-red-600 bg-red-50 border-l-4 border-red-500 pl-3';
      case 'success':
        return 'text-green-600 bg-green-50 border-l-4 border-green-500 pl-3';
      case 'status':
        return 'text-blue-600 bg-blue-50 border-l-4 border-blue-500 pl-3';
      case 'system':
        return 'text-gray-500 bg-gray-50 border-l-4 border-gray-400 pl-3 italic';
      default:
        return 'text-gray-800';
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
      {/* Header */}
      <div className="bg-gray-800 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <span className="text-lg">{getStatusIcon()}</span>
          <h3 className="text-white font-semibold">Deployment Logs</h3>
          <span className={`px-2 py-1 rounded text-xs font-medium ${getStatusColor()}`}>
            {status.toUpperCase()}
          </span>
        </div>
        <div className="flex items-center space-x-4">
          {status === 'running' && (
            <div className="flex items-center space-x-2">
              <div className="text-white text-sm">{progress}%</div>
              <div className="w-32 h-2 bg-gray-700 rounded-full overflow-hidden">
                <div
                  className="h-full bg-blue-500 transition-all duration-300"
                  style={{ width: `${progress}%` }}
                />
              </div>
            </div>
          )}
          <span className="text-gray-400 text-xs">
            {logs.length} log entries
          </span>
        </div>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="bg-red-50 border-b border-red-200 px-4 py-3">
          <div className="flex items-center">
            <span className="text-red-500 mr-2">⚠</span>
            <p className="text-sm text-red-700 font-medium">{error}</p>
          </div>
        </div>
      )}

      {/* Logs Container */}
      <div className="bg-gray-900 p-4 h-96 overflow-y-auto font-mono text-sm">
        {logs.length === 0 ? (
          <div className="text-gray-500 text-center py-8">
            <div className="animate-pulse">Waiting for logs...</div>
          </div>
        ) : (
          <div className="space-y-1">
            {logs.map((log, index) => (
              <div
                key={index}
                className={`py-1 rounded ${getLogTypeStyle(log.type)}`}
              >
                <span className="text-gray-400 mr-2">
                  [{new Date(log.timestamp).toLocaleTimeString()}]
                </span>
                <span className={log.type === 'error' ? 'text-red-400' : 'text-gray-100'}>
                  {log.message}
                </span>
              </div>
            ))}
            <div ref={logsEndRef} />
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="bg-gray-50 px-4 py-2 border-t border-gray-200">
        <div className="flex items-center justify-between text-xs text-gray-500">
          <span>Deployment ID: {deploymentId}</span>
          <span>
            {status === 'running' && '⚙️ In Progress'}
            {status === 'completed' && '✓ Completed'}
            {status === 'failed' && '✗ Failed'}
          </span>
        </div>
      </div>
    </div>
  );
}

export default DeploymentLogStream;
