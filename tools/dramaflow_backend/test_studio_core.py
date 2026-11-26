"""Tests of studio_core.py (no network). Run: python3 -m unittest test_studio_core"""
import unittest

import studio_core as sc


class Names(unittest.TestCase):
    def test_safe_names(self):
        for ok in ("video.mp4", "Episode 12 (final).mp4", "绝世唐门 第12集.mp4", "မြန်မာ ဗီဒီယို.srt", "a-b_c.mp3"):
            self.assertTrue(sc.safe_name(ok), ok)
        for bad in ("", ".hidden", "../x.mp4", "a/b.mp4", "a\\b.mp4", "x" * 200 + ".mp4", "a..b.mp4", "a;rm.mp4", "a\x00.mp4"):
            self.assertFalse(sc.safe_name(bad), repr(bad))

    def test_kind(self):
        self.assertEqual(sc.kind_of("a.MP4"), "video")
        self.assertEqual(sc.kind_of("a.mp3"), "audio")
        self.assertEqual(sc.kind_of("a_my.srt"), "srt")
        self.assertEqual(sc.kind_of("a.zip"), "other")

    def test_stem(self):
        self.assertEqual(sc.make_stem("Ep 12: The *Fight* / Part 2?"), "Ep 12_ The _Fight_ _ Part 2")
        self.assertEqual(sc.make_stem("   "), "video")
        self.assertEqual(sc.make_stem("", "x"), "x")
        self.assertEqual(sc.make_stem("绝世唐门 第12集"), "绝世唐门 第12集")
        self.assertLessEqual(len(sc.make_stem("a" * 500)), 80)
        self.assertTrue(sc.safe_name(sc.make_stem("မြန်မာ: စမ်းသပ်") + ".mp4"))

    def test_unique(self):
        self.assertEqual(sc.unique_name("a", ".mp4", []), "a.mp4")
        self.assertEqual(sc.unique_name("a", ".mp4", ["a.mp4"]), "a (2).mp4")
        self.assertEqual(sc.unique_name("a", ".mp4", ["a.mp4", "a (2).mp4"]), "a (3).mp4")


class Time(unittest.TestCase):
    def test_parse_time(self):
        self.assertEqual(sc.parse_time("90"), 90)
        self.assertEqual(sc.parse_time("1:30"), 90)
        self.assertEqual(sc.parse_time("01:02:03"), 3723)
        self.assertEqual(sc.parse_time("1:30.5"), 90.5)
        self.assertEqual(sc.parse_time("1:30,5"), 90.5)
        for bad in ("", "abc", "1:2:3:4", "-5", "1:xx"):
            self.assertIsNone(sc.parse_time(bad), bad)

    def test_fmt(self):
        self.assertEqual(sc.fmt_time(65), "1:05")
        self.assertEqual(sc.fmt_time(3725), "1:02:05")
        self.assertEqual(sc.fmt_time(-3), "0:00")

    def test_equal_parts_cover_everything(self):
        p = sc.equal_parts(100, 3)
        self.assertEqual(len(p), 3)
        self.assertEqual(p[0][0], 0)
        self.assertEqual(p[-1][1], 100)
        for a, b in zip(p, p[1:]):
            self.assertAlmostEqual(a[1], b[0], places=2)

    def test_equal_parts_limits(self):
        self.assertEqual(sc.equal_parts(0.5, 3), [])
        self.assertEqual(len(sc.equal_parts(3, 10)), 3)  # not shorter than a second
        self.assertEqual(len(sc.equal_parts(10000, 500)), sc.MAX_PARTS)
        self.assertEqual(len(sc.equal_parts(60, 0)), 1)

    def test_ranges(self):
        r, err = sc.parse_ranges("0:00-5:00, 5:00 - 12:30", 800)
        self.assertEqual((r, err), ([(0.0, 300.0), (300.0, 750.0)], ""))
        r, err = sc.parse_ranges("0:00-5:00\n10:00-99:00", 800)
        self.assertEqual(r[1], (600.0, 800.0))  # an end past the video is cut
        self.assertEqual(sc.parse_ranges("0:10 to 0:40", 100)[0], [(10.0, 40.0)])

    def test_ranges_errors(self):
        for text in ("", "abc", "1:00", "5:00-1:00", "0:00-0:00", "x-y", "30:00-40:00"):
            r, err = sc.parse_ranges(text, 600)
            self.assertEqual(r, [], text)
            self.assertTrue(err, text)
        r, err = sc.parse_ranges(",".join(f"{i}:00-{i}:30" for i in range(0, 61)), 4000)
        self.assertEqual(r, [])
        self.assertIn(str(sc.MAX_PARTS), err)


