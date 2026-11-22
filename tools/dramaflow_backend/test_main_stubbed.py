"""Runs main.py's own code (jobs, voice, tempo, token, selftest) WITHOUT the
real fastapi, edge-tts or Gemini: small stand-ins are put in sys.modules.
This proves the logic of main.py; it does not prove that FastAPI routes,
Edge TTS or Gemini behave as assumed (that needs the real backend running).

Run:  python3 -m unittest test_main_stubbed   (needs pydantic and ffmpeg)
"""
import asyncio
import os
import struct
import sys
import tempfile
import threading
import time
import types
import unittest
import wave
from pathlib import Path

os.environ["APP_TOKEN"] = "test-token-123456"

# ---- stand-ins -------------------------------------------------------------
SPOKEN = []  # the text each fake voice call received
GEMINI = {"reply": None, "gate": None, "calls": 0}


class _HTTPException(Exception):
    def __init__(self, status_code=500, detail=""):
        super().__init__(detail)
        self.status_code, self.detail = status_code, detail


class _App:
    def __init__(self, *a, **k):
        pass

    def add_middleware(self, *a, **k):
        pass

    def get(self, *a, **k):
        return lambda f: f

    post = get


def _install():
    fa = types.ModuleType("fastapi")
    fa.FastAPI, fa.HTTPException, fa.Header = _App, _HTTPException, lambda default=None: default
    cors = types.ModuleType("fastapi.middleware.cors")
    cors.CORSMiddleware = object
    mid = types.ModuleType("fastapi.middleware")
    resp = types.ModuleType("fastapi.responses")

    class FileResponse:
        def __init__(self, path, media_type=None, filename=None):
            self.path, self.media_type = path, media_type

    class Response:
        def __init__(self, content=b"", media_type=None):
            self.content, self.media_type = content, media_type

    resp.FileResponse, resp.Response = FileResponse, Response
    sys.modules.update({"fastapi": fa, "fastapi.middleware": mid, "fastapi.middleware.cors": cors, "fastapi.responses": resp})

    et = types.ModuleType("edge_tts")

    class Communicate:
        def __init__(self, text, voice, rate="+0%"):
            self.text, self.voice, self.rate = text, voice, rate

        async def save(self, path):
            SPOKEN.append(self.text)
            n = int(24000 * 0.01 * len(self.text))  # 10 ms per character
            with wave.open(str(path), "wb") as w:  # a WAV inside the .mp3 name; ffmpeg reads by content
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(24000)
                w.writeframes(struct.pack("<h", 0) * n)

    et.Communicate = Communicate
    sys.modules["edge_tts"] = et

    class _Kw:
        def __init__(self, *a, **k):
            self.a, self.k = a, k

        @staticmethod
        def from_bytes(**k):
            return _Kw(**k)

    types_mod = types.ModuleType("google.genai.types")
    for name in ("Part", "FileData", "VideoMetadata", "GenerateContentConfig"):
        setattr(types_mod, name, type(name, (_Kw,), {"from_bytes": staticmethod(lambda **k: _Kw(**k))}))
    genai = types.ModuleType("google.genai")

    class _Models:
        def generate_content(self, model, contents, config=None):
            GEMINI["calls"] += 1
            if GEMINI["gate"]:
                GEMINI["gate"].wait(5)
            r = GEMINI["reply"](model, contents)
            if isinstance(r, Exception):
                raise r
            return types.SimpleNamespace(text=r)

    class Client:
        def __init__(self, api_key=None):
            self.api_key, self.models = api_key, _Models()

    genai.Client, genai.types = Client, types_mod
    google = types.ModuleType("google")
    google.genai = genai
    sys.modules.update({"google": google, "google.genai": genai, "google.genai.types": types_mod})


_install()
import main  # noqa: E402


def _reply(model, contents):
    prompt = contents[-1] if isinstance(contents[-1], str) else ""
    return "=== PART 1 ===\nစာတစ်ခု 😀 25 နှစ်\n=== PART 2 ===\n" + "က" * 100


def _wait(job_id, secs=20):
    end = time.time() + secs
    while time.time() < end:
        j = main.job_status(job_id, x_app_token=main.TOKEN)
        if j["status"] in ("done", "error"):
            return j
        time.sleep(0.05)
    raise AssertionError("job did not finish")


