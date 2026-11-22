"""Run:  python3 -m unittest test_recap_core   (no packages needed)"""
import unittest

from recap_core import mask_key, parse_reply, run_recap


class ParseTests(unittest.TestCase):
    def test_parts_and_code_fence(self):
        r = "intro\n```\n=== PART 1 ===\nတစ်။\n=== PART 2 ===\nနှစ်။\n```"
        self.assertEqual(parse_reply(r), {1: "တစ်။", 2: "နှစ်။"})

    def test_empty_part_skipped(self):
        self.assertEqual(parse_reply("=== PART 1 ===\n\n=== PART 2 ===\nx"), {2: "x"})

    def test_none(self):
        self.assertEqual(parse_reply(""), {})

    def test_mask(self):
        self.assertEqual(mask_key("bad key ABCDEFGH12 here", "ABCDEFGH12"), "bad key *** here")
        self.assertEqual(mask_key("short", "abc"), "short")


class RunTests(unittest.TestCase):
    def groups(self):
        return [{"first": 1, "last": 2, "prompt": "p"}, {"first": 3, "last": 4, "prompt": "q"}]

    def test_ok_with_voice(self):
        replies = iter(["=== PART 1 ===\na\n=== PART 2 ===\nb", "=== PART 3 ===\nc\n=== PART 4 ===\nd"])
        prog = []
        out = run_recap(self.groups(), lambda g: next(replies), lambda n, t: (1000 * n, f"p{n}.wav"),
                        lambda s, p: prog.append(p), sleep=lambda s: None)
        self.assertEqual([p["n"] for p in out["parts"]], [1, 2, 3, 4])
        self.assertEqual(out["parts"][3]["audio_ms"], 4000)
        self.assertEqual(out["warnings"], [])
        self.assertEqual(prog, sorted(prog))
        self.assertLessEqual(max(prog), 100)

    def test_missing_part_and_failed_group(self):
        def gem(g):
            if g["first"] == 3:
                raise RuntimeError("quota")
            return "=== PART 1 ===\na"

        out = run_recap(self.groups(), gem, None, lambda s, p: None, sleep=lambda s: None)
        self.assertEqual([p["n"] for p in out["parts"]], [1])
        self.assertEqual(out["parts"][0]["audio_file"], "")
        self.assertEqual(len(out["warnings"]), 2)
        self.assertIn("2", out["warnings"][0])
        self.assertIn("quota", out["warnings"][1])

    def test_all_fail(self):
        def gem(g):
            raise RuntimeError("x")

        with self.assertRaises(ValueError):
            run_recap(self.groups(), gem, None, lambda s, p: None, sleep=lambda s: None)

    def test_tts_failure_is_warning(self):
        def bad(n, t):
            raise RuntimeError("voice down")

        out = run_recap([{"first": 1, "last": 1, "prompt": "p"}], lambda g: "=== PART 1 ===\na", bad,
                        lambda s, p: None, sleep=lambda s: None)
        self.assertEqual(out["parts"][0]["audio_ms"], 0)
        self.assertEqual(len(out["warnings"]), 1)


if __name__ == "__main__":
    unittest.main()
