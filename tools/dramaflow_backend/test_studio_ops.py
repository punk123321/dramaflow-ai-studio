"""Tests of studio_ops.py. Real ffmpeg for split / CC; stand-ins for yt-dlp, deep-translator and the Google libraries
(no network here). Run: python3 -m unittest test_studio_ops"""
import base64
import os
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace as NS

import studio_core as sc
import studio_ops as so

_SAVED = {}


def remember(names):
    """Remember what sys.modules held for these names, so a test can put it back (other test files stub the same modules)."""
    for n in names:
        _SAVED.setdefault(n, sys.modules.get(n))


def restore(names):
    for n in names:
        old = _SAVED.pop(n, None)
        if old is None:
            sys.modules.pop(n, None)
        else:
            sys.modules[n] = old


FFMPEG = shutil.which("ffmpeg")
HAVE_FFMPEG = FFMPEG is not None

SRT = """1
00:00:00,500 --> 00:00:02,000
Hello

2
00:00:03,000 --> 00:00:04,000
World

3
00:00:07,000 --> 00:00:08,500
Last line
"""


def make_env(lib, canceled=lambda: False, paused=lambda: False, gemini_many=None, log=None):
    log = log if log is not None else []
    return so.Env(Path(lib), FFMPEG or "ffmpeg", lambda s, p: log.append((s, p)), canceled, paused, lambda **k: log.append(("detail", k)), gemini_many)


def make_video(path, seconds=10):
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", f"testsrc=size=160x120:rate=10:duration={seconds}",
                    "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}", "-g", "10", "-pix_fmt", "yuv420p", "-c:v", "libx264", "-c:a", "aac",
                    "-shortest", str(path)], check=True)


