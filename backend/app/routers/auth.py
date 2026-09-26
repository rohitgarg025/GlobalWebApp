import os

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthRole, AuthUser
from app.models.schemas import GoogleLoginRequest, LoginResponse, AuthUserOut
from app.services import auth_service
from app.services.auth_deps import get_current_user

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/google", response_model=LoginResponse)
async def google_login(body: GoogleLoginRequest, db: Session = Depends(get_db)):
    try:
        result = auth_service.login(db, body.id_token)
    except auth_service.AuthError as e:
        raise HTTPException(status_code=401, detail=str(e))
    return result


class DevLoginRequest(BaseModel):
    email: str | None = None


@router.post("/dev-login", response_model=LoginResponse)
async def dev_login(body: DevLoginRequest = DevLoginRequest(), db: Session = Depends(get_db)):
    """Dev-only shortcut: issues a real JWT without Google OAuth.
    Disabled when DISABLE_DEV_LOGIN=1 is set (use in production)."""
    if os.getenv("DISABLE_DEV_LOGIN", "").strip() == "1":
        raise HTTPException(status_code=403, detail="Dev login is disabled.")
    email = (body.email or "").strip().lower() or next(iter(auth_service.ADMIN_EMAILS), "dev@local")
    user = auth_service.provision_user(db, email, name="Dev User")
    return auth_service.issue_session(db, user)


@router.get("/me", response_model=AuthUserOut)
async def me(user: AuthUser = Depends(get_current_user), db: Session = Depends(get_db)):
    role = db.query(AuthRole).filter(AuthRole.id == user.role_id).first()
    return auth_service.user_out(user, role)
