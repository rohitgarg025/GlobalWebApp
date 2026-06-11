import os
from pathlib import Path

from sqlalchemy import create_engine
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


def init_db() -> None:
    import app.db.models  # noqa: F401 — registers models with Base
    Base.metadata.create_all(bind=engine)
