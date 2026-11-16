import os
from pathlib import Path

from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import sessionmaker, DeclarativeBase


def database_url() -> str:
    """DATABASE_URL (e.g. postgresql+psycopg://user:pass@host/db) wins; otherwise a SQLite
    file at DB_PATH (a persistent volume in production, e.g. /data/app.db)."""
    url = os.getenv("DATABASE_URL")
    if url:
        return url
    db_path = os.getenv("DB_PATH", str(Path(__file__).parent.parent.parent / "quantity_sheet.db"))
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    return f"sqlite:///{db_path}"


def make_engine(url: str):
    if not url.startswith("sqlite"):
        return create_engine(url, pool_pre_ping=True)
    eng = create_engine(url, connect_args={"check_same_thread": False})

    @event.listens_for(eng, "connect")
    def _sqlite_fk_on(dbapi_conn, _record):
        # SQLite ignores foreign keys unless asked; Postgres always enforces them.
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA foreign_keys=ON")
        cur.close()

    return eng


engine = make_engine(database_url())
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


_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
BASELINE_REVISION = "0001"


def _alembic_config():
    from alembic.config import Config

    cfg = Config(str(_BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(_BACKEND_DIR / "alembic"))
    cfg.attributes["configure_logger"] = False  # keep uvicorn's logging as it is
    return cfg


def init_db() -> None:
    """Bring the database schema up to date (Alembic), then seed the system roles.

    A database made before Alembic was added has tables but no alembic_version row: the old
    start-up fixes bring it to the baseline schema once, and it is stamped at the baseline.
    """
    from alembic import command

    import app.db.models  # noqa: F401 — registers models with Base

    cfg = _alembic_config()
    tables = set(inspect(engine).get_table_names())
    if tables - {"alembic_version"} and "alembic_version" not in tables:
        _drop_legacy_qs_projects()
        Base.metadata.create_all(bind=engine)
        _migrate_pm_activities()
        _migrate_takeoff_jobs()
        command.stamp(cfg, BASELINE_REVISION)
    command.upgrade(cfg, "head")
    _seed_roles()


def _migrate_takeoff_jobs() -> None:
    """Pre-Alembic fix: only runs on databases made before migrations existed."""
    existing = {c["name"] for c in inspect(engine).get_columns("takeoff_jobs")}
    if "default_slab_mm" not in existing:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE takeoff_jobs ADD COLUMN default_slab_mm INTEGER"))


def _migrate_pm_activities() -> None:
    """Pre-Alembic fix (create_all doesn't add columns to existing tables)."""
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
        # COD is system-generated and unique per project; enforce it in the DB too.
        conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_pm_activities_project_code "
            "ON pm_activities(project_id, code)"
        ))


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
