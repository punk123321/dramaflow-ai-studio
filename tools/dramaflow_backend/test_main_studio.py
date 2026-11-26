"""The Creator Studio routes of main.py, run as plain functions (same stand-ins as test_main_stubbed:
no FastAPI, no network). Run: python3 -m unittest test_main_studio"""
import base64
import shutil
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

import test_main_stubbed as tms
import test_studio_ops as tso

main = tms.main
TOKEN = main.TOKEN
SRT = tso.SRT


def wait(job_id, secs=20, final=("done", "error", "canceled")):
    end = time.time() + secs
    while time.time() < end:
        j = main.studio_status(job_id, x_app_token=TOKEN)
        if j["status"] in final:
            return j
        time.sleep(0.05)
    raise AssertionError("studio job did not finish: " + str(main.studio_status(job_id, x_app_token=TOKEN)))


def start(**kw):
    return main.studio_create(main.StudioRequest(**kw), x_app_token=TOKEN)["job_id"]


class Studio(unittest.TestCase):
    def setUp(self):
        main.JOBS.clear()
        self.dir = Path(tempfile.mkdtemp())
        self.old_dir = main.STUDIO_DIR
        main.STUDIO_DIR = self.dir / "lib"
        tms.GEMINI.update(gate=None, calls=0, reply=self.numbered)

    def tearDown(self):
        main.STUDIO_DIR = self.old_dir
        shutil.rmtree(self.dir, ignore_errors=True)
        tms.GEMINI.update(gate=None)

    @staticmethod
    def numbered(model, contents):
        out = []
        for ln in str(contents).splitlines():
            if "|" in ln and ln.split("|")[0].isdigit():
                n, t = ln.split("|", 1)
                out.append(f"{n}|MY {t}")
        return "\n".join(out)

    def put_srt(self, name="ep.srt"):
        return main.studio_upload(main.StudioUpload(name=name, data_b64=base64.b64encode(SRT.encode()).decode()), x_app_token=TOKEN)["name"]

    def test_health_and_auth(self):
        self.assertIn("studio", main.health()["features"])
        for call in (lambda: main.studio_files(x_app_token=None), lambda: main.studio_files(x_app_token="wrong"),
                     lambda: main.studio_create(main.StudioRequest(op="zip"), x_app_token=None),
                     lambda: main.studio_yt_status(x_app_token="wrong"), lambda: main.studio_delete("a.srt", x_app_token=None)):
            with self.assertRaises(tms._HTTPException) as c:
                call()
            self.assertEqual(c.exception.status_code, 401)

    def test_upload_list_zip_download_delete(self):
        name = self.put_srt()
        files = main.studio_files(x_app_token=TOKEN)
        self.assertEqual([f["name"] for f in files["files"]], [name])
        self.assertIn("youtube", files)
        j = wait(start(op="zip", files=[name], zip_name="pack"))
        self.assertEqual(j["status"], "done", j)
        self.assertEqual(j["result"]["files"], ["pack.zip"])
        self.assertEqual(j["op"], "zip")
        r = main.studio_file("pack.zip", x_app_token=TOKEN)
        self.assertTrue(r.path.endswith("pack.zip"))
        main.studio_delete("pack.zip", x_app_token=TOKEN)
        with self.assertRaises(tms._HTTPException) as c:
            main.studio_file("pack.zip", x_app_token=TOKEN)
        self.assertEqual(c.exception.status_code, 404)

    def test_bad_names_never_reach_the_disk(self):
        for bad in ("../x.srt", "a/b.srt", "x.exe"):
            with self.assertRaises(tms._HTTPException):
                main.studio_upload(main.StudioUpload(name=bad, data_b64=base64.b64encode(b"hi").decode()), x_app_token=TOKEN)
        for bad in ("../secret", "..", "a/b"):
            with self.assertRaises(tms._HTTPException):
                main.studio_file(bad, x_app_token=TOKEN)

    def test_request_checks(self):
        for kw in (dict(op="hack"), dict(op="youtube", files=["a.mp4"]), dict(op="youtube", files=["a.mp4"], confirm_rights=True, privacy="all"),
                   dict(op="translate", engine="gemini", file="a.srt")):
            with self.assertRaises(tms._HTTPException) as c:
                start(**kw)
            self.assertEqual(c.exception.status_code, 400, kw)
        with self.assertRaises(tms._HTTPException) as c:
            main.studio_status("studio_0_0000", x_app_token=TOKEN)
        self.assertEqual(c.exception.status_code, 404)
        with self.assertRaises(tms._HTTPException) as c:
            main.studio_status("ingest_0_0000", x_app_token=TOKEN)
        self.assertEqual(c.exception.status_code, 404)

    def test_translate_one_job_at_a_time_and_cancel(self):
        name = self.put_srt()
        gate = threading.Event()
        tms.GEMINI["gate"] = gate
        jid = start(op="translate", file=name, engine="gemini", gemini_key="AIza-secret-key-1234")
        with self.assertRaises(tms._HTTPException) as c:
            start(op="zip", files=[name])
        self.assertEqual(c.exception.status_code, 409)
        main.studio_control(jid, "pause", x_app_token=TOKEN)
        main.studio_control(jid, "cancel", x_app_token=TOKEN)
        gate.set()
        j = wait(jid)
        self.assertEqual(j["status"], "canceled", j)
        self.assertEqual([f["name"] for f in main.studio_files(x_app_token=TOKEN)["files"]], [name], "no half result is left")
        with self.assertRaises(tms._HTTPException) as c:
            main.studio_control(jid, "cancel", x_app_token=TOKEN)
        self.assertEqual(c.exception.status_code, 409)
        with self.assertRaises(tms._HTTPException) as c:
            main.studio_control(jid, "explode", x_app_token=TOKEN)

    def test_translate_with_gemini_and_the_key_is_not_kept(self):
        name = self.put_srt()
        j = wait(start(op="translate", file=name, engine="gemini", gemini_key="AIza-secret-key-1234", src_lang="zh"))
        self.assertEqual(j["status"], "done", j)
        out = j["result"]["files"][0]
        self.assertEqual(out, "ep_my.srt")
        text = (main.STUDIO_DIR / out).read_text(encoding="utf-8")
        self.assertIn("MY Hello", text)
        self.assertNotIn("AIza-secret-key-1234", str(j))

    def test_a_failing_gemini_key_is_masked(self):
        name = self.put_srt()
        tms.GEMINI["reply"] = lambda m, c: RuntimeError("403 API key AIza-secret-key-1234 not valid")
        j = wait(start(op="translate", file=name, engine="gemini", gemini_key="AIza-secret-key-1234"))
        self.assertEqual(j["status"], "error")
        self.assertNotIn("AIza-secret-key-1234", j["error"])

    def test_download_job_reports_speed_and_files(self):
        real_check = tso.so.check_url
        tso.so.check_url = lambda u, resolve=None: real_check(u, resolve=lambda h, p: [(0, 0, 0, "", ("93.184.216.34", 0))])
        tso.install_ytdlp()
        self.addCleanup(setattr, tso.so, "check_url", real_check)
        self.addCleanup(tso.restore, ["yt_dlp"])
        j = wait(start(op="download", url="https://www.youtube.com/watch?v=aaaaaaaaaaa", quality="720"))
        self.assertEqual(j["status"], "done", j)
        self.assertEqual(j["result"]["files"], ["Video One.mp4"])
        self.assertEqual(j["detail"].get("speed_mbs"), 2.0)

    def test_failed_job_says_why(self):
        j = wait(start(op="split", file="nope.mp4"))
        self.assertEqual(j["status"], "error")
        self.assertIn("nope.mp4", j["error"])

    def test_youtube_status_and_link_without_setup(self):
        st = main.studio_yt_status(x_app_token=TOKEN)
        self.assertIn("secret", st)
        self.assertIn("linked", st)
        with self.assertRaises(tms._HTTPException) as c:
            main.studio_yt_complete(main.YoutubePaste(pasted="http://localhost/?code=x"), x_app_token=TOKEN)
        self.assertEqual(c.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