SRT = """﻿1
00:00:01,000 --> 00:00:03,000
Hello

2
00:00:03,500 --> 00:00:06,000
Line one
Line two

3
00:00:10,000 --> 00:00:12,500
Late
"""


class Srt(unittest.TestCase):
    def test_parse(self):
        c = sc.parse_srt(SRT)
        self.assertEqual(len(c), 3)
        self.assertEqual(c[0], (1000, 3000, "Hello"))
        self.assertEqual(c[1][2], "Line one\nLine two")

    def test_parse_crlf_dot_and_junk(self):
        c = sc.parse_srt("1\r\n00:00:01.5 --> 00:00:02.25\r\nA\r\n\r\nnonsense block\r\n\r\n")
        self.assertEqual(c, [(1500, 2250, "A")])
        self.assertEqual(sc.parse_srt(""), [])
        self.assertEqual(sc.parse_srt("no cues"), [])

    def test_roundtrip(self):
        c = sc.parse_srt(SRT)
        self.assertEqual(sc.parse_srt(sc.serialize_srt(c)), c)
        self.assertTrue(sc.serialize_srt(c).startswith("1\n00:00:01,000 --> 00:00:03,000\nHello\n"))

    def test_slice(self):
        c = sc.parse_srt(SRT)
        s = sc.slice_srt(c, 2, 5)
        self.assertEqual(s, [(0, 1000, "Hello"), (1500, 3000, "Line one\nLine two")])
        self.assertEqual(sc.slice_srt(c, 7, 9), [])
        self.assertEqual(sc.slice_srt(c, 10, 11)[0], (0, 1000, "Late"))


class Translate(unittest.TestCase):
    def test_batches(self):
        texts = ["x" * 1000, "y" * 1000, "z" * 1000, "w"]
        b = sc.batches(texts, max_chars=2100)
        self.assertEqual([i for g in b for i in g], [0, 1, 2, 3])
        self.assertGreater(len(b), 1)
        self.assertEqual(len(sc.batches(["a"] * 100, max_items=40)), 3)
        self.assertEqual(sc.batches([]), [])

    def test_prompt_and_reply(self):
        p = sc.numbered_prompt(["Hi", "Two\nlines"], "zh")
        self.assertIn("1|Hi", p)
        self.assertIn("2|Two / lines", p)
        self.assertIn("Burmese", p)
        got = sc.parse_numbered_reply("1|မင်္ဂလာပါ\n2|နှစ်\nကြောင်း\n", 2)
        self.assertEqual(got, ["မင်္ဂလာပါ", "နှစ် ကြောင်း"])
        self.assertEqual(sc.parse_numbered_reply("`1|a`\n3|c", 3), ["a", "", "c"])
        self.assertEqual(sc.parse_numbered_reply("", 2), ["", ""])
        self.assertEqual(sc.parse_numbered_reply("9|out of range", 2), ["", ""])

    def test_translate_cues_ok(self):
        cues = [(0, 1000, "a"), (1000, 2000, "b")]
        out, failed = sc.translate_cues(cues, lambda ts: [t.upper() for t in ts])
        self.assertEqual([c[2] for c in out], ["A", "B"])
        self.assertEqual(failed, 0)
        self.assertEqual((out[1][0], out[1][1]), (1000, 2000))

    def test_wrong_count_falls_back_to_line_by_line(self):
        calls = []

        def many(ts):
            calls.append(len(ts))
            return ts[:1] * 1 if len(ts) > 1 else [ts[0] + "!"]

        out, failed = sc.translate_cues([(0, 1, "a"), (1, 2, "b"), (2, 3, "c")], many)
        self.assertEqual([c[2] for c in out], ["a!", "b!", "c!"])
        self.assertEqual(failed, 0)
        self.assertEqual(calls, [3, 1, 1, 1])

    def test_failures_keep_the_original(self):
        def many(ts):
            if "bad" in ts:
                raise RuntimeError("429")
            return [t + "!" for t in ts]

        out, failed = sc.translate_cues([(0, 1, "ok"), (1, 2, "bad"), (2, 3, "ok2")], many)
        self.assertEqual([c[2] for c in out], ["ok!", "bad", "ok2!"])
        self.assertEqual(failed, 1)

    def test_empty_answers_count_as_failed(self):
        out, failed = sc.translate_cues([(0, 1, "a"), (1, 2, "b")], lambda ts: ["" for _ in ts])
        self.assertEqual([c[2] for c in out], ["a", "b"])
        self.assertEqual(failed, 2)

    def test_progress(self):
        seen = []
        sc.translate_cues([(i, i + 1, "x" * 30) for i in range(100)], lambda ts: ts, lambda d, t: seen.append((d, t)))
        self.assertEqual(seen[-1][0], seen[-1][1])
        self.assertGreater(len(seen), 1)


