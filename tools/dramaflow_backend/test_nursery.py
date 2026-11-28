"""Tests of nursery_core.py (pure) and the `karaoke` / `nursery` Studio ops (real ffmpeg, small made-up media).
Run: python3 -m unittest test_nursery"""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace as NS

import nursery_core as nc
import studio_ops as so

FFMPEG = shutil.which("ffmpeg")
HAVE_FFMPEG = FFMPEG is not None


class Pure(unittest.TestCase):
    def test_lyric_lines_drop_headings_and_marks(self):
        t = "**[Verse 1]**\nLittle bunny hops\n- Sings a song\n\n[Chorus]\n(x2)\nLa la la\n【第二段】\n小兔子"
        self.assertEqual(nc.lyric_lines(t), ["Little bunny hops", "Sings a song", "La la la", "小兔子"])
        self.assertEqual(nc.lyric_lines(""), [])
        self.assertEqual(nc.lyric_lines("Look around (နေရောင်ခြည်)"), ["Look around (နေရောင်ခြည်)"])

    def test_split_words(self):
        self.assertEqual(nc.split_words("a  b c"), ["a", "b", "c"])
        self.assertEqual(nc.split_words("小兔子跳"), ["小", "兔", "子", "跳"])
        self.assertEqual(nc.split_words("နေရောင်ခြည်လေး"), ["နေရောင်ခြည်လေး"])  # Burmese is never cut inside a syllable
        self.assertEqual(nc.split_words("   "), [])

    def test_word_centis_add_up_exactly(self):
        for words, sec in ((["a", "bbb", "cc"], 2.37), (["x"], 0.5), (["ab", "cd", "ef", "gh", "ij", "kl", "mn"], 3.0)):
            cs = nc.word_centis(words, sec)
            self.assertEqual(sum(cs), int(round(sec * 100)))
            self.assertTrue(all(c >= 0 for c in cs))
        self.assertEqual(nc.word_centis([], 2), [])

    def test_proportional_cues_cover_the_song_in_order(self):
        cues = nc.proportional_cues(["short", "a much longer lyric line here"], 60)
        self.assertEqual(len(cues), 2)
        self.assertGreater(cues[0]["s"], 0)  # a quiet start
        self.assertLess(cues[1]["e"], 60 + 1e-9)
        self.assertLessEqual(cues[0]["e"], cues[1]["s"] + 1e-9)
        self.assertGreater(cues[1]["e"] - cues[1]["s"], cues[0]["e"] - cues[0]["s"])  # longer line, longer time
        for c in cues:
            self.assertEqual(sum(cs for _, cs in c["words"]), int(round((c["e"] - c["s"]) * 100)))
        self.assertEqual(nc.proportional_cues([], 10), [])
        self.assertEqual(nc.proportional_cues(["a"], 0), [])

    def test_cues_from_whisper_segments(self):
        W = lambda w, s, e: NS(word=w, start=s, end=e)
        segs = [NS(text=" Hello little star ", start=1.0, end=3.0, words=[W(" Hello", 1.0, 1.4), W(" little", 1.5, 2.0), W(" star", 2.1, 3.0)]),
                NS(text="", start=3, end=4, words=[]),
                NS(text="no words", start=3.5, end=3.7, words=None)]
        cues = nc.cues_from_segments(segs)
        self.assertEqual(len(cues), 2)
        self.assertEqual(cues[0]["t"], "Hello little star")
        self.assertEqual([w for w, _ in cues[0]["words"]], ["Hello", "little", "star"])
        self.assertGreaterEqual(cues[1]["e"] - cues[1]["s"], 0.4 - 1e-9)  # a short cue is lengthened
        self.assertLessEqual(cues[0]["e"], cues[1]["s"] + 1e-9)  # no overlap

    def test_ass_and_srt_text(self):
        cues = nc.proportional_cues(["Hello {x} world", "နေရောင်ခြည်လေး"], 20)
        ass = nc.ass_text(cues, 1280, 720, "Padauk")
        self.assertIn("PlayResX: 1280", ass)
        self.assertIn("Style: Kids,Padauk,", ass)
        self.assertIn("{\\kf", ass)
        self.assertNotIn("{x}", ass)  # braces would break the override tags
        self.assertEqual(ass.count("Dialogue:"), 2)
        self.assertIn("-->", nc.srt_text(cues))
        self.assertIn("00:00:", nc.srt_text(cues))
        evil = nc.ass_text(cues, 720, 1280, "Bad,Font;name")
        self.assertIn("Style: Kids,BadFontname,", evil)

    def test_plan_durations(self):
        d = nc.plan_durations(4, 40)
        self.assertEqual(d, [10.0] * 4)
        d = nc.plan_durations(3, 30, [8, 8, 16])
        self.assertAlmostEqual(sum(d), 30)
        self.assertAlmostEqual(d[2], 15)
        d = nc.plan_durations(2, 20, [19, 0.1], min_s=2)
        self.assertGreaterEqual(d[1], 2 - 1e-9)
        self.assertAlmostEqual(sum(d), 20)
        self.assertEqual(nc.plan_durations(0, 10), [])
        self.assertEqual(nc.plan_durations(3, 0), [])
        self.assertEqual(len(nc.plan_durations(3, 9, [1, 2])), 3)  # wrong length of weights: equal

    def test_command_shapes(self):
        cmd = nc.build_slideshow_cmd("ffmpeg", ["a.png", "b.mp4"], "s.mp3", "o.mp4", [3, 3], 6, "9:16", 30, "/tmp/x:y/l.ass")
        j = " ".join(cmd)
        self.assertIn("720x1280", j)
        self.assertIn("-stream_loop -1", j)
        self.assertIn("ass='/tmp/x\\:y/l.ass'", j)
        self.assertIn("zoompan", j)
        self.assertIn("loudnorm", j)
        self.assertIn("-t 6", j)
        self.assertIn("libx264", j)
        self.assertIn("h264_nvenc", " ".join(nc.build_slideshow_cmd("ffmpeg", ["a.png"], "s.mp3", "o.mp4", [6], 6, nvenc=True)))
        srt = " ".join(nc.build_slideshow_cmd("ffmpeg", ["a.png"], "s.mp3", "o.mp4", [6], 6, sub_path="/t/l.srt", font="Pad;auk"))
        self.assertIn("subtitles='/t/l.srt'", srt)
        self.assertIn("FontName=Padauk", srt)
        with self.assertRaises(ValueError):
            nc.build_slideshow_cmd("ffmpeg", [], "s.mp3", "o.mp4", [], 6)
        with self.assertRaises(ValueError):
            nc.build_slideshow_cmd("ffmpeg", ["a.png"], "s.mp3", "o.mp4", [1, 2], 6)
        with self.assertRaises(ValueError):
            nc.build_slideshow_cmd("ffmpeg", ["a.png"] * (nc.MAX_ITEMS + 1), "s.mp3", "o.mp4", [1] * (nc.MAX_ITEMS + 1), 6)


