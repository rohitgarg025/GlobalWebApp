import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers.reports import router
from app.routers.quantity_sheet import router as qs_router
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

app.include_router(router)
app.include_router(qs_router)
