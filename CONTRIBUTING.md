# Working on the Global Buildestate app

This repository is **public**, so anyone on the internet can read it. Never commit company data. See the rules below.

## What's here

| Folder | What it is |
|---|---|
| `backend/` | FastAPI API (Python 3.11+), SQLAlchemy models, Alembic migrations, tests |
| `flutter_app/` | Flutter **web** app (the UI) |
| `infra/aws/`, `scripts/` | Hosting. Only the owner deploys; you don't need AWS access |

## First-time setup

**Backend**

```bash
cd backend
```

```bash
python3 -m venv .venv
```

```bash
.venv/bin/python3 -m pip install -r requirements.txt
```

Run it on http://127.0.0.1:8765. With no settings it uses a local SQLite file, `backend/quantity_sheet.db`, which git ignores:

```bash
.venv/bin/python3 -m uvicorn app.main_api:app --port 8765 --reload
```

Converting DWG drawings (Quantity Takeoff, BBS, Drawing Register previews) needs LibreDWG's `dwg2dxf` on your PATH. Everything else works without it.

**Web app** (Flutter 3.x)

```bash
cd flutter_app
```

```bash
flutter pub get
```

```bash
flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:8765
```

On the sign-in page, **Skip — Enter as Dev / Admin** logs you in locally.

## Before you open a pull request

1. **Backend tests:** run `.venv/bin/python3 -m unittest discover -s tests` from `backend/`.
2. **Web app:** `flutter analyze` from `flutter_app/` shows no new warnings. The app is web-only, so check it in the browser, at desktop width and at phone width (375 px).
3. **Database changes:** if you changed a model in `backend/app/db/models.py`, add a migration:
   ```bash
   .venv/bin/python3 -m alembic revision --autogenerate -m "what changed"
   ```
   Read the generated file before committing. See `backend/alembic/README.md`.
4. **Version History:** add an entry at the top of `backend/app/release_notes.json`.
   - Leave `"date": null`. The owner sets the date when it goes live.
   - Write it for admins: what changed and why, not code details.

## Branches and pull requests

- Never push to `main`. Create a branch from `main`, for example `feature/drawing-search` or `fix/dashboard-overflow`.
- Keep a pull request to one topic. Fill in the template, and add screenshots for UI changes.
- The owner reviews and merges. Merging to `main` can trigger a deploy.

## Never commit

- Real company files: ERP exports, reports, drawings (`.dwg`, `.pdf`), Excel sheets, photos.
- Databases (`*.db`) or anything under `backend/temp/`.
- Secrets: API keys, passwords, `.env` files, AWS keys. The app reads secrets from environment variables.

If something sensitive gets committed, tell the owner straight away. Deleting it in a later commit doesn't remove it from history.
