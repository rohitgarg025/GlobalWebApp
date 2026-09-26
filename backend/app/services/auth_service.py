"""Google ID-token verification, user provisioning and JWT session tokens."""

import json
import os
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from sqlalchemy.orm import Session

from app.db.models import AuthRole, AuthUser

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
# Random default keeps dev working out of the box; set AUTH_SECRET_KEY in
# production or sessions are invalidated on every restart.
AUTH_SECRET_KEY = os.getenv("AUTH_SECRET_KEY") or secrets.token_hex(32)
ADMIN_EMAILS = {
    e.strip().lower()
    for e in os.getenv("ADMIN_EMAILS", "rohitgarg025@gmail.com").split(",")
    if e.strip()
}
TOKEN_TTL_DAYS = 7
JWT_ALGORITHM = "HS256"


class AuthError(Exception):
    """Raised for any authentication failure; routers map it to 401."""


def verify_google_token(id_token_str: str) -> dict:
    """Verify a Google ID token and return {email, name, picture}."""
    if not GOOGLE_CLIENT_ID:
        raise AuthError("Server is missing GOOGLE_CLIENT_ID configuration.")
    try:
        info = google_id_token.verify_oauth2_token(
            id_token_str, google_requests.Request(), audience=GOOGLE_CLIENT_ID
        )
    except ValueError as e:
        raise AuthError(f"Invalid Google token: {e}")
    email = (info.get("email") or "").lower()
    if not email or not info.get("email_verified", False):
        raise AuthError("Google account has no verified email.")
    return {
        "email": email,
        "name": info.get("name") or email,
        "picture": info.get("picture"),
    }


def get_role_modules(role: AuthRole) -> list:
    try:
        return json.loads(role.modules or "[]")
    except (ValueError, TypeError):
        return []


def login(db: Session, id_token_str: str) -> dict:
    """Verify the Google token, find-or-create the user, return token + profile."""
    profile = verify_google_token(id_token_str)
    user = provision_user(db, profile["email"], profile["name"], profile["picture"])
    return issue_session(db, user)


def provision_user(db: Session, email: str, name: str = None, picture: str = None) -> AuthUser:
    email = email.lower()
    user = db.query(AuthUser).filter(AuthUser.email == email).first()

    admin_role = db.query(AuthRole).filter(AuthRole.name == "admin").first()
    guest_role = db.query(AuthRole).filter(AuthRole.name == "guest").first()

    if user is None:
        role = admin_role if email in ADMIN_EMAILS else guest_role
        user = AuthUser(email=email, role_id=role.id)
        db.add(user)
    elif email in ADMIN_EMAILS:
        # Bootstrap guarantee: configured admins can never be locked out
        user.role_id = admin_role.id

    if name:
        user.display_name = name
    if picture:
        user.picture_url = picture
    user.last_login_at = datetime.utcnow()
    db.commit()
    db.refresh(user)
    return user


def issue_session(db: Session, user: AuthUser) -> dict:
    role = db.query(AuthRole).filter(AuthRole.id == user.role_id).first()
    modules = get_role_modules(role)
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": str(user.id),
            "email": user.email,
            "iat": now,
            "exp": now + timedelta(days=TOKEN_TTL_DAYS),
        },
        AUTH_SECRET_KEY,
        algorithm=JWT_ALGORITHM,
    )
    return {
        "token": token,
        "user": user_out(user, role, modules),
    }


def decode_session_token(token: str) -> dict:
    try:
        return jwt.decode(token, AUTH_SECRET_KEY, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise AuthError("Session expired. Please sign in again.")
    except jwt.InvalidTokenError:
        raise AuthError("Invalid session token.")


def user_out(user: AuthUser, role: AuthRole, modules: list = None) -> dict:
    if modules is None:
        modules = get_role_modules(role)
    return {
        "id": user.id,
        "email": user.email,
        "name": user.display_name,
        "picture": user.picture_url,
        "role": role.name,
        "modules": modules,
        "last_login_at": user.last_login_at.isoformat() if user.last_login_at else None,
    }