class Tmp(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.lib = Path(self.dir) / "lib"
        self.lib.mkdir()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class Library(Tmp):
    def test_upload_list_delete(self):
        name = so.save_upload(self.lib, "ep1.srt", base64.b64encode(SRT.encode()).decode())
        self.assertEqual(name, "ep1.srt")
        self.assertEqual(so.save_upload(self.lib, "ep1.srt", base64.b64encode(b"x").decode()), "ep1 (2).srt")
        so.save_upload(self.lib, "cover.png", base64.b64encode(b"\x89PNG....").decode())
        (self.lib / "a.mp4").write_bytes(b"0" * 10)
        (self.lib / "b.zip").write_bytes(b"0" * 10)
        (self.lib / ".tmp_hidden").write_bytes(b"0")
        kinds = {f["name"]: f["kind"] for f in so.list_library(self.lib)}
        self.assertEqual(kinds, {"ep1.srt": "srt", "ep1 (2).srt": "srt", "cover.png": "image", "a.mp4": "video", "b.zip": "zip"})
        so.delete_file(self.lib, "a.mp4")
        self.assertFalse((self.lib / "a.mp4").exists())

    def test_upload_refusals(self):
        b = base64.b64encode(b"data").decode()
        for name in ("evil.exe", "../x.srt", "a.mp4", ""):
            with self.assertRaises(ValueError, msg=name):
                so.save_upload(self.lib, name, b)
        with self.assertRaises(ValueError):
            so.save_upload(self.lib, "a.srt", "")
        with self.assertRaises(ValueError):
            so.save_upload(self.lib, "a.srt", base64.b64encode(b"0" * (so.MAX_UPLOAD_BYTES + 1)).decode())

    def test_file_path_is_a_plain_library_file(self):
        (self.lib / "a.mp4").write_bytes(b"0")
        self.assertEqual(so.file_path(self.lib, "a.mp4"), self.lib / "a.mp4")
        for bad in ("../a.mp4", "nope.mp4", "a/b.mp4", ""):
            with self.assertRaises(ValueError, msg=bad):
                so.file_path(self.lib, bad)
        with self.assertRaises(ValueError):
            so.file_path(self.lib, "a.mp4", ("srt",))

    def test_final_names(self):
        self.assertEqual(so.final_name("My Title [abc123].mp4", []), "My Title.mp4")
        self.assertEqual(so.final_name("My Title [abc123].mp4", ["My Title.mp4"]), "My Title (2).mp4")
        self.assertEqual(so.final_name("My Title [abc123].zh-Hans.srt", []), "My Title.zh-Hans.srt")
        self.assertEqual(so.final_name("plain.mp3", []), "plain.mp3")


class FakeYoutubeDL:
    """Writes what real yt-dlp would write into the folder of outtmpl, calls the hook, can fail."""
    plan = {}
    seen = []

    def __init__(self, opts):
        self.opts = opts
        FakeYoutubeDL.seen.append(opts)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def extract_info(self, url, download=True):
        spec = FakeYoutubeDL.plan.get(url, {"files": ["Video One [id1].mp4"]})
        if spec.get("raise"):
            raise RuntimeError(spec["raise"])
        folder = Path(self.opts["outtmpl"]).parent
        for hook in self.opts.get("progress_hooks", []):
            hook({"status": "downloading", "downloaded_bytes": 50, "total_bytes": 100, "speed": 2 * 1048576, "eta": 3, "filename": str(folder / "x.part")})
        for n in spec["files"]:
            (folder / n).write_bytes(b"0" * 2048)
        for hook in self.opts.get("progress_hooks", []):
            hook({"status": "finished", "filename": str(folder / "x")})
        return {}


def install_ytdlp():
    FakeYoutubeDL.plan = {}
    FakeYoutubeDL.seen = []
    remember(["yt_dlp"])
    sys.modules["yt_dlp"] = types.SimpleNamespace(YoutubeDL=FakeYoutubeDL)


class Download(Tmp):
    def setUp(self):
        super().setUp()
        install_ytdlp()
        real = so.check_url  # no DNS in the sandbox: public host names resolve to a public address, literal IPs are judged for real
        so.check_url = lambda u, resolve=None: real(u, resolve=lambda h, p: [(0, 0, 0, "", ("93.184.216.34", 0))])
        self.addCleanup(setattr, so, "check_url", real)
        self._cookies = os.environ.get("DF_COOKIES")
        os.environ["DF_COOKIES"] = str(Path(self.dir) / "no_cookies.txt")

    def tearDown(self):
        restore(["yt_dlp"])
        if self._cookies is None:
            os.environ.pop("DF_COOKIES", None)
        else:
            os.environ["DF_COOKIES"] = self._cookies
        super().tearDown()

    def req(self, **k):
        d = dict(url="https://www.youtube.com/watch?v=aaaaaaaaaaa", quality="720", speed="safe4", playlist=False, playlist_items="", sub_langs="auto", subtitles=False, auto_subs=False)
        d.update(k)
        return NS(**d)

    def test_one_video(self):
        log = []
        r = so.op_download(make_env(self.lib, log=log), self.req())
        self.assertEqual(r["files"], ["Video One.mp4"])
        self.assertTrue((self.lib / "Video One.mp4").is_file())
        self.assertEqual([p.name for p in self.lib.iterdir()], ["Video One.mp4"], "the temp folder is gone")
        o = FakeYoutubeDL.seen[0]
        self.assertTrue(o["noplaylist"])
        self.assertEqual(o["merge_output_format"], "mp4")
        self.assertNotIn("external_downloader", o, "YouTube is never downloaded with aria2c (403)")
        details = [d for t, d in [x for x in log if x[0] == "detail"]]
        self.assertTrue(any(d.get("speed_mbs") == 2.0 and d.get("eta") == 3 for d in details))
        self.assertEqual(log[-1], ("ပြီးပြီ", 100))

    def test_several_links_one_bad(self):
        FakeYoutubeDL.plan = {"https://www.youtube.com/watch?v=bbbbbbbbbbb": {"raise": "ERROR: Sign in to confirm you're not a bot"}}
        r = so.op_download(make_env(self.lib), self.req(url="https://www.youtube.com/watch?v=aaaaaaaaaaa\nhttps://www.youtube.com/watch?v=bbbbbbbbbbb"))
        self.assertEqual(r["files"], ["Video One.mp4"])
        self.assertEqual(len(r["errors"]), 1)
        self.assertIn("bbbbbbbbbbb", r["errors"][0])

    def test_all_links_bad_is_an_error(self):
        FakeYoutubeDL.plan = {"https://www.youtube.com/watch?v=aaaaaaaaaaa": {"raise": "HTTP Error 404"}}
        with self.assertRaises(RuntimeError):
            so.op_download(make_env(self.lib), self.req())

    def test_nothing_downloaded_is_an_error(self):
        FakeYoutubeDL.plan = {"https://www.youtube.com/watch?v=aaaaaaaaaaa": {"files": []}}
        with self.assertRaises(RuntimeError):
            so.op_download(make_env(self.lib), self.req())

    def test_mp3_and_subtitles_only(self):
        FakeYoutubeDL.plan = {"https://www.youtube.com/watch?v=aaaaaaaaaaa": {"files": ["Song [id1].mp3"]}}
        r = so.op_download(make_env(self.lib), self.req(quality="mp3"))
        self.assertEqual(r["files"], ["Song.mp3"])
        self.assertEqual(FakeYoutubeDL.seen[-1]["postprocessors"][0]["key"], "FFmpegExtractAudio")
        FakeYoutubeDL.plan = {"https://www.youtube.com/watch?v=aaaaaaaaaaa": {"files": ["Video One [id1].zh-Hans.srt", "Video One [id1].zh-Hans.vtt", "Video One [id1].danmaku.xml"]}}
        r = so.op_download(make_env(self.lib), self.req(quality="srt", auto_subs=True))
        self.assertEqual(r["files"], ["Video One.zh-Hans.srt"], "raw vtt / danmaku are not kept")
        o = FakeYoutubeDL.seen[-1]
        self.assertTrue(o["skip_download"] and o["writesubtitles"] and o["writeautomaticsub"])

    def test_aria2c_only_for_ordinary_sites(self):
        if not shutil.which("aria2c"):
            old = shutil.which
            so.shutil.which = lambda n, *a, **k: "/usr/bin/aria2c" if n == "aria2c" else old(n, *a, **k)
            self.addCleanup(setattr, so.shutil, "which", old)
        FakeYoutubeDL.plan = {"https://example.com/v.mp4": {"files": ["v [x].mp4"]}}
        r = so.op_download(make_env(self.lib), self.req(url="https://example.com/v.mp4", speed="fast8"))
        o = FakeYoutubeDL.seen[-1]
        self.assertEqual(o["external_downloader"], {"default": "aria2c"})
        self.assertTrue(any("aria2c 8" in n for n in r["notes"]))

    def test_cancel_and_pause(self):
        with self.assertRaises(so.Canceled):
            so.op_download(make_env(self.lib, canceled=lambda: True), self.req())
        self.assertEqual([p for p in self.lib.iterdir()], [], "nothing is left behind")
        # pause: waits until resumed
        state = {"n": 0}

        def paused():
            state["n"] += 1
            return state["n"] < 3

        log = []
        so.op_download(make_env(self.lib, paused=paused, log=log), self.req())
        self.assertTrue(any(x[0] == "detail" and x[1].get("paused") is True for x in log))

    def test_refusals(self):
        for bad in ("", "no link here", "http://127.0.0.1/x.mp4", "http://192.168.1.5/x.mp4"):
            with self.assertRaises(ValueError, msg=bad):
                so.op_download(make_env(self.lib), self.req(url=bad))
        with self.assertRaises(ValueError):
            so.op_download(make_env(self.lib), self.req(playlist_items="4;rm"))
        with self.assertRaises(ValueError):
            so.op_download(make_env(self.lib), self.req(url="\n".join(f"https://example.com/{i}.mp4" for i in range(31))))

    def test_playlist_items_and_cookies(self):
        ck = Path(self.dir) / "cookies.txt"
        ck.write_text("# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t2000000000\tSID\tabc\n")
        os.environ["DF_COOKIES"] = str(ck)
        r = so.op_download(make_env(self.lib), self.req(playlist=True, playlist_items="4-7"))
        o = FakeYoutubeDL.seen[-1]
        self.assertFalse(o["noplaylist"])
        self.assertEqual(o["playlist_items"], "4-7")
        self.assertTrue(any("cookies" in n for n in r["notes"]))
        self.assertNotIn("cookies.txt", [p.name for p in self.lib.iterdir()], "the private cookie copy is deleted")


@unittest.skipUnless(HAVE_FFMPEG, "ffmpeg missing")
class Split(Tmp):
    def test_equal_parts_with_srt(self):
        make_video(self.lib / "ep.mp4", 10)
        (self.lib / "ep.srt").write_text(SRT, encoding="utf-8")
        r = so.op_split(make_env(self.lib), NS(file="ep.mp4", split_mode="count", count=2, ranges="", srt_file="ep.srt", reencode=False))
        self.assertEqual([f for f in r["files"] if f.endswith(".mp4")], ["ep_Part01.mp4", "ep_Part02.mp4"])
        self.assertEqual([f for f in r["files"] if f.endswith(".srt")], ["ep_Part01.srt", "ep_Part02.srt"])
        for f in ("ep_Part01.mp4", "ep_Part02.mp4"):
            d = so.duration_ms(make_env(self.lib), self.lib / f)
            self.assertTrue(3000 < d < 7500, d)
        first = sc.parse_srt((self.lib / "ep_Part01.srt").read_text(encoding="utf-8"))
        second = sc.parse_srt((self.lib / "ep_Part02.srt").read_text(encoding="utf-8"))
        self.assertEqual([c[2] for c in first], ["Hello", "World"])
        self.assertEqual([c[2] for c in second], ["Last line"])
        self.assertLess(second[0][0], 3600, "part 2 starts at 0:00")
        self.assertEqual(sorted(p.name for p in self.lib.iterdir() if p.is_file()), sorted(["ep.mp4", "ep.srt"] + r["files"]))

    def test_ranges_and_errors(self):
        make_video(self.lib / "ep.mp4", 10)
        r = so.op_split(make_env(self.lib), NS(file="ep.mp4", split_mode="ranges", ranges="0:00-0:04\n0:06-0:09", count=0, srt_file="", reencode=True))
        self.assertEqual(len(r["files"]), 2)
        with self.assertRaises(ValueError):
            so.op_split(make_env(self.lib), NS(file="ep.mp4", split_mode="ranges", ranges="0:20-0:30", count=0, srt_file="", reencode=False))
        with self.assertRaises(ValueError):
            so.op_split(make_env(self.lib), NS(file="missing.mp4", split_mode="count", count=2, ranges="", srt_file="", reencode=False))

    def test_cancel_removes_the_half_file(self):
        make_video(self.lib / "ep.mp4", 6)
        with self.assertRaises(so.Canceled):
            so.op_split(make_env(self.lib, canceled=lambda: True), NS(file="ep.mp4", split_mode="count", count=2, ranges="", srt_file="", reencode=False))
        self.assertEqual([p.name for p in self.lib.iterdir()], ["ep.mp4"])


@unittest.skipUnless(HAVE_FFMPEG, "ffmpeg missing")
class Subtitles(Tmp):
    def test_soft_cc(self):
        make_video(self.lib / "ep.mp4", 4)
        (self.lib / "ep_my.srt").write_text(SRT, encoding="utf-8")
        r = so.op_subtitle_video(make_env(self.lib), NS(file="ep.mp4", srt_file="ep_my.srt", sub_mode="soft"))
        self.assertEqual(r["files"], ["ep_cc.mp4"])
        info = subprocess.run([FFMPEG, "-i", str(self.lib / "ep_cc.mp4")], capture_output=True, text=True).stderr
        self.assertIn("Subtitle", info)
        orig = subprocess.run([FFMPEG, "-i", str(self.lib / "ep.mp4")], capture_output=True, text=True).stderr
        self.assertNotIn("Subtitle", orig, "the original is not touched")

    @unittest.skipUnless(HAVE_FFMPEG and "subtitles" in subprocess.run([FFMPEG or "ffmpeg", "-hide_banner", "-filters"], capture_output=True, text=True).stdout, "ffmpeg has no libass")
    def test_hardsub(self):
        make_video(self.lib / "ep.mp4", 4)
        (self.lib / "ep_my.srt").write_text(SRT, encoding="utf-8")
        r = so.op_subtitle_video(make_env(self.lib), NS(file="ep.mp4", srt_file="ep_my.srt", sub_mode="both", font="Padauk", font_size=22))
        self.assertEqual(r["files"], ["ep_cc.mp4", "ep_hardsub.mp4"])
        self.assertTrue((self.lib / "ep_hardsub.mp4").stat().st_size > 1000)

    def test_bad_mode(self):
        make_video(self.lib / "ep.mp4", 2)
        (self.lib / "ep.srt").write_text(SRT, encoding="utf-8")
        with self.assertRaises(ValueError):
            so.op_subtitle_video(make_env(self.lib), NS(file="ep.mp4", srt_file="ep.srt", sub_mode="zoom"))


class Translate(Tmp):
    def setUp(self):
        super().setUp()
        (self.lib / "ep.srt").write_text(SRT, encoding="utf-8")

    def test_gemini_engine(self):
        seen = []

        def many(texts, lang):
            seen.append((list(texts), lang))
            return [f"MY:{t}" for t in texts]

        r = so.op_translate(make_env(self.lib, gemini_many=many), NS(file="ep.srt", engine="gemini", src_lang="zh"))
        self.assertEqual(r["files"], ["ep_my.srt"])
        out = sc.parse_srt((self.lib / "ep_my.srt").read_text(encoding="utf-8"))
        self.assertEqual([c[2] for c in out], ["MY:Hello", "MY:World", "MY:Last line"])
        self.assertEqual([c[0] for c in out], [c[0] for c in sc.parse_srt(SRT)], "times are unchanged")
        self.assertEqual(seen[0][1], "zh")
        # translating the result again does not make ep_my_my.srt
        r2 = so.op_translate(make_env(self.lib, gemini_many=many), NS(file="ep_my.srt", engine="gemini", src_lang="auto"))
        self.assertEqual(r2["files"], ["ep_my (2).srt"])

    def test_gemini_without_key(self):
        with self.assertRaises(ValueError):
            so.op_translate(make_env(self.lib), NS(file="ep.srt", engine="gemini", src_lang="auto"))

    def test_free_engine_with_a_stand_in(self):
        class GT:
            def __init__(self, source, target):
                assert target == "my"

            def translate(self, text):
                return text.upper()

        remember(["deep_translator"])
        sys.modules["deep_translator"] = types.SimpleNamespace(GoogleTranslator=GT)
        self.addCleanup(restore, ["deep_translator"])
        r = so.op_translate(make_env(self.lib), NS(file="ep.srt", engine="free", src_lang="auto"))
        out = sc.parse_srt((self.lib / r["files"][0]).read_text(encoding="utf-8"))
        self.assertEqual([c[2] for c in out], ["HELLO", "WORLD", "LAST LINE"])

    def test_total_failure_is_an_error(self):
        def many(texts, lang):
            raise RuntimeError("quota")

        with self.assertRaises(RuntimeError):
            so.op_translate(make_env(self.lib, gemini_many=many), NS(file="ep.srt", engine="gemini", src_lang="auto"))

    def test_empty_srt(self):
        (self.lib / "e.srt").write_text("nothing", encoding="utf-8")
        with self.assertRaises(ValueError):
            so.op_translate(make_env(self.lib, gemini_many=lambda t, l: t), NS(file="e.srt", engine="gemini", src_lang="auto"))


class Zip(Tmp):
    def test_zip(self):
        (self.lib / "a.mp4").write_bytes(b"1" * 100)
        (self.lib / "a.srt").write_text(SRT, encoding="utf-8")
        r = so.op_zip(make_env(self.lib), NS(files=["a.mp4", "a.srt"], zip_name="my pack"))
        self.assertEqual(r["files"], ["my pack.zip"])
        with zipfile.ZipFile(self.lib / "my pack.zip") as z:
            self.assertEqual(sorted(z.namelist()), ["a.mp4", "a.srt"])
        with self.assertRaises(ValueError):
            so.op_zip(make_env(self.lib), NS(files=[], zip_name=""))
        with self.assertRaises(ValueError):
            so.op_zip(make_env(self.lib), NS(files=["../x"], zip_name=""))


class FakeRequest:
    uploads = []
    captions = []
    thumbs = []
    fail = None


class _Exec:
    def __init__(self, val=None, chunks=None, exc=None):
        self.val, self.chunks, self.exc = val, chunks, exc

    def execute(self):
        if self.exc:
            raise self.exc
        return self.val

    def next_chunk(self):
        if self.exc:
            raise self.exc
        return None, {"id": "VID123"}


class HttpErr(Exception):
    pass


def install_google(fail=None):
    FakeRequest.uploads, FakeRequest.captions, FakeRequest.thumbs = [], [], []

    class Videos:
        def insert(self, part, body, media_body):
            FakeRequest.uploads.append(body)
            return _Exec(exc=fail)

    class Captions:
        def insert(self, part, body, media_body):
            FakeRequest.captions.append(body)
            return _Exec(val={})

    class Thumbs:
        def set(self, videoId, media_body):
            FakeRequest.thumbs.append(videoId)
            return _Exec(val={})

    svc = types.SimpleNamespace(videos=lambda: Videos(), captions=lambda: Captions(), thumbnails=lambda: Thumbs())

    class Creds:
        expired = False
        valid = True
        refresh_token = "r"

        @classmethod
        def from_authorized_user_file(cls, p, scopes):
            return cls()

        def to_json(self):
            return "{}"

    mods = {
        "google": types.ModuleType("google"),
        "google.auth": types.ModuleType("google.auth"),
        "google.auth.transport": types.ModuleType("google.auth.transport"),
        "google.auth.transport.requests": types.SimpleNamespace(Request=object),
        "google.oauth2": types.ModuleType("google.oauth2"),
        "google.oauth2.credentials": types.SimpleNamespace(Credentials=Creds),
        "googleapiclient": types.ModuleType("googleapiclient"),
        "googleapiclient.discovery": types.SimpleNamespace(build=lambda *a, **k: svc),
        "googleapiclient.errors": types.SimpleNamespace(HttpError=HttpErr),
        "googleapiclient.http": types.SimpleNamespace(MediaFileUpload=lambda *a, **k: object()),
    }
    remember(mods)
    sys.modules.update(mods)
    return list(mods)


class YouTube(Tmp):
    def setUp(self):
        super().setUp()
        self.mods = install_google()
        (self.lib / "ep.mp4").write_bytes(b"0" * 3000)
        (self.lib / "ep_my.srt").write_text(SRT, encoding="utf-8")
        (self.lib / "cover.jpg").write_bytes(b"\xff\xd8" + b"0" * 100)
        self.token = Path(self.dir) / "tok.json"
        self.token.write_text("{}")
        self._old = {k: os.environ.get(k) for k in ("DF_YT_TOKEN", "DF_YT_CLIENT_SECRET")}
        os.environ["DF_YT_TOKEN"] = str(self.token)

    def tearDown(self):
        restore(self.mods)
        for k, v in self._old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        super().tearDown()

    def req(self, **k):
        d = dict(files=["ep.mp4"], confirm_rights=True, privacy="private", title_template="{name} #{n}", description="desc", tags="a, b", category="entertainment",
                 kids=False, thumbnail="", upload_cc=False)
        d.update(k)
        return NS(**d)

    def test_upload_is_private_with_the_rights_box(self):
        r = so.op_youtube(make_env(self.lib), self.req())
        self.assertEqual(r["links"][0]["watch"], "https://youtu.be/VID123")
        body = FakeRequest.uploads[0]
        self.assertEqual(body["status"]["privacyStatus"], "private")
        self.assertFalse(body["status"]["selfDeclaredMadeForKids"])
        self.assertEqual(body["snippet"]["tags"], ["a", "b"])
        self.assertEqual(body["snippet"]["categoryId"], "24")

    def test_refuses_without_confirmation_or_with_bad_input(self):
        with self.assertRaises(ValueError):
            so.op_youtube(make_env(self.lib), self.req(confirm_rights=False))
        self.assertEqual(FakeRequest.uploads, [])
        with self.assertRaises(ValueError):
            so.op_youtube(make_env(self.lib), self.req(privacy="everyone"))
        with self.assertRaises(ValueError):
            so.op_youtube(make_env(self.lib), self.req(files=[]))
        with self.assertRaises(ValueError):
            so.op_youtube(make_env(self.lib), self.req(files=["ep_my.srt"]))
        self.token.unlink()
        with self.assertRaises(ValueError):
            so.op_youtube(make_env(self.lib), self.req())

    def test_thumbnail_and_cc(self):
        r = so.op_youtube(make_env(self.lib), self.req(thumbnail="cover.jpg", upload_cc=True))
        self.assertEqual(FakeRequest.thumbs, ["VID123"])
        self.assertEqual(FakeRequest.captions[0]["snippet"]["language"], "my")
        self.assertIn("CC OK", r["links"][0]["note"])

    def test_cc_missing_is_a_note_not_a_failure(self):
        (self.lib / "ep_my.srt").unlink()
        r = so.op_youtube(make_env(self.lib), self.req(upload_cc=True))
        self.assertIn("မတွေ့", r["links"][0]["note"])

    def test_failure_is_reported(self):
        install_google(fail=HttpErr("quotaExceeded"))
        with self.assertRaises(RuntimeError) as c:
            so.op_youtube(make_env(self.lib), self.req())
        self.assertTrue(str(c.exception))

    def test_status_and_login_without_a_secret(self):
        os.environ["DF_YT_CLIENT_SECRET"] = str(Path(self.dir) / "nope.json")
        st = so.yt_status()
        self.assertTrue(st["linked"])
        so.yt_unlink()
        self.assertFalse(so.yt_status()["linked"])
        if so.yt_secret_path() is None:
            self.assertFalse(so.yt_status()["secret"])
            with self.assertRaises(ValueError):
                so.yt_auth_link()
        with self.assertRaises(ValueError):
            so.yt_auth_complete("http://localhost/?code=abc")


class NoEvasionFilters(unittest.TestCase):
    def test_no_editing_that_changes_the_picture_or_sound(self):
        src = (Path(__file__).parent / "studio_ops.py").read_text(encoding="utf-8").lower() + (Path(__file__).parent / "studio_core.py").read_text(encoding="utf-8").lower()
        for bad in ("hflip", "vflip", "zoompan", "asetrate", "atempo", "eq=brightness", "hue="):
            self.assertNotIn(bad, src, bad)


if __name__ == "__main__":
    unittest.main()
