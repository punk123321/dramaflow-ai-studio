"""Tests of render_core.py (pure) and the `render` Studio op (real ffmpeg on a small made-up video).
Run: python3 -m unittest test_render"""
import copy
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace as NS

import render_core as rc
import studio_ops as so

FFMPEG = shutil.which("ffmpeg")
HAVE_FFMPEG = FFMPEG is not None


def job(**kw):
    j = {"name": "Show_part01_1", "outW": 320, "outH": 180, "fit": "orig", "fps": 25, "bitrate": 1_000_000, "originalVolume": 1.0,
         "aspect": 16 / 9, "pieces": [{"s": 0, "e": 4000}, {"s": 6000, "e": 10000, "sp": 2.0}], "burn": False, "subtitles": [],
         "subStyle": {"size": 0.05, "color": 0xFFFFFFFF, "bg": True, "top": False}}
    j.update(kw)
    return j


class Pure(unittest.TestCase):
    def test_supported_job_has_no_reasons(self):
        self.assertEqual(rc.unsupported(job()), [])

    def test_every_unsupported_feature_is_reported(self):
        cases = {
            "voiceLanes": [[{"uri": "x", "off": 0, "dur": 1000, "vol": 1}]],
            "music": {"uri": "m", "vol": 1, "loop": True},
            "overlays": [{"s": 0, "e": 1000}],
            "splits": [{"s": 0, "e": 2000}],
            "logo": {"p": "x"},
            "corners": [{"t": "x"}],
            "fit": "blur",
        }
        for k, v in cases.items():
            self.assertTrue(rc.unsupported(job(**{k: v})), k)
        for piece in ({"s": 0, "e": 1000, "f": 1}, {"s": 0, "e": 1000, "c": [1, 0.5, 0.5]}, {"s": 0, "e": 1000, "z": 1},
                      {"s": 0, "e": 1000, "l": [0, 0]}, {"s": 0, "e": 1000, "sp": 9.0}):
            self.assertTrue(rc.unsupported(job(pieces=[piece])), piece)

    def test_pieces_must_be_in_order_and_not_overlap(self):
        self.assertTrue(rc.unsupported(job(pieces=[{"s": 5000, "e": 8000}, {"s": 1000, "e": 2000}])))
        self.assertTrue(rc.unsupported(job(pieces=[{"s": 0, "e": 5000}, {"s": 4000, "e": 8000}])))
        self.assertTrue(rc.unsupported(job(pieces=[{"s": 3000, "e": 3000}])))
        self.assertTrue(rc.unsupported(job(pieces=[])))

    def test_output_length_follows_speed(self):
        self.assertEqual(rc.output_ms(job()), 6000)

    def test_atempo_chain(self):
        self.assertEqual(rc.atempo_chain(1.0), "")
        self.assertEqual(rc.atempo_chain(1.5), "atempo=1.500000")
        self.assertEqual(rc.atempo_chain(4.0), "atempo=2.0,atempo=2.000000")
        self.assertEqual(rc.atempo_chain(0.25), "atempo=0.5,atempo=0.500000")

    def test_ass_colour_turns_alpha_and_channels_round(self):
        self.assertEqual(rc.ass_color(0xFFFFFFFF), "&H00FFFFFF")
        self.assertEqual(rc.ass_color(0xFFFF0000), "&H000000FF")  # red in ARGB is 0000FF in BGR
        self.assertEqual(rc.ass_color(0x80000000), "&H7F000000")

    def test_subtitle_style(self):
        s = rc.subtitle_style({"size": 0.05, "color": 0xFFFFFFFF, "bg": True, "top": False}, "Padauk;x")
        self.assertIn("FontName=Padaukx", s)
        self.assertIn("FontSize=14", s)
        self.assertIn("BorderStyle=3", s)
        self.assertIn("Alignment=2", s)
        top = rc.subtitle_style({"top": True, "bg": False})
        self.assertIn("Alignment=6", top)
        self.assertIn("BorderStyle=1", top)

    def test_srt_text_skips_empty_and_backwards_cues(self):
        t = rc.srt_text([{"s": 0, "e": 1500, "t": "a"}, {"s": 2000, "e": 2000, "t": "b"}, {"s": 3000, "e": 4000, "t": "  "}, {"s": 3661001, "e": 3662000, "t": "c"}])
        self.assertIn("1\n00:00:00,000 --> 00:00:01,500\na", t)
        self.assertIn("2\n01:01:01,001 --> 01:01:02,000\nc", t)
        self.assertNotIn("\nb\n", t)

    def test_censor_boxes_are_clamped_and_checked(self):
        b = rc.censor_boxes({"aspect": 2.0, "censors": [{"s": 1000, "e": 9000, "x": 0.5, "y": 0.5, "w": 0.4, "ar": 0.5, "str": 99}]})
        l, t, w, h, a, e, sigma = b[0]
        self.assertAlmostEqual(l, 0.3)
        self.assertAlmostEqual(w, 0.4)
        self.assertAlmostEqual(h, 0.4)  # 0.4 * 0.5 * 2.0
        self.assertEqual((a, e, sigma), (1.0, 9.0, 60.0))
        with self.assertRaises(ValueError):
            rc.censor_boxes({"censors": [{"s": 0, "e": 1, "x": 5.0, "y": 0.5, "w": 0.1}]})

    def test_graph_has_the_pieces_the_boxes_and_the_sound(self):
        g, v, a = rc.filter_graph(job(censors=[{"s": 1000, "e": 9000, "x": 0.5, "y": 0.5, "w": 0.3, "ar": 0.5, "str": 25}]), True, None)
        self.assertIn("gblur=sigma=25", g)
        self.assertIn("between(t,1,9)", g)
        self.assertIn("concat=n=2:v=1:a=1", g)
        self.assertIn("atempo=2.000000", g)
        self.assertEqual((v, a), ("[vout]", "[acat]"))

    def test_no_sound_when_the_source_has_none_or_volume_is_zero(self):
        self.assertIsNone(rc.filter_graph(job(), False, None)[2])
        self.assertIsNone(rc.filter_graph(job(originalVolume=0.0), True, None)[2])

    def test_build_cmd_refuses_an_unsupported_job(self):
        with self.assertRaises(ValueError) as cm:
            rc.build_cmd("ffmpeg", "a.mp4", "b.mp4", job(music={"uri": "m"}), True, False)
        self.assertIn("Background music", str(cm.exception))

    def test_encoder_choice(self):
        cpu = rc.build_cmd("ffmpeg", "a.mp4", "b.mp4", job(), True, False)
        gpu = rc.build_cmd("ffmpeg", "a.mp4", "b.mp4", job(), True, True)
        self.assertIn("libx264", cpu)
        self.assertIn("h264_nvenc", gpu)
        self.assertIn("1000k", cpu)


