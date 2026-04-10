import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path

from app.routers.reports import router

app = FastAPI(
    title="Global Buildestate Report API",
    description="Excel report generation API for Global Buildestate ERP data",
    version="1.0.0",
)

# CORS — defaults to all origins for local dev; set ALLOWED_ORIGINS in production
_origins_raw = os.getenv("ALLOWED_ORIGINS", "*")
_origins = ["*"] if _origins_raw == "*" else [o.strip() for o in _origins_raw.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)

# Ensure temp dirs exist on startup
@app.on_event("startup")
async def startup():
    base = Path(__file__).parent.parent / "temp"
    (base / "outputs").mkdir(parents=True, exist_ok=True)
