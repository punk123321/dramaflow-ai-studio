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


class AiImages(unittest.TestCase):
    def test_prompt_is_safe_and_varies(self):
        f = load("ai_prompt")["ai_prompt"]
        a, b = f("flooded street", "9:16", 0), f("flooded street", "9:16", 1)
        self.assertNotEqual(a, b)
        self.assertIn("vertical", a)
        self.assertIn("horizontal", f("x", "16:9"))
        for w in ("no text", "no logos", "no watermark", "no identifiable real people"):
            self.assertIn(w, a)
        self.assertLessEqual(len(f("k" * 999, "9:16")), 160 + 220)

    def test_inline_image_parsing(self):
        import base64
        f = load("gemini_image_bytes")["gemini_image_bytes"]
        raw = b"\x89PNG" + b"x" * 50
        ok = {"candidates": [{"content": {"parts": [{"text": "hi"}, {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(raw).decode()}}]}}]}
        self.assertEqual(f(ok), raw)
        snake = {"candidates": [{"content": {"parts": [{"inline_data": {"data": base64.b64encode(raw).decode()}}]}}]}
        self.assertEqual(f(snake), raw)
        self.assertIsNone(f({"candidates": [{"content": {"parts": [{"text": "only text"}]}}]}))
        self.assertIsNone(f({}))
        self.assertIsNone(f(None))
        self.assertIsNone(f({"candidates": [{"content": {"parts": [{"inlineData": {"data": "!!not base64!!"}}]}}]}))

    def test_error_text_hides_key(self):
        f = load("short_api_error")["short_api_error"]
        body = json.dumps({"error": {"message": "quota for key AIza-secret-12345 exceeded\n  now"}})
        r = f(body, "AIza-secret-12345")
        self.assertNotIn("AIza", r)
        self.assertIn("quota", r)
        self.assertNotIn("\n", r)
        self.assertEqual(f("plain text", ""), "plain text")
        self.assertLessEqual(len(f("x" * 999)), 160)

    def _gen(self, results):
        ns = load("generate_images", "ai_prompt")
        calls = []

        def fake(prompt, *a):
            calls.append(prompt)
            why = results.pop(0)
            if why == "":
                a[-1].write_bytes(b"x" * 2000)  # the save path is the last argument
            return why

        import secrets
        ns.update(gen_gemini_image=fake, gen_pollinations_image=fake, secrets=secrets, AI_GEMINI_IMAGE_MODEL="m")
        return ns["generate_images"], calls

    def test_generates_what_is_needed(self):
        f, calls = self._gen(["", "", ""])
        with tempfile.TemporaryDirectory() as d:
            state = {}
            imgs = f("ai_gemini", "k", "", ["a", "b"], "9:16", 3, Path(d), 0, state)
            self.assertEqual(len(imgs), 3)
            self.assertEqual(state["made"], 3)
            self.assertFalse(state.get("off"))
            self.assertIn("a,", calls[0])
            self.assertIn("b,", calls[1])  # keywords take turns

    def test_two_failures_in_a_row_switch_it_off(self):
        f, calls = self._gen(["HTTP 429 quota", "HTTP 429 quota", ""])
        with tempfile.TemporaryDirectory() as d:
            state = {}
            self.assertEqual(f("ai_gemini", "k", "", ["a"], "9:16", 4, Path(d), 0, state), [])
            self.assertTrue(state["off"])
            self.assertEqual(state["why"], "HTTP 429 quota")
            self.assertEqual(len(calls), 2)  # it stopped trying
            # the next scene does not try again
            self.assertEqual(f("ai_gemini", "k", "", ["a"], "9:16", 4, Path(d), 1, state), [])
            self.assertEqual(len(calls), 2)

    def test_one_failure_then_success_goes_on(self):
        f, calls = self._gen(["HTTP 500", "", ""])
        with tempfile.TemporaryDirectory() as d:
            state = {}
            imgs = f("ai_pollinations", "", "", ["a"], "16:9", 3, Path(d), 0, state)
            self.assertEqual(len(imgs), 2)  # 3 tries, 1 failed
            self.assertFalse(state.get("off"))
            self.assertEqual(state["fails"], 0)


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