def run(*args):
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def probe(path):
    return subprocess.run([FFMPEG, "-i", str(path)], capture_output=True, text=True).stderr


def seconds(info):
    m = re.search(r"Duration: (\d+):(\d+):(\d+\.\d+)", info)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))


@unittest.skipUnless(HAVE_FFMPEG, "ffmpeg not installed")
class Ops(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.lib = Path(self.dir)
        for i, c in enumerate(("red", "green", "blue")):
            run("-f", "lavfi", "-i", f"color=c={c}:s=640x360", "-frames:v", "1", str(self.lib / f"scene{i + 1}.png"))
        run("-f", "lavfi", "-i", "testsrc2=size=320x180:rate=25:duration=2", "-pix_fmt", "yuv420p", "-c:v", "libx264", str(self.lib / "clip.mp4"))
        run("-f", "lavfi", "-i", "sine=frequency=440:duration=8", "-c:a", "libmp3lame", str(self.lib / "song.mp3"))
        self.log = []

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def env(self, canceled=lambda: False):
        return so.Env(self.lib, FFMPEG, lambda s, p: self.log.append((s, p)), canceled)

    def karaoke(self, **kw):
        base = dict(file="song.mp3", lyrics="[Verse 1]\nHello little star\nSing along with me\n[Chorus]\nLa la la", karaoke_mode="lyrics", ratio="16:9", font="Padauk")
        base.update(kw)
        return so.op_karaoke(self.env(), NS(**base))

    def test_karaoke_writes_ass_and_srt_from_the_lyrics(self):
        r = self.karaoke()
        self.assertEqual(len(r["files"]), 2)
        ass = (self.lib / r["files"][0]).read_text(encoding="utf-8")
        srt = (self.lib / r["files"][1]).read_text(encoding="utf-8")
        self.assertEqual(ass.count("Dialogue:"), 3)
        self.assertIn("Hello", srt)
        self.assertNotIn("Verse 1", srt)  # headings are not sung
        self.assertTrue(any("အကြမ်းချိန်" in n for n in r["notes"]))
        self.assertTrue((self.lib / "song.mp3").exists())
        r2 = self.karaoke()  # never overwrites
        self.assertNotEqual(r2["files"][0], r["files"][0])

    def test_karaoke_refuses_without_lyrics_and_with_a_bad_file(self):
        with self.assertRaises(ValueError):
            self.karaoke(lyrics="[Chorus]\n")
        with self.assertRaises(ValueError):
            self.karaoke(file="scene1.png")
        with self.assertRaises(ValueError):
            self.karaoke(file="../x.mp3")

    def nursery(self, **kw):
        base = dict(files=["scene1.png", "scene2.png", "clip.mp4"], file="song.mp3", srt_file="", durations=[], ratio="16:9", font="Padauk")
        base.update(kw)
        return so.op_nursery(self.env(), NS(**base))

    def test_pictures_and_a_clip_become_a_video_as_long_as_the_song(self):
        r = self.nursery()
        out = self.lib / r["files"][0]
        info = probe(out)
        self.assertIn("1280x720", info)
        self.assertIn("Audio: aac", info)
        self.assertAlmostEqual(seconds(info), 8.0, delta=0.4)
        self.assertTrue(any(p == 100 for _, p in self.log))
        for n in ("scene1.png", "clip.mp4", "song.mp3"):
            self.assertTrue((self.lib / n).exists())  # only read

    def test_planned_times_and_karaoke_lyrics_and_vertical_size(self):
        k = self.karaoke(ratio="9:16")
        r = self.nursery(files=["scene1.png", "scene2.png", "scene3.png"], srt_file=k["files"][0], durations=[2, 2, 4], ratio="9:16")
        info = probe(self.lib / r["files"][0])
        self.assertIn("720x1280", info)
        self.assertAlmostEqual(seconds(info), 8.0, delta=0.4)
        r2 = self.nursery(files=["scene1.png"], srt_file=k["files"][1])  # an .srt works too
        self.assertAlmostEqual(seconds(probe(self.lib / r2["files"][0])), 8.0, delta=0.4)

    def test_karaoke_text_is_really_drawn(self):
        # the lyrics must change the picture: the same video with and without the .ass differs
        k = self.karaoke()
        plain = self.nursery(files=["scene1.png"])
        with_text = self.nursery(files=["scene1.png"], srt_file=k["files"][0])
        shot = []
        for n in (plain["files"][0], with_text["files"][0]):
            png = self.lib / (n + ".png")
            run("-ss", "4", "-i", str(self.lib / n), "-frames:v", "1", str(png))
            shot.append(png.read_bytes())
        self.assertNotEqual(shot[0], shot[1])

    def test_refusals_leave_no_file(self):
        before = {f.name for f in self.lib.iterdir()}
        for kw in (dict(files=[]), dict(files=["nope.png"]), dict(file="scene1.png"), dict(srt_file="song.mp3"), dict(srt_file="missing.ass"),
                   dict(files=["../x.png"]), dict(files=["scene1.png"] * (nc.MAX_ITEMS + 1))):
            with self.assertRaises(ValueError, msg=str(kw)):
                self.nursery(**kw)
        self.assertEqual({f.name for f in self.lib.iterdir()}, before)

    def test_cancel_removes_the_partial_video(self):
        before = {f.name for f in self.lib.iterdir()}
        calls = {"n": 0}

        def canceled():
            calls["n"] += 1
            return calls["n"] > 3

        with self.assertRaises(BaseException):
            so.op_nursery(self.env(canceled), NS(files=["scene1.png", "scene2.png"], file="song.mp3", srt_file="", durations=[], ratio="16:9", font="Padauk"))
        self.assertEqual({f.name for f in self.lib.iterdir()}, before)


if __name__ == "__main__":
    unittest.main()
