"""Tests of ingest_core.py (no network). Run: python3 -m unittest test_ingest_core"""
import unittest

import ingest_core as ic


def fake_resolve(ip):
    return lambda host, port: [(0, 0, 0, "", (ip, 0))]


class ExtractUrl(unittest.TestCase):
    def test_share_text_with_words(self):
        t = "78 【绝世唐门 第12集 - 小红书】 😆 abc 😆 http://xhslink.com/a/AbC123，复制本条信息"
        self.assertEqual(ic.extract_url(t), "http://xhslink.com/a/AbC123")

    def test_tiktok_share(self):
        self.assertEqual(ic.extract_url("Check this https://vm.tiktok.com/ZMabc123/ now"), "https://vm.tiktok.com/ZMabc123/")

    def test_trailing_punctuation(self):
        self.assertEqual(ic.extract_url("see https://youtu.be/abc123."), "https://youtu.be/abc123")

    def test_none(self):
        self.assertEqual(ic.extract_url("no link here"), "")
        self.assertEqual(ic.extract_url(""), "")
        self.assertEqual(ic.extract_url(None), "")


class Cookies(unittest.TestCase):
    OK = "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t1893456000\tSID\tabc\n"

    def test_good_file(self):
        self.assertEqual(ic.cookies_problem(self.OK), "")
        self.assertEqual(ic.cookies_problem("\ufeff" + self.OK), "")
        self.assertEqual(ic.cookies_problem("#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc"), "")

    def test_problems(self):
        self.assertIn("အလွတ်", ic.cookies_problem("  \n"))
        self.assertIn("JSON", ic.cookies_problem('[{"name":"SID"}]'))
        self.assertIn("JSON", ic.cookies_problem('{"a":1}'))
        self.assertIn("tab", ic.cookies_problem("# Netscape\njust some text without tabs"))
        self.assertIn("ကြီးလွန်း", ic.cookies_problem(self.OK + ("x" * (ic.MAX_COOKIE_BYTES + 1))))

    def test_note_when_other_website(self):
        self.assertEqual(ic.cookie_note(self.OK, "youtube"), "")
        self.assertIn("tiktok.com", ic.cookie_note(self.OK, "tiktok"))
        self.assertEqual(ic.cookie_note(self.OK, "other"), "")


class Subtitles(unittest.TestCase):
    def test_chinese_first_then_english(self):
        self.assertEqual(ic.pick_subtitle(["v.mp4", "v.en.srt", "v.zh-Hans.srt"]), ("v.zh-Hans.srt", "zh-Hans"))
        self.assertEqual(ic.pick_subtitle(["v.en.srt", "v.my.srt"]), ("v.en.srt", "en"))
        self.assertEqual(ic.pick_subtitle(["v.fr.srt", "v.zh-Hant-HK.srt"]), ("v.zh-Hant-HK.srt", "zh-Hant-HK"))
        self.assertEqual(ic.pick_subtitle(["v.fr.srt"]), ("v.fr.srt", "fr"))

    def test_danmaku_and_other_files_are_not_subtitles(self):
        self.assertEqual(ic.pick_subtitle(["v.danmaku.srt", "v.live_chat.srt", "v.zh.vtt", "v.mp4"]), (None, ""))
        self.assertEqual(ic.pick_subtitle([]), (None, ""))

    def test_clean_srt(self):
        self.assertEqual(ic.clean_srt("\ufeff1\n00:00:01,000 --> 00:00:02,000\nhi\n"), "1\n00:00:01,000 --> 00:00:02,000\nhi")
        self.assertEqual(ic.clean_srt("nothing here"), "")
        self.assertEqual(ic.clean_srt("-->" + "x" * (ic.MAX_SRT_CHARS + 1)), "")
        self.assertEqual(ic.clean_srt(None), "")

    def test_run_ingest_passes_srt_and_cookie_flag(self):
        got = {"path": "/tmp/v.mp4", "title": "T", "duration_ms": 1000, "srt": "1\n00:00:01,000 --> 00:00:02,000\nhi", "srt_lang": "zh-Hans", "cookies": True}
        out = ic.run_ingest("https://142.250.1.1/v", lambda u, p: got, lambda p, m: ("uri", m), lambda s, p: None)
        self.assertEqual(out["srt_lang"], "zh-Hans")
        self.assertIn("hi", out["srt"])
        self.assertTrue(out["cookies"])
        got2 = {"path": "/tmp/v.mp4", "title": "T", "duration_ms": 1000, "srt": "garbage"}
        out2 = ic.run_ingest("https://142.250.1.1/v", lambda u, p: got2, lambda p, m: ("uri", m), lambda s, p: None)
        self.assertNotIn("srt", out2)
        self.assertFalse(out2["cookies"])


class Classify(unittest.TestCase):
    def test_kinds(self):
        self.assertEqual(ic.classify("https://www.youtube.com/watch?v=x"), "youtube")
        self.assertEqual(ic.classify("https://youtu.be/x"), "youtube")
        self.assertEqual(ic.classify("https://vm.tiktok.com/x"), "tiktok")
        self.assertEqual(ic.classify("http://xhslink.com/a/x"), "rednote")
        self.assertEqual(ic.classify("https://www.xiaohongshu.com/explore/1"), "rednote")
        self.assertEqual(ic.classify("https://v.douyin.com/x"), "douyin")
        self.assertEqual(ic.classify("https://b23.tv/x"), "bilibili")
        self.assertEqual(ic.classify("https://example.com/v.mp4"), "other")

    def test_lookalike_host_is_other(self):
        self.assertEqual(ic.classify("https://notyoutube.com/x"), "other")
        self.assertEqual(ic.classify("https://youtube.com.evil.example/x"), "other")


