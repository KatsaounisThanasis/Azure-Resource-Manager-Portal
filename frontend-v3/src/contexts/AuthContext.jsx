import { createContext, useContext, useState, useEffect } from 'react';
import api, { authAPI } from '../api/client';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [token, setToken] = useState(null);
  const [loading, setLoading] = useState(true);
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  // Load user from localStorage on mount
  useEffect(() => {
    const storedToken = localStorage.getItem('auth_token');
    const storedUser = localStorage.getItem('auth_user');

    if (storedToken && storedUser) {
      try {
        const parsedUser = JSON.parse(storedUser);
        setToken(storedToken);
        setUser(parsedUser);
        setIsAuthenticated(true);

        // Set axios default header (handled by interceptor in client.js, but keeping sync)
        // Note: client.js interceptor handles this dynamically, but we can explicit set for clarity
      } catch (error) {
        console.error('Failed to parse stored user:', error);
        logout();
      }
    }

    setLoading(false);
  }, []);

  const login = async (email, password) => {
    try {
      const response = await authAPI.login(email, password);

      if (response.data.success) {
        const { access_token, user: userData } = response.data.data;

        // Store in localStorage
        localStorage.setItem('auth_token', access_token);
        localStorage.setItem('auth_user', JSON.stringify(userData));

        // Update state
        setToken(access_token);
        setUser(userData);
        setIsAuthenticated(true);

        return { success: true, user: userData };
      } else {
        return { success: false, error: response.data.message || 'Login failed' };
      }
    } catch (error) {
      console.error('Login error:', error);
      return {
        success: false,
        error: error.response?.data?.detail || error.response?.data?.message || 'Login failed'
      };
    }
  };

  const register = async (email, password, username, role = 'user') => {
    try {
      const response = await authAPI.register({
        email,
        password,
        username,
        role
      });

      if (response.data.success) {
        // Auto-login after registration
        return await login(email, password);
      } else {
        return { success: false, error: response.data.message || 'Registration failed' };
      }
    } catch (error) {
      console.error('Registration error:', error);
      return {
        success: false,
        error: error.response?.data?.detail || error.response?.data?.message || 'Registration failed'
      };
    }
  };

  const logout = () => {
    // Clear localStorage
    localStorage.removeItem('auth_token');
    localStorage.removeItem('auth_user');

    // Clear state
    setToken(null);
    setUser(null);
    setIsAuthenticated(false);
  };

  const updateUser = async (updates) => {
    if (!user || !token) return { success: false, error: 'Not authenticated' };

    try {
      const response = await authAPI.updateUser(user.email, updates);

      if (response.data.success) {
        const updatedUser = response.data.data.user;

        // Update localStorage
        localStorage.setItem('auth_user', JSON.stringify(updatedUser));

        // Update state
        setUser(updatedUser);

        return { success: true, user: updatedUser };
      } else {
        return { success: false, error: response.data.message || 'Update failed' };
      }
    } catch (error) {
      console.error('Update user error:', error);
      return {
        success: false,
        error: error.response?.data?.detail || error.response?.data?.message || 'Update failed'
      };
    }
  };

  const getCurrentUser = async () => {
    if (!token) return null;

    try {
      const response = await authAPI.getCurrentUser();

      if (response.data.success) {
        const userData = response.data.data.user;
        const permissions = response.data.data.permissions;

        const userWithPermissions = {
          ...userData,
          permissions
        };

        // Update localStorage
        localStorage.setItem('auth_user', JSON.stringify(userWithPermissions));

        // Update state
        setUser(userWithPermissions);

        return userWithPermissions;
      }
    } catch (error) {
      console.error('Get current user error:', error);
      // If token is invalid, logout
      if (error.response?.status === 401) {
        logout();
      }
    }

    return null;
  };

  const hasPermission = (permission) => {
    if (!user || !user.permissions) return false;
    return user.permissions.includes(permission);
  };

  const isAdmin = () => {
    return user?.role === 'admin';
  };

  const isUser = () => {
    return user?.role === 'user';
  };

  const isViewer = () => {
    return user?.role === 'viewer';
  };

  const value = {
    user,
    token,
    loading,
    isAuthenticated,
    login,
    register,
    logout,
    updateUser,
    getCurrentUser,
    hasPermission,
    isAdmin,
    isUser,
    isViewer
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
