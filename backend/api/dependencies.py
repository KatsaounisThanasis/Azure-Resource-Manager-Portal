"""
FastAPI Dependencies

Common dependencies used across API routes.
"""

from fastapi import Header, HTTPException
from typing import Optional
from backend.core.auth import get_current_user as get_jwt_user


async def get_current_user_dependency(authorization: Optional[str] = Header(None)):
    """Get current authenticated user from JWT token"""
    return get_jwt_user(authorization)


async def require_admin_user(current_user: dict = None):
    """Require user to have admin role"""
    if not current_user or current_user.get('role') != 'admin':
        raise HTTPException(
            status_code=403,
            detail="Admin access required"
        )
    return current_user
