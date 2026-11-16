# Database migrations (Alembic)

The database comes from `DATABASE_URL` if it is set, otherwise from a SQLite file at `DB_PATH`, otherwise from `backend/quantity_sheet.db`. See `app/db/database.py`.

The app runs `alembic upgrade head` itself on start-up, inside `init_db()`, so a deploy needs no extra step.

## Changing a model

Run these from `backend/`:

```bash
.venv/bin/python3 -m alembic revision --autogenerate -m "add drawing sheet size"
```

1. Read the new file in `alembic/versions/` and fix anything autogenerate got wrong. It can't detect renames: a renamed column shows up as a drop plus an add.
2. Restart the backend. The migration runs on start-up.
3. Check that nothing is left over:

   ```bash
   .venv/bin/python3 -m alembic check
   ```

   It should report "No new upgrade operations detected."

## Notes

- `0001` is the baseline: the schema as of November 2026. Databases created before Alembic are brought up to it once by the old start-up code, then stamped `0001`.
- SQLite can't alter most column properties in place. `render_as_batch=True` in `env.py` makes Alembic rebuild the table instead.
- Production uses PostgreSQL on Amazon RDS, via `DATABASE_URL` and the `psycopg` driver. Local development and tests still use SQLite. Migrations must work on both, so check new scripts with `alembic check` locally.
- To run the migration test against a scratch Postgres database:

  ```bash
  TEST_DATABASE_URL=postgresql+psycopg://… python -m unittest tests.test_migrations
  ```

  It drops every table in that database, so never point it at `gbe`.
