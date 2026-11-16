"""Version history API: admin only, valid entries, not-yet-live first then newest first."""
import re
import unittest

from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main_api import app
from app.routers.release_notes import load_notes
from app.services.auth_deps import require_admin


class ReleaseNotesTests(unittest.TestCase):
    def tearDown(self):
        app.dependency_overrides.clear()

    def test_entries_are_valid_and_ordered(self):
        notes = load_notes()
        self.assertTrue(notes)
        dates = [n["date"] for n in notes]
        for n in notes:
            self.assertTrue(n["title"] and n["summary"])
            self.assertTrue(n["date"] is None or re.fullmatch(r"\d{4}-\d{2}-\d{2}", n["date"]), n["date"])
            for s in n["sections"]:
                self.assertTrue(s["heading"] and s["points"])
        live = [d for d in dates if d]
        self.assertEqual(dates[: len(dates) - len(live)], [None] * (len(dates) - len(live)))
        self.assertEqual(live, sorted(live, reverse=True))

    def test_admin_can_read(self):
        app.dependency_overrides[require_admin] = lambda: object()
        res = TestClient(app).get("/api/release-notes")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(len(res.json()), len(load_notes()))

    def test_non_admin_refused(self):
        def deny():
            raise HTTPException(403, "Only administrators can perform this action.")
        app.dependency_overrides[require_admin] = deny
        self.assertEqual(TestClient(app).get("/api/release-notes").status_code, 403)

    def test_requires_login(self):
        self.assertEqual(TestClient(app).get("/api/release-notes").status_code, 401)


if __name__ == "__main__":
    unittest.main()
