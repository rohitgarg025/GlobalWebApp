"""Alembic migrations: fresh databases, pre-Alembic databases, and repeat start-ups.

Run: python -m unittest discover -s tests
"""
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import MetaData, inspect, text
from sqlalchemy.orm import sessionmaker

import app.db.models  # noqa: F401 — registers models
from app.db import database
from app.db.database import Base, make_engine


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self._engine, self._session = database.engine, database.SessionLocal

    def tearDown(self):
        database.engine.dispose()
        database.engine, database.SessionLocal = self._engine, self._session
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _use(self, name: str):
        eng = make_engine(f"sqlite:///{Path(self.tmp) / name}")
        database.engine = eng
        database.SessionLocal = sessionmaker(bind=eng, autoflush=False)
        return eng

    def _version(self, eng) -> str:
        with eng.connect() as c:
            return c.execute(text("SELECT version_num FROM alembic_version")).scalar_one()

    def _schema_diff(self, eng) -> list:
        with eng.connect() as c:
            return compare_metadata(MigrationContext.configure(c), Base.metadata)

    def test_fresh_database_matches_models(self):
        eng = self._use("fresh.db")
        database.init_db()
        self.assertEqual(self._version(eng), database.BASELINE_REVISION)
        self.assertEqual(self._schema_diff(eng), [])
        with eng.connect() as c:
            roles = {r[0] for r in c.execute(text("SELECT name FROM auth_roles"))}
        self.assertEqual(roles, {"admin", "guest"})

    def test_pre_alembic_database_is_stamped_and_keeps_data(self):
        eng = self._use("old.db")
        # how start-up used to build the database, before Alembic
        Base.metadata.create_all(eng)
        database._migrate_pm_activities()
        database._migrate_takeoff_jobs()
        with eng.begin() as c:
            c.execute(text("INSERT INTO projects (name, status) VALUES ('JWC Commercial', 'active')"))
            c.execute(text("INSERT INTO qs_floors (project_id, name, display_order) VALUES (1, 'GF', 0)"))
        self.assertNotIn("alembic_version", inspect(eng).get_table_names())

        database.init_db()

        self.assertEqual(self._version(eng), database.BASELINE_REVISION)
        with eng.connect() as c:
            self.assertEqual(c.execute(text("SELECT name FROM projects")).scalar_one(), "JWC Commercial")
            self.assertEqual(c.execute(text("SELECT count(*) FROM qs_floors")).scalar_one(), 1)

    def test_init_db_twice_is_harmless(self):
        eng = self._use("twice.db")
        database.init_db()
        with eng.begin() as c:
            c.execute(text("INSERT INTO projects (name, status) VALUES ('P1', 'active')"))
        database.init_db()
        self.assertEqual(self._version(eng), database.BASELINE_REVISION)
        with eng.connect() as c:
            self.assertEqual(c.execute(text("SELECT count(*) FROM projects")).scalar_one(), 1)
            self.assertEqual(c.execute(text("SELECT count(*) FROM auth_roles")).scalar_one(), 2)

    def test_sqlite_foreign_keys_enforced(self):
        eng = self._use("fk.db")
        database.init_db()
        with eng.connect() as c:
            self.assertEqual(c.execute(text("PRAGMA foreign_keys")).scalar_one(), 1)


@unittest.skipUnless(os.getenv("TEST_DATABASE_URL"), "set TEST_DATABASE_URL to a scratch PostgreSQL database")
class PostgresMigrationTests(unittest.TestCase):
    """Same schema checks on a real PostgreSQL database. Every table in it is dropped."""

    def setUp(self):
        self._engine, self._session = database.engine, database.SessionLocal
        self.eng = make_engine(os.environ["TEST_DATABASE_URL"])
        self._wipe()
        database.engine = self.eng
        database.SessionLocal = sessionmaker(bind=self.eng, autoflush=False)

    def tearDown(self):
        self._wipe()
        self.eng.dispose()
        database.engine, database.SessionLocal = self._engine, self._session

    def _wipe(self):
        md = MetaData()
        md.reflect(bind=self.eng)
        md.drop_all(bind=self.eng)

    def test_fresh_postgres_matches_models_and_works(self):
        database.init_db()
        database.init_db()  # second start-up is harmless
        with self.eng.connect() as c:
            self.assertEqual(c.execute(text("SELECT version_num FROM alembic_version")).scalar_one(),
                             database.BASELINE_REVISION)
            self.assertEqual(compare_metadata(MigrationContext.configure(c), Base.metadata), [])
            roles = {r[0] for r in c.execute(text("SELECT name FROM auth_roles"))}
        self.assertEqual(roles, {"admin", "guest"})

        from app.db.models import Project, QsFloor
        db = database.SessionLocal()
        try:
            p = Project(name="PG check", status="active")
            db.add(p)
            db.flush()
            db.add(QsFloor(project_id=p.id, name="GF", display_order=0))
            db.commit()
            self.assertEqual(db.query(QsFloor).filter_by(project_id=p.id).count(), 1)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