def _req(**kw):
    base = dict(gemini_key="AIza-secret-key-1234", voice="my-MM-ThihaNeural",
                groups=[main.Group(first=1, last=2, prompt="P", part_ms=[5000, 800])])
    base.update(kw)
    return main.RecapRequest(**base)


class MainTests(unittest.TestCase):
    def setUp(self):
        SPOKEN.clear()
        GEMINI.update(reply=_reply, gate=None, calls=0)
        main.JOBS.clear()
        main.run_job.__globals__["time"] = time  # real sleep is not patched; retries are not hit here

    def test_token(self):
        with self.assertRaises(main.HTTPException) as c:
            main.create_job(_req(), x_app_token="wrong")
        self.assertEqual(c.exception.status_code, 401)
        with self.assertRaises(main.HTTPException):
            main.job_status("recap_1_abcd", x_app_token=None)

    def test_empty_groups(self):
        with self.assertRaises(main.HTTPException) as c:
            main.create_job(_req(groups=[]), x_app_token=main.TOKEN)
        self.assertEqual(c.exception.status_code, 400)

    def test_full_job_voice_cleaned_and_fitted(self):
        jid = main.create_job(_req(), x_app_token=main.TOKEN)["job_id"]
        j = _wait(jid)
        self.assertEqual(j["status"], "done", j.get("error"))
        self.assertEqual([p["n"] for p in j["parts"]], [1, 2])
        # the voice got the cleaned text: no emoji, small number spelled
        self.assertNotIn("😀", SPOKEN[0])
        self.assertIn("နှစ်ဆယ့်ငါး", SPOKEN[0])
        p1, p2 = j["parts"]
        self.assertEqual(p1["target_ms"], 5000)
        self.assertTrue(p1["audio_url"].endswith("/audio/1.wav"))
        self.assertNotIn("audio_file", p1)
        # part 2: 100 chars = 1000 ms for an 800 ms part -> sped up to about 800-870 ms
        self.assertLessEqual(p2["audio_ms"], 1000 / 1.15 + 40)
        self.assertGreaterEqual(p2["audio_ms"], 700)
        # the audio endpoint serves the file; bad ids do not
        r = main.audio(jid, 1, x_app_token=main.TOKEN)
        self.assertTrue(Path(r.path).exists())
        with self.assertRaises(main.HTTPException):
            main.audio("../x", 1, x_app_token=main.TOKEN)
        with self.assertRaises(main.HTTPException):
            main.audio(jid, 9, x_app_token=main.TOKEN)

    def test_second_context_request(self):
        seen = []

        def reply(model, contents):
            seen.append(contents[-1])
            n = len(seen)
            return f"=== PART {n} ===\nစာ{n}"

        GEMINI["reply"] = reply
        gs = [main.Group(first=1, last=1, prompt="P1"), main.Group(first=2, last=2, prompt="P2")]
        old = main.run_recap

        def fast(groups, g, t, p, **k):
            return old(groups, g, t, p, gap_seconds=0, **k)

        main.run_recap = fast
        try:
            jid = main.create_job(_req(groups=gs, voice=""), x_app_token=main.TOKEN)["job_id"]
            j = _wait(jid)
        finally:
            main.run_recap = old
        self.assertEqual(j["status"], "done", j.get("error"))
        self.assertEqual(seen[0], "P1")
        self.assertIn("CONTEXT", seen[1])
        self.assertIn("စာ1", seen[1])

    def test_busy_and_error_hides_key(self):
        gate = threading.Event()
        GEMINI.update(gate=gate, reply=lambda m, c: RuntimeError("bad key AIza-secret-key-1234 rejected"))
        jid = main.create_job(_req(voice=""), x_app_token=main.TOKEN)["job_id"]
        with self.assertRaises(main.HTTPException) as c:
            main.create_job(_req(voice=""), x_app_token=main.TOKEN)
        self.assertEqual(c.exception.status_code, 409)
        gate.set()
        j = _wait(jid)
        self.assertEqual(j["status"], "error")
        self.assertNotIn("AIza-secret-key-1234", str(j))

    def test_finished_job_survives_a_restart(self):
        jid = main.create_job(_req(voice=""), x_app_token=main.TOKEN)["job_id"]
        first = _wait(jid)
        self.assertEqual(first["status"], "done")
        main.JOBS.clear()  # what a restarted web process looks like
        again = main.job_status(jid, x_app_token=main.TOKEN)
        self.assertEqual(again["parts"], first["parts"])
        with self.assertRaises(main.HTTPException):
            main.job_status("recap_1_ffff", x_app_token=main.TOKEN)

    def test_fallback_model(self):
        used = []

        def reply(model, contents):
            used.append(model)
            if model == "old-model":
                return RuntimeError("404 NOT_FOUND no such model")
            return "=== PART 1 ===\nစာ"

        GEMINI["reply"] = reply
        gs = [main.Group(first=1, last=1, prompt="P")]
        jid = main.create_job(_req(groups=gs, voice="", gemini_model="old-model", gemini_fallback="new-model"), x_app_token=main.TOKEN)["job_id"]
        j = _wait(jid)
        self.assertEqual(j["status"], "done", j.get("error"))
        self.assertEqual(used, ["old-model", "new-model"])
        # without a fallback the 404 is reported and nothing is retried
        used.clear()
        main.JOBS.clear()
        jid = main.create_job(_req(groups=gs, voice="", gemini_model="old-model"), x_app_token=main.TOKEN)["job_id"]
        self.assertEqual(_wait(jid)["status"], "error")
        self.assertEqual(used, ["old-model"])

    def test_quota_waits_then_falls_back(self):
        used, slept = [], []

        def reply(model, contents):
            used.append(model)
            return RuntimeError("429 RESOURCE_EXHAUSTED") if model == "a" else "=== PART 1 ===\nစာ"

        GEMINI["reply"] = reply
        real = main.time.sleep
        main.time.sleep = lambda s: slept.append(s)
        try:
            jid = main.create_job(_req(groups=[main.Group(first=1, last=1, prompt="P")], voice="", gemini_model="a", gemini_fallback="b"), x_app_token=main.TOKEN)["job_id"]
            j = _wait(jid)
        finally:
            main.time.sleep = real
        self.assertEqual(j["status"], "done", j.get("error"))
        self.assertEqual(used, ["a", "a", "a", "b"])  # three tries on a, then b
        self.assertEqual([x for x in slept if x >= 1][:2], [25, 50])

    def test_tts_once(self):
        r = main.tts_once(main.TtsRequest(text="မင်္ဂလာပါ 😀 3 ယောက်"), x_app_token=main.TOKEN)
        self.assertEqual(r.media_type, "audio/wav")
        self.assertTrue(r.content.startswith(b"RIFF"))
        self.assertNotIn("😀", SPOKEN[-1])
        with self.assertRaises(main.HTTPException) as c:
            main.tts_once(main.TtsRequest(text="  "), x_app_token=main.TOKEN)
        self.assertEqual(c.exception.status_code, 400)

    def test_selftest_ok_and_hints(self):
        GEMINI["reply"] = lambda m, c: "OK"
        r = main.selftest(main.SelfTestRequest(gemini_key="AIza-secret-key-1234"), x_app_token=main.TOKEN)
        by = {c["id"]: c for c in r["checks"]}
        self.assertTrue(by["ffmpeg"]["ok"] and by["edge_tts"]["ok"] and by["gemini"]["ok"], r)
        GEMINI["reply"] = lambda m, c: RuntimeError("404 NOT_FOUND model AIza-secret-key-1234")
        r = main.selftest(main.SelfTestRequest(gemini_key="AIza-secret-key-1234", gemini_model="old"), x_app_token=main.TOKEN)
        g = {c["id"]: c for c in r["checks"]}["gemini"]
        self.assertFalse(g["ok"])
        self.assertIn("model", g["note"])
        self.assertNotIn("AIza-secret-key-1234", str(r))
        GEMINI["reply"] = lambda m, c: RuntimeError("503 UNAVAILABLE high demand")
        r = main.selftest(main.SelfTestRequest(gemini_key="AIza-secret-key-1234"), x_app_token=main.TOKEN)
        self.assertIn("လူသုံးများ", {c["id"]: c for c in r["checks"]}["gemini"]["note"])
        GEMINI["reply"] = lambda m, c: RuntimeError("429 RESOURCE_EXHAUSTED")
        r = main.selftest(main.SelfTestRequest(gemini_key="AIza-secret-key-1234"), x_app_token=main.TOKEN)
        self.assertIn("quota", {c["id"]: c for c in r["checks"]}["gemini"]["note"])
        r = main.selftest(main.SelfTestRequest(gemini_key=""), x_app_token=main.TOKEN)
        self.assertFalse({c["id"]: c for c in r["checks"]}["gemini"]["ok"])


if __name__ == "__main__":
    unittest.main()