class Ffmpeg(unittest.TestCase):
    def test_split_copy_and_reencode(self):
        c = sc.split_cmd("ff", "in.mp4", 10, 20.5, "out.mp4", False)
        self.assertEqual(c[:2], ["ff", "-y"])
        self.assertIn("copy", c)
        self.assertEqual(c[c.index("-ss") + 1], "10.000")
        self.assertEqual(c[c.index("-t") + 1], "20.500")
        self.assertEqual(c[-1], "out.mp4")
        r = sc.split_cmd("ff", "in.mp4", 0, 5, "o.mp4", True)
        self.assertIn("libx264", r)
        self.assertNotIn("copy", r)

    def test_nothing_changes_the_picture(self):
        """Studio never zooms, flips, recolours or changes the pitch."""
        cmds = [sc.split_cmd("ff", "i", 0, 5, "o", True), sc.split_cmd("ff", "i", 0, 5, "o", False), sc.mux_cc_cmd("ff", "v", "s", "o")]
        for c in cmds:
            text = " ".join(c)
            for banned in ("hflip", "vflip", "zoom", "crop=", "scale=", "eq=", "asetrate", "atempo", "-af"):
                self.assertNotIn(banned, text)

    def test_mux_copies_picture_and_sound(self):
        c = sc.mux_cc_cmd("ff", "v.mp4", "s.srt", "o.mp4")
        self.assertEqual(c[c.index("-c:v") + 1], "copy")
        self.assertEqual(c[c.index("-c:a") + 1], "copy")
        self.assertIn("mov_text", c)
        self.assertIn("language=mya", c)

    def test_hardsub(self):
        c = sc.hardsub_cmd("ff", "v.mp4", "/tmp/a:b's,[x].srt", "o.mp4", "Padauk; rm -rf", 99)
        vf = c[c.index("-vf") + 1]
        self.assertIn("FontName=Padauk rm -rf", vf)  # odd characters of the font name are dropped
        self.assertIn("FontSize=60", vf)
        self.assertIn("\\:", vf)
        self.assertIn("\\,", vf)
        self.assertIn("libx264", c)
        self.assertIn("h264_nvenc", sc.hardsub_cmd("ff", "v", "s", "o", gpu=True))


