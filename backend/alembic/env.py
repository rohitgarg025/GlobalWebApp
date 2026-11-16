"""Alembic environment: uses the app's own engine and models."""
from logging.config import fileConfig

from alembic import context

from app.db.database import Base, engine
import app.db.models  # noqa: F401 — registers every table on Base.metadata

config = context.config
if config.config_file_name is not None and config.attributes.get("configure_logger", True):
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = Base.metadata


# Made by the pre-Alembic start-up code on older databases; it is the only thing enforcing
# unique (project_id, code) there, so autogenerate must never propose dropping it.
_KEEP_UNMODELLED = {"ux_pm_activities_project_code"}


def _include_object(obj, name, type_, reflected, compare_to):
    return not (type_ == "index" and reflected and compare_to is None and name in _KEEP_UNMODELLED)


def _configure(**kw) -> None:
    context.configure(
        target_metadata=target_metadata,
        include_object=_include_object,
        render_as_batch=True,  # SQLite can't ALTER most things; batch mode rebuilds the table
        compare_type=True,
        **kw,
    )


def run_migrations_offline() -> None:
    _configure(url=str(engine.url), literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connection = config.attributes.get("connection")
    if connection is not None:  # called from init_db() with an open connection
        _configure(connection=connection)
        context.run_migrations()
        return
    with engine.begin() as conn:
        _configure(connection=conn)
        context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
