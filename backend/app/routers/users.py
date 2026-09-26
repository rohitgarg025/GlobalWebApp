import json

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.db.database import get_db
from app.db.models import AuthRole, AuthUser
from app.models.schemas import (
    AuthUserOut,
    RoleOut,
    RoleCreateRequest,
    RoleUpdateRequest,
    AssignRoleRequest,
)
from app.services import auth_service
from app.services.auth_deps import require_module
from app.services.modules import ALL_MODULES, MODULE_USER_MANAGEMENT

router = APIRouter(
    prefix="/api",
    tags=["users"],
    dependencies=[Depends(require_module(MODULE_USER_MANAGEMENT))],
)


def _role_out(role: AuthRole) -> RoleOut:
    return RoleOut(
        id=role.id,
        name=role.name,
        modules=auth_service.get_role_modules(role),
        is_system=role.is_system,
    )


def _validate_modules(modules):
    unknown = [m for m in modules if m not in ALL_MODULES]
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown module id(s): {unknown}. Valid: {ALL_MODULES}")


@router.get("/users", response_model=list[AuthUserOut])
async def list_users(db: Session = Depends(get_db)):
    users = db.query(AuthUser).order_by(AuthUser.email).all()
    roles = {r.id: r for r in db.query(AuthRole).all()}
    return [auth_service.user_out(u, roles[u.role_id]) for u in users]


@router.put("/users/{user_id}/role", response_model=AuthUserOut)
async def assign_role(
    user_id: int,
    body: AssignRoleRequest,
    db: Session = Depends(get_db),
    current: AuthUser = Depends(require_module(MODULE_USER_MANAGEMENT)),
):
    user = db.query(AuthUser).filter(AuthUser.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found.")
    role = db.query(AuthRole).filter(AuthRole.id == body.role_id).first()
    if role is None:
        raise HTTPException(status_code=404, detail="Role not found.")

    if user.id == current.id and MODULE_USER_MANAGEMENT not in auth_service.get_role_modules(role):
        raise HTTPException(status_code=422, detail="You cannot remove your own access to User Management.")

    user.role_id = role.id
    db.commit()
    db.refresh(user)
    return auth_service.user_out(user, role)


@router.get("/roles", response_model=list[RoleOut])
async def list_roles(db: Session = Depends(get_db)):
    return [_role_out(r) for r in db.query(AuthRole).order_by(AuthRole.name).all()]


@router.post("/roles", response_model=RoleOut)
async def create_role(body: RoleCreateRequest, db: Session = Depends(get_db)):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="Role name cannot be empty.")
    if db.query(AuthRole).filter(AuthRole.name == name).first():
        raise HTTPException(status_code=422, detail=f"Role '{name}' already exists.")
    _validate_modules(body.modules)
    role = AuthRole(name=name, modules=json.dumps(body.modules), is_system=False)
    db.add(role)
    db.commit()
    db.refresh(role)
    return _role_out(role)


@router.put("/roles/{role_id}", response_model=RoleOut)
async def update_role(role_id: int, body: RoleUpdateRequest, db: Session = Depends(get_db)):
    role = db.query(AuthRole).filter(AuthRole.id == role_id).first()
    if role is None:
        raise HTTPException(status_code=404, detail="Role not found.")

    if body.name is not None and body.name.strip() != role.name:
        if role.is_system:
            raise HTTPException(status_code=422, detail="System roles cannot be renamed.")
        name = body.name.strip()
        if not name:
            raise HTTPException(status_code=422, detail="Role name cannot be empty.")
        if db.query(AuthRole).filter(AuthRole.name == name).first():
            raise HTTPException(status_code=422, detail=f"Role '{name}' already exists.")
        role.name = name

    if body.modules is not None:
        _validate_modules(body.modules)
        if role.name == "admin" and MODULE_USER_MANAGEMENT not in body.modules:
            raise HTTPException(status_code=422, detail="The admin role must keep User Management access.")
        role.modules = json.dumps(body.modules)

    db.commit()
    db.refresh(role)
    return _role_out(role)


@router.delete("/roles/{role_id}")
async def delete_role(role_id: int, db: Session = Depends(get_db)):
    role = db.query(AuthRole).filter(AuthRole.id == role_id).first()
    if role is None:
        raise HTTPException(status_code=404, detail="Role not found.")
    if role.is_system:
        raise HTTPException(status_code=422, detail="System roles cannot be deleted.")
    in_use = db.query(AuthUser).filter(AuthUser.role_id == role.id).count()
    if in_use:
        raise HTTPException(status_code=422, detail=f"Role is assigned to {in_use} user(s). Reassign them first.")
    db.delete(role)
    db.commit()
    return {"deleted": True}