def make_video(path, seconds=12, audio=True):
    cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", f"testsrc2=size=320x180:rate=25:duration={seconds}"]
    if audio:
        cmd += ["-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}"]
    cmd += ["-pix_fmt", "yuv420p", "-c:v", "libx264"] + (["-c:a", "aac"] if audio else []) + ["-shortest", str(path)]
    subprocess.run(cmd, check=True)


def probe(path):
    p = subprocess.run([FFMPEG, "-i", str(path)], capture_output=True, text=True)
    return p.stderr


@unittest.skipUnless(HAVE_FFMPEG, "ffmpeg not installed")
class Op(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.lib = Path(self.dir)
        make_video(self.lib / "src.mp4")
        self.log = []

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def env(self, canceled=lambda: False):
        return so.Env(self.lib, FFMPEG, lambda s, p: self.log.append((s, p)), canceled)

    def test_makes_the_cut_video_with_size_speed_and_sound(self):
        r = so.op_render(self.env(), NS(job=job(), file="src.mp4", font="Padauk"))
        self.assertEqual(len(r["files"]), 1)
        out = self.lib / r["files"][0]
        self.assertTrue(out.exists())
        info = probe(out)
        self.assertIn("320x180", info)
        self.assertIn("Audio: aac", info)
        # 4 s + 4 s at double speed = 6 s
        import re
        m = re.search(r"Duration: (\d+):(\d+):(\d+\.\d+)", info)
        secs = int(m.group(2)) * 60 + float(m.group(3))
        self.assertAlmostEqual(secs, 6.0, delta=0.3)
        self.assertTrue(any(p == 100 for _, p in self.log))
        self.assertTrue((self.lib / "src.mp4").exists())  # the original is only read

    def test_a_blur_box_and_burned_subtitles_make_it_through(self):
        j = job(censors=[{"s": 1000, "e": 9000, "x": 0.5, "y": 0.5, "w": 0.3, "ar": 0.5, "str": 20}], burn=True,
                subtitles=[{"s": 0, "e": 2000, "t": "hello"}])
        r = so.op_render(self.env(), NS(job=j, file="src.mp4", font="Padauk"))
        self.assertTrue((self.lib / r["files"][0]).stat().st_size > 1024)
        self.assertTrue(any("Blur box" in n for n in r["notes"]))

    def test_a_source_without_sound_still_works(self):
        make_video(self.lib / "mute.mp4", audio=False)
        r = so.op_render(self.env(), NS(job=job(), file="mute.mp4", font="Padauk"))
        self.assertNotIn("Audio:", probe(self.lib / r["files"][0]))

    def test_an_unsupported_job_is_refused_and_leaves_no_file(self):
        before = sorted(p.name for p in self.lib.iterdir())
        with self.assertRaises(ValueError):
            so.op_render(self.env(), NS(job=job(overlays=[{"s": 0, "e": 1000}]), file="src.mp4", font="Padauk"))
        self.assertEqual(sorted(p.name for p in self.lib.iterdir()), before)

    def test_cancel_stops_and_removes_the_partial_file(self):
        calls = {"n": 0}

        def canceled():
            calls["n"] += 1
            return calls["n"] > 3

        before = sorted(p.name for p in self.lib.iterdir())
        with self.assertRaises(so.Canceled):
            so.op_render(self.env(canceled), NS(job=job(pieces=[{"s": 0, "e": 12000}], fps=60, outW=1280, outH=720), file="src.mp4", font="Padauk"))
        self.assertEqual(sorted(p.name for p in self.lib.iterdir()), before)

    def test_a_missing_or_empty_job_and_a_missing_file_are_refused(self):
        with self.assertRaises(ValueError):
            so.op_render(self.env(), NS(job={}, file="src.mp4"))
        with self.assertRaises(ValueError):
            so.op_render(self.env(), NS(job=job(), file="nope.mp4"))

    def test_the_name_never_overwrites(self):
        a = so.op_render(self.env(), NS(job=job(), file="src.mp4", font="Padauk"))["files"][0]
        b = so.op_render(self.env(), NS(job=job(), file="src.mp4", font="Padauk"))["files"][0]
        self.assertNotEqual(a, b)


if __name__ == "__main__":
    unittest.main()
