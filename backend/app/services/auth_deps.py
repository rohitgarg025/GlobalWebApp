"""FastAPI dependencies for authentication and per-module authorization."""

from fastapi import Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthRole, AuthUser
from app.services import auth_service


def get_current_user(request: Request, db: Session = Depends(get_db)) -> AuthUser:
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated.")
    try:
        claims = auth_service.decode_session_token(auth_header[len("Bearer "):])
    except auth_service.AuthError as e:
        raise HTTPException(status_code=401, detail=str(e))

    user = db.query(AuthUser).filter(AuthUser.id == int(claims["sub"])).first()
    if user is None:
        raise HTTPException(status_code=401, detail="User no longer exists.")
    return user


def get_current_user_modules(
    user: AuthUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list:
    # Role is re-read from DB per request so admin changes apply immediately
    role = db.query(AuthRole).filter(AuthRole.id == user.role_id).first()
    return auth_service.get_role_modules(role)


def require_module(module_id: str):
    def checker(
        user: AuthUser = Depends(get_current_user),
        modules: list = Depends(get_current_user_modules),
    ) -> AuthUser:
        if module_id not in modules:
            raise HTTPException(
                status_code=403,
                detail=f"Your role does not have access to this module ({module_id}).",
            )
        return user

    return checker


def require_admin(
    user: AuthUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AuthUser:
    role = db.query(AuthRole).filter(AuthRole.id == user.role_id).first()
    if role is None or role.name != "admin":
        raise HTTPException(
            status_code=403,
            detail="Only administrators can perform this action.",
        )
    return user
