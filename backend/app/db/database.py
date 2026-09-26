import os
from pathlib import Path

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker, DeclarativeBase

# Production: set DB_PATH env var to a persistent volume path (e.g. /data/qs.db on Fly.io)
_db_path = os.getenv(
    "DB_PATH",
    str(Path(__file__).parent.parent.parent / "quantity_sheet.db"),
)
Path(_db_path).parent.mkdir(parents=True, exist_ok=True)

engine = create_engine(
    f"sqlite:///{_db_path}",
    connect_args={"check_same_thread": False},
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


_LEGACY_TABLES = (
    "qs_baseline_changes",
    "qs_monthly_entries",
    "qs_baselines",
    "qs_floors",
    "qs_projects",
)


def _drop_legacy_qs_projects() -> None:
    """Dummy data may still live under qs_projects; drop it so FKs can point at projects."""
    names = inspect(engine).get_table_names()
    if "qs_projects" not in names:
        return
    with engine.begin() as conn:
        conn.execute(text("PRAGMA foreign_keys=OFF"))
        for table in _LEGACY_TABLES:
            if table in names:
                conn.execute(text(f"DROP TABLE IF EXISTS {table}"))


def init_db() -> None:
    import app.db.models  # noqa: F401 — registers models with Base
    _drop_legacy_qs_projects()
    Base.metadata.create_all(bind=engine)
    _migrate_pm_activities()
    _seed_roles()


def _migrate_pm_activities() -> None:
    """create_all doesn't add columns to existing tables; add grouping/floor columns."""
    existing = {c["name"] for c in inspect(engine).get_columns("pm_activities")}
    wanted = {
        "row_type": "VARCHAR NOT NULL DEFAULT 'activity'",
        "parent_id": "INTEGER REFERENCES pm_activities(id)",
        "floor_id": "INTEGER REFERENCES qs_floors(id)",
    }
    with engine.begin() as conn:
        for name, ddl in wanted.items():
            if name not in existing:
                conn.execute(text(f"ALTER TABLE pm_activities ADD COLUMN {name} {ddl}"))


def _seed_roles() -> None:
    import json
    from app.db.models import AuthRole
    from app.services.modules import ALL_MODULES, MODULE_REPORT_TRANSFORMER

    db = SessionLocal()
    try:
        guest = db.query(AuthRole).filter(AuthRole.name == "guest").first()
        if not guest:
            db.add(AuthRole(name="guest", modules=json.dumps([MODULE_REPORT_TRANSFORMER]), is_system=True))
        admin = db.query(AuthRole).filter(AuthRole.name == "admin").first()
        if not admin:
            db.add(AuthRole(name="admin", modules=json.dumps(ALL_MODULES), is_system=True))
        else:
            admin.modules = json.dumps(ALL_MODULES)
        db.commit()
    finally:
        db.close()
