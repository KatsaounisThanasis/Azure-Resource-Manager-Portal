import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import LoadingState from './LoadingState';

function ProtectedRoute({ children, requireAuth = true, requiredPermission = null }) {
  const { isAuthenticated, loading, hasPermission } = useAuth();
  const location = useLocation();

  if (loading) {
    return <LoadingState message="Checking authentication..." fullPage />;
  }

  if (requireAuth && !isAuthenticated) {
    // Redirect to login but save the attempted URL
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (requiredPermission && !hasPermission(requiredPermission)) {
    // Redirect to dashboard if user doesn't have required permission
    return <Navigate to="/" replace />;
  }

  return children;
}

export default ProtectedRoute;
