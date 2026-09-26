import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers.reports import router
from app.routers.quantity_sheet import router as qs_router
from app.routers.auth import router as auth_router
from app.routers.users import router as users_router
from app.routers.projects import router as projects_router
from app.routers.project_schedule import router as schedule_router
from app.routers.hindrance_register import router as hindrance_router
from app.services.auth_deps import require_module
from app.services.modules import MODULE_REPORT_TRANSFORMER, MODULE_QUANTITY_SHEET
from app.db.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    base = Path(__file__).parent.parent / "temp"
    (base / "outputs").mkdir(parents=True, exist_ok=True)
    init_db()
    yield


app = FastAPI(
    title="Global Buildestate Report API",
    description="Excel report generation API for Global Buildestate ERP data",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS — defaults to all origins for local dev; set ALLOWED_ORIGINS in production
_origins_raw = os.getenv("ALLOWED_ORIGINS", "*")
_origins = ["*"] if _origins_raw == "*" else [o.strip() for o in _origins_raw.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}


app.include_router(auth_router)
app.include_router(users_router)
app.include_router(projects_router)
app.include_router(router, dependencies=[Depends(require_module(MODULE_REPORT_TRANSFORMER))])
app.include_router(qs_router, dependencies=[Depends(require_module(MODULE_QUANTITY_SHEET))])
app.include_router(schedule_router)
app.include_router(hindrance_router)