class YouTube(unittest.TestCase):
    def test_title(self):
        self.assertEqual(sc.format_title("{name} - အပိုင်း {n}/{total}", "Ep", 2, 5), "Ep - အပိုင်း 2/5")
        self.assertEqual(sc.format_title("", "Name", 1, 1), "Name")
        self.assertEqual(sc.format_title("<b>{name}</b>", "x", 1, 1), "bx/b")  # only the < > are removed
        self.assertLessEqual(len(sc.format_title("{name}", "x" * 300, 1, 1)), 100)
        self.assertEqual(sc.format_title("   ", "", 1, 1), "video")

    def test_tags_description(self):
        self.assertEqual(sc.clean_tags("a, b ,,<c>, d"), ["a", "b", "c", "d"])
        self.assertLessEqual(sum(len(t) + 1 for t in sc.clean_tags(",".join("t" * 40 for _ in range(50)))), 450)
        self.assertEqual(sc.clean_description("x<y>z"), "xyz")
        self.assertEqual(len(sc.clean_description("a" * 9000)), 4900)

    def test_oauth_code(self):
        self.assertEqual(sc.extract_oauth_code("http://localhost/?state=x&code=4/0AbCdEf&scope=youtube"), "4/0AbCdEf")
        self.assertEqual(sc.extract_oauth_code("4/0AbCdEfGhIj"), "4/0AbCdEfGhIj")
        self.assertEqual(sc.extract_oauth_code("  http://localhost/?code=abc123XYZ789  "), "abc123XYZ789")
        self.assertEqual(sc.extract_oauth_code(""), "")
        self.assertEqual(sc.extract_oauth_code("hello world"), "")

    def test_hints(self):
        self.assertIn("quota", sc.youtube_error_hint("<HttpError 403 quotaExceeded>"))
        self.assertIn("login", sc.youtube_error_hint("invalid_grant: Token has been expired or revoked"))
        self.assertEqual(sc.youtube_error_hint("some other thing"), "")

    def test_privacy_and_categories(self):
        self.assertEqual(sc.YT_PRIVACY[0], "private")  # the safe choice is the first
        self.assertIn("entertainment", sc.YT_CATEGORIES)


