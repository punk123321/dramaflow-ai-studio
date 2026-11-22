"""Tests for the pure/ffmpeg helpers of news_backend_colab.py without installing
fastapi, edge-tts or google-genai: the functions are cut out of the file.
Run:  python3 tools/test_news_helpers.py   (needs ffmpeg and ffprobe)"""
import ast, json, subprocess, tempfile, unittest, wave
from pathlib import Path
from typing import Optional

SRC = Path(__file__).with_name("news_backend_colab.py").read_text()
TREE = ast.parse(SRC)


def load(*names):
    ns = {"Path": Path, "Optional": Optional, "subprocess": subprocess, "json": json}
    for node in TREE.body:
        if isinstance(node, ast.FunctionDef) and node.name in names:
            exec(compile(ast.Module([node], []), "news", "exec"), ns)
    return ns


class Helpers(unittest.TestCase):
    def test_images_for(self):
        f = load("images_for")["images_for"]
        self.assertEqual(f(5, 12), 1)
        self.assertEqual(f(14, 12), 1)
        self.assertEqual(f(30, 12), 2)
        self.assertEqual(f(300, 12), 4)  # capped per scene
        self.assertEqual(f(10, 0), 1)

    def test_scene_from_three_pictures(self):
        ns = load("_run", "render_image_clip", "render_image_scene")
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            imgs = []
            for i, c in enumerate(("red", "green", "blue")):
                p = d / f"i{i}.jpg"
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", f"color=c={c}:s=1600x1000", "-frames:v", "1", str(p)], check=True)
                imgs.append(p)
            aud = d / "a.wav"
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=d=6", str(aud)], check=True)
            out = d / "scene.mp4"
            ns["render_image_scene"](imgs, aud, out, "9:16", 6.0, d, 0)
            probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height:format=duration", "-of", "json", str(out)],
                                   capture_output=True, text=True, check=True).stdout
            j = json.loads(probe)
            dur = float(j["format"]["duration"])
            self.assertAlmostEqual(dur, 6.0, delta=0.3)
            v = [s for s in j["streams"] if s["codec_name"] == "h264"][0]
            self.assertEqual((v["width"], v["height"]), (720, 1280))
            self.assertTrue(any(s["codec_name"] == "aac" for s in j["streams"]))


if __name__ == "__main__":
    unittest.main()