class CheckUrl(unittest.TestCase):
    def test_public_ok(self):
        self.assertEqual(ic.check_url("https://youtu.be/x", fake_resolve("142.250.1.1")), (True, ""))

    def test_scheme(self):
        self.assertFalse(ic.check_url("file:///etc/passwd")[0])
        self.assertFalse(ic.check_url("ftp://x.example/a")[0])
        self.assertFalse(ic.check_url("youtube.com/x")[0])
        self.assertFalse(ic.check_url("")[0])

    def test_private_literals(self):
        for u in ("http://127.0.0.1/x", "http://localhost:8000/x", "http://10.0.0.5/x", "http://192.168.1.1/x", "http://169.254.169.254/latest", "http://[::1]/x"):
            ok, _ = ic.check_url(u, fake_resolve("127.0.0.1"))
            self.assertFalse(ok, u)

    def test_name_that_resolves_inside(self):
        self.assertFalse(ic.check_url("https://evil.example/x", fake_resolve("10.1.2.3"))[0])

    def test_unresolvable(self):
        def boom(h, p):
            raise OSError("no")

        ok, why = ic.check_url("https://nowhere.invalid/x", boom)
        self.assertFalse(ok)
        self.assertIn("website", why)


class Small(unittest.TestCase):
    def test_mime(self):
        self.assertEqual(ic.mime_for("/a/v.mp4"), "video/mp4")
        self.assertEqual(ic.mime_for("v.WEBM"), "video/webm")
        self.assertIsNone(ic.mime_for("v.mkv"))
        self.assertIsNone(ic.mime_for("v"))

    def test_ffmpeg_duration(self):
        self.assertEqual(ic.parse_ffmpeg_duration("  Duration: 00:12:34.56, start: 0.0"), 754560)
        self.assertEqual(ic.parse_ffmpeg_duration("Duration: 01:00:00.5, x"), 3600500)
        self.assertEqual(ic.parse_ffmpeg_duration("Duration: N/A"), 0)
        self.assertEqual(ic.parse_ffmpeg_duration(""), 0)

    def test_hint(self):
        self.assertIn("YouTube", ic.ingest_hint("ERROR: Sign in to confirm you're not a bot"))
        self.assertIn("private", ic.ingest_hint("This video is private"))
        self.assertIn("link ပုံစံ", ic.ingest_hint("ERROR: Unsupported URL: https://x"))
        self.assertIn("Colab", ic.ingest_hint("HTTP Error 429: Too Many Requests"))
        self.assertIn("ဖိုင်ကို ရွေးတင်", ic.ingest_hint("HTTP Error 403: Forbidden", "tiktok"))
        self.assertEqual(ic.ingest_hint("something odd"), "")


class RunIngest(unittest.TestCase):
    URL = "https://youtu.be/abc"

    def setUp(self):
        self._orig = ic.socket.getaddrinfo
        ic.socket.getaddrinfo = fake_resolve("142.250.1.1")
        # check_url has resolve bound at definition time, so patch its default too
        self._defaults = ic.check_url.__defaults__
        ic.check_url.__defaults__ = (fake_resolve("142.250.1.1"),)

    def tearDown(self):
        ic.socket.getaddrinfo = self._orig
        ic.check_url.__defaults__ = self._defaults

    def test_happy_path_and_progress(self):
        seen = []

        def download(url, pct):
            pct(0)
            pct(50)
            pct(100)
            return {"path": "/t/v.mp4", "title": "T" * 300, "duration_ms": 61000}

        def upload(path, mime):
            self.assertEqual((path, mime), ("/t/v.mp4", "video/mp4"))
            return "https://files/abc", mime

        r = ic.run_ingest(self.URL, download, upload, lambda s, p: seen.append(p))
        self.assertEqual(r["file_uri"], "https://files/abc")
        self.assertEqual(r["mime"], "video/mp4")
        self.assertEqual(r["duration_ms"], 61000)
        self.assertEqual(r["source"], "youtube")
        self.assertEqual(len(r["title"]), 120)
        self.assertEqual(seen, sorted(seen))  # progress never goes back
        self.assertEqual(seen[-1], 100)

    def test_bad_url_never_downloads(self):
        called = []
        with self.assertRaises(ValueError):
            ic.run_ingest("http://127.0.0.1/x", lambda u, p: called.append(1), lambda a, b: ("", ""), lambda s, p: None)
        self.assertEqual(called, [])

    def test_unsupported_format_never_uploads(self):
        up = []
        with self.assertRaises(ValueError) as cm:
            ic.run_ingest(self.URL, lambda u, p: {"path": "/t/v.mkv"}, lambda a, b: up.append(1) or ("", ""), lambda s, p: None)
        self.assertIn("mkv", str(cm.exception))
        self.assertEqual(up, [])

    def test_download_error_passes_through(self):
        def download(u, p):
            raise RuntimeError("Sign in to confirm you're not a bot")

        with self.assertRaises(RuntimeError):
            ic.run_ingest(self.URL, download, lambda a, b: ("", ""), lambda s, p: None)


if __name__ == "__main__":
    unittest.main()
