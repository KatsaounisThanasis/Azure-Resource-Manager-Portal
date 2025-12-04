import LoadingSpinner from './LoadingSpinner';

function LoadingState({ message = 'Loading...', subMessage = null, fullPage = false }) {
  const containerClass = fullPage
    ? 'flex flex-col items-center justify-center min-h-screen bg-gray-50'
    : 'flex flex-col items-center justify-center py-12';

  return (
    <div className={containerClass}>
      <LoadingSpinner size="lg" />
      <p className="mt-4 text-lg font-medium text-gray-900">{message}</p>
      {subMessage && (
        <p className="mt-2 text-sm text-gray-600">{subMessage}</p>
      )}
    </div>
  );
}

export default LoadingState;