class Downloading(unittest.TestCase):
    def test_qualities_and_speeds(self):
        self.assertEqual(sc.QUALITIES["mp3"][1], "audio")
        self.assertEqual(sc.QUALITIES["srt"][1], "subtitles")
        self.assertIn("height<=720", sc.QUALITIES["720"][0])
        self.assertIn("hev", sc.QUALITIES["1080hevc"][0])
        self.assertEqual(sc.SPEEDS["native"], 1)
        self.assertEqual(sc.SPEEDS["turbo16"], 16)

    def test_extract_urls_many_lines_and_share_text(self):
        t = ("see https://youtu.be/abc123.\n"
             "78 【绝世唐门】 http://xhslink.com/a/AbC，复制\n"
             "https://youtu.be/abc123\n"
             "BV1ab4y1c7d8\n"
             "nothing here\n")
        self.assertEqual(sc.extract_urls(t), ["https://youtu.be/abc123", "http://xhslink.com/a/AbC", "https://www.bilibili.com/video/BV1ab4y1c7d8"])
        self.assertEqual(sc.extract_urls(""), [])

    def test_short_bilibili_is_resolved(self):
        out = sc.extract_urls("https://b23.tv/xyz", resolve=lambda u: "https://m.bilibili.com/video/BV1x?p=3&spm_id_from=a")
        self.assertEqual(out, ["https://www.bilibili.com/video/BV1x?p=3"])
        out = sc.extract_urls("https://b23.tv/xyz", resolve=lambda u: 1 / 0)  # a failing resolver keeps the link
        self.assertEqual(out, ["https://b23.tv/xyz"])

    def test_normalize(self):
        self.assertEqual(sc.normalize_url("https://www.bilibili.com/en/video/BV1x?p=2&share=1"), "https://www.bilibili.com/video/BV1x?p=2")
        self.assertEqual(sc.normalize_url("https://youtu.be/a?t=5"), "https://youtu.be/a?t=5")

    def test_playlist_items(self):
        self.assertEqual(sc.parse_playlist_items(" 4 - 7 "), ("4-7", ""))
        self.assertEqual(sc.parse_playlist_items("4,6,8"), ("4,6,8", ""))
        self.assertEqual(sc.parse_playlist_items(""), (None, ""))
        self.assertEqual(sc.parse_playlist_items("1:3,-5:")[0], "1:3,-5:")
        self.assertTrue(sc.parse_playlist_items("4; rm")[1])
        self.assertTrue(sc.parse_playlist_items("1," * 100)[1])

    def test_sub_langs(self):
        self.assertEqual(sc.sub_langs("auto", True), ["en", "my", "zh-Hans", "zh-CN", "zh"])
        self.assertIn("all", sc.sub_langs("auto", False))
        self.assertIn("-danmaku", sc.sub_langs("all"))
        self.assertIn("zh-Hans", sc.sub_langs("zh"))
        self.assertEqual(sc.sub_langs("en"), ["en.*", "en"])
        self.assertEqual(sc.sub_langs("my"), ["my.*", "my"])

    def test_aria2_args(self):
        self.assertEqual(sc.aria2_args(8)[:4], ["-x", "8", "-s", "8"])
        self.assertEqual(sc.aria2_args(99)[1], "16")
        self.assertEqual(sc.aria2_args(0)[1], "1")

    def test_download_hints(self):
        self.assertIn("cookies.txt", sc.download_hint("Sign in to confirm you're not a bot", {"YouTube"}))
        self.assertNotEqual(sc.download_hint("HTTP Error 412: Precondition Failed"), "")
        self.assertIn("Bilibili", sc.download_hint("HTTP Error 412 Precondition Failed", {"Bilibili"}))
        self.assertIn("1 လိုင်း", sc.download_hint("HTTP Error 403: Forbidden", used_aria2c=True))
        self.assertNotIn("1 လိုင်း", sc.download_hint("HTTP Error 403: Forbidden", used_aria2c=False))
        self.assertIn("subtitle", sc.download_hint("nothing", subtitles_only=True))
        self.assertIn("Bilibili", sc.download_hint("x", {"Bilibili"}, has_cookie=False, subtitles_only=True))
        self.assertEqual(sc.download_hint("fine"), "")



class WhisperHelpers(unittest.TestCase):
    def test_language(self):
        self.assertIsNone(sc.whisper_lang("auto"))
        self.assertIsNone(sc.whisper_lang(""))
        self.assertIsNone(sc.whisper_lang("; rm -rf"))
        self.assertEqual(sc.whisper_lang("zh-CN"), "zh")
        self.assertEqual(sc.whisper_lang(" EN "), "en")

    def test_model_name_falls_back_to_small(self):
        self.assertEqual(sc.whisper_model_name("large-v3"), "large-v3")
        self.assertEqual(sc.whisper_model_name("../../x"), "small")
        self.assertEqual(sc.whisper_model_name(""), "small")

    def test_segments_to_cues(self):
        from types import SimpleNamespace as NS
        segs = [NS(start=0.0, end=2.0, text=" hello  world "), NS(start=1.5, end=3.0, text="overlap"), NS(start=4.0, end=4.1, text="short"), NS(start=5.0, end=6.0, text="  ")]
        cues = sc.segments_to_cues(segs)
        self.assertEqual(cues[0], (0, 1500, "hello world"))
        self.assertEqual(cues[1], (1500, 3000, "overlap"))
        self.assertEqual(cues[2], (4000, 4400, "short"))
        self.assertEqual(len(cues), 3)
        for a, b in zip(cues, cues[1:]):
            self.assertLessEqual(a[1], b[0])

    def test_close_start_moves_the_next_cue_instead(self):
        from types import SimpleNamespace as NS
        cues = sc.segments_to_cues([NS(start=1.0, end=2.0, text="a"), NS(start=1.1, end=2.5, text="b")])
        self.assertEqual(cues[0], (1000, 2000, "a"))
        self.assertEqual(cues[1][0], 2000)


if __name__ == "__main__":
    unittest.main()
