"""Drawing register API against a throwaway database and file store.

Run: python -m unittest discover -s tests
"""
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.db.models  # noqa: F401 — registers models
from app.db.database import Base, get_db
from app.db.models import AuthUser, Project
from app.main_api import app
from app.services import drawing_service as svc
from app.services.auth_deps import get_current_user, get_current_user_modules
from app.services.modules import MODULE_DRAWING_REGISTER

SAMPLE_DWG = Path(os.getenv("SAMPLE_DWG") or
                  Path.home() / "Downloads" / "20251017_JWC_FOURTH FLOOR FRAMING PLAN & BEAM DETAILS.dwg")
PDF = b"%PDF-1.4\n%test\n"


class DrawingRegisterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls._env = os.environ.get("DRAWINGS_DIR")
        os.environ["DRAWINGS_DIR"] = str(Path(cls.tmp) / "files")
        engine = create_engine(f"sqlite:///{cls.tmp}/test.db", connect_args={"check_same_thread": False})
        Base.metadata.create_all(engine)
        cls.Session = sessionmaker(bind=engine, autoflush=False)
        cls._session_local = svc.SessionLocal
        svc.SessionLocal = cls.Session  # background preview task

        def db():
            s = cls.Session()
            try:
                yield s
            finally:
                s.close()

        user = AuthUser(id=1, email="tester@example.com", display_name="Tester", role_id=1)
        app.dependency_overrides[get_db] = db
        app.dependency_overrides[get_current_user] = lambda: user
        app.dependency_overrides[get_current_user_modules] = lambda: [MODULE_DRAWING_REGISTER]
        with cls.Session() as s:
            s.add_all([Project(id=1, name="Tower A"), Project(id=2, name="Tower B")])
            s.commit()
        cls.client = TestClient(app)

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.clear()
        svc.SessionLocal = cls._session_local
        if cls._env is None:
            os.environ.pop("DRAWINGS_DIR", None)
        else:
            os.environ["DRAWINGS_DIR"] = cls._env
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def _new(self, number, project=1, name="plan.pdf", data=PDF, **form):
        fields = {"number": number, "title": "Ground Floor Plan", "discipline": "Architectural", **form}
        return self.client.post(f"/api/drawing-register/projects/{project}/drawings",
                                data=fields, files={"file": (name, data)})

    def test_new_drawing_then_revision(self):
        r = self._new("gbe-ar-101")
        self.assertEqual(r.status_code, 201, r.text)
        d = r.json()
        self.assertEqual(d["number"], "GBE-AR-101")
        self.assertEqual([x["rev"] for x in d["revisions"]], ["R0"])
        self.assertEqual(d["revisions"][0]["remarks"], "Issued for construction")

        r = self.client.post(f"/api/drawing-register/drawings/{d['id']}/revisions",
                             data={"remarks": "Lobby revised"}, files={"file": ("plan-r1.pdf", PDF + b"x")})
        self.assertEqual(r.status_code, 201, r.text)
        revs = r.json()["revisions"]
        self.assertEqual([(x["rev"], x["status"]) for x in revs], [("R1", "current"), ("R0", "superseded")])
        self.assertEqual(revs[0]["remarks"], "Lobby revised")

        listed = self.client.get("/api/drawing-register/projects/1/drawings").json()
        self.assertIn("GBE-AR-101", [x["number"] for x in listed])

        old = self.client.get(f"/api/drawing-register/revisions/{revs[1]['id']}/file")
        self.assertEqual(old.content, PDF)
        self.assertTrue(old.headers["content-disposition"].startswith("attachment"))
        cur = self.client.get(f"/api/drawing-register/revisions/{revs[0]['id']}/file?inline=true")
        self.assertEqual(cur.content, PDF + b"x")
        self.assertTrue(cur.headers["content-disposition"].startswith("inline"))
        self.assertEqual(cur.headers["content-type"], "application/pdf")

    def test_number_unique_per_project(self):
        self.assertEqual(self._new("GBE-ST-201").status_code, 201)
        dup = self._new("gbe-st-201")
        self.assertEqual(dup.status_code, 409)
        self.assertIn("already exists", dup.json()["detail"])
        self.assertEqual(self._new("GBE-ST-201", project=2).status_code, 201)

    def test_rejects_bad_files(self):
        self.assertEqual(self._new("X-1", name="sheet.xlsx").status_code, 422)
        self.assertEqual(self._new("X-2", data=b"").status_code, 422)
        self.assertEqual(self._new("X-3", discipline="Landscape").status_code, 422)
        self.assertEqual(self._new("X-4", project=99).status_code, 404)

    def test_rejects_oversize(self):
        limit = svc.MAX_UPLOAD_BYTES
        svc.MAX_UPLOAD_BYTES = 10
        try:
            self.assertEqual(self._new("X-5", data=b"%PDF" + b"0" * 20).status_code, 413)
        finally:
            svc.MAX_UPLOAD_BYTES = limit
        # nothing half-saved
        self.assertNotIn("X-5", [x["number"] for x in self.client.get("/api/drawing-register/projects/1/drawings").json()])

    @unittest.skipUnless(shutil.which("dwg2dxf") and SAMPLE_DWG.exists(), "needs dwg2dxf and the sample DWG")
    def test_dwg_preview(self):
        r = self._new("GBE-ST-300", name=SAMPLE_DWG.name, data=SAMPLE_DWG.read_bytes(), discipline="Structural")
        self.assertEqual(r.status_code, 201, r.text)
        rev = r.json()["revisions"][0]
        self.assertEqual(rev["fmt"], "DWG")
        # TestClient runs background tasks before returning, so the preview is done
        d = self.client.get(f"/api/drawing-register/drawings/{r.json()['id']}").json()
        self.assertEqual(d["revisions"][0]["preview_status"], "ready")
        png = self.client.get(f"/api/drawing-register/revisions/{rev['id']}/preview")
        self.assertEqual(png.status_code, 200)
        self.assertTrue(png.content.startswith(b"\x89PNG"))


    @unittest.skipUnless(shutil.which("dwg2dxf") and SAMPLE_DWG.exists(), "needs dwg2dxf and the sample DWG")
    def test_dwg_preview_time_limit(self):
        limit = svc.PREVIEW_TIMEOUT_S
        svc.PREVIEW_TIMEOUT_S = 0.5
        try:
            r = self._new("GBE-ST-301", name=SAMPLE_DWG.name, data=SAMPLE_DWG.read_bytes(), discipline="Structural")
        finally:
            svc.PREVIEW_TIMEOUT_S = limit
        rev = r.json()["revisions"][0]
        d = self.client.get(f"/api/drawing-register/drawings/{r.json()['id']}").json()
        self.assertEqual(d["revisions"][0]["preview_status"], "failed")
        self.assertEqual(self.client.get(f"/api/drawing-register/revisions/{rev['id']}/preview").status_code, 404)
        # the drawing itself is still stored and downloadable
        self.assertEqual(self.client.get(f"/api/drawing-register/revisions/{rev['id']}/file").content,
                         SAMPLE_DWG.read_bytes())

if __name__ == "__main__":
    unittest.main()
