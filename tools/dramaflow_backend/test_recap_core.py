"""Run:  python3 -m unittest test_recap_core   (no packages needed)"""
import unittest

from recap_core import fit_tempo, fit_warning, part_targets, with_context, mask_key, parse_reply, run_recap


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
        out = run_recap(self.groups(), lambda g: next(replies), lambda n, t, tg: (1000 * n, f"p{n}.wav"),
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
        def bad(n, t, tg):
            raise RuntimeError("voice down")

        out = run_recap([{"first": 1, "last": 1, "prompt": "p"}], lambda g: "=== PART 1 ===\na", bad,
                        lambda s, p: None, sleep=lambda s: None)
        self.assertEqual(out["parts"][0]["audio_ms"], 0)
        self.assertEqual(len(out["warnings"]), 1)


class FitTests(unittest.TestCase):
    def test_tempo(self):
        self.assertEqual(fit_tempo(10000, 0), 1.0)
        self.assertEqual(fit_tempo(10000, 10000), 1.0)
        self.assertEqual(fit_tempo(10100, 10000), 1.0)  # within 2%
        self.assertEqual(fit_tempo(5000, 10000), 1.0)  # never slowed down
        self.assertEqual(fit_tempo(11000, 10000), 1.1)
        self.assertEqual(fit_tempo(20000, 10000), 1.15)  # capped

    def test_warning(self):
        self.assertEqual(fit_warning(1, 10000, 10000), "")
        self.assertEqual(fit_warning(1, 10000, 0), "")
        self.assertIn("ရှည်", fit_warning(2, 12000, 10000))
        self.assertIn("တို", fit_warning(3, 3000, 10000))

    def test_targets(self):
        g = [{"first": 1, "last": 2, "prompt": "p", "part_ms": [5000, 7000]},
             {"first": 3, "last": 4, "prompt": "q", "part_ms": [1000]},  # wrong length: ignored
             {"first": 5, "last": 5, "prompt": "r"}]
        self.assertEqual(part_targets(g), {1: 5000, 2: 7000})

    def test_context_and_targets_reach_the_run(self):
        seen = []

        def gem(g):
            seen.append(g["prompt"])
            return "=== PART %d ===\n%s" % (g["first"], "စာ" * 400)

        got = []

        def tts(n, t, tg):
            got.append((n, tg))
            return 6000, f"p{n}.wav"

        groups = [{"first": 1, "last": 1, "prompt": "P1", "part_ms": [5000]},
                  {"first": 2, "last": 2, "prompt": "P2", "part_ms": [9000]}]
        out = run_recap(groups, gem, tts, lambda s, p: None, sleep=lambda s: None)
        self.assertEqual(seen[0], "P1")  # the first request has no context
        self.assertTrue(seen[1].startswith("P2"))
        self.assertIn("CONTEXT", seen[1])
        self.assertLessEqual(len(seen[1]), 600)
        self.assertEqual(got, [(1, 5000), (2, 9000)])
        self.assertEqual(out["parts"][0]["target_ms"], 5000)
        # 6 s of voice for a 5 s part is 20% long: warned; 6 s for 9 s is fine
        self.assertEqual(len(out["warnings"]), 1)
        self.assertIn("အပိုင်း 1", out["warnings"][0])

    def test_with_context_empty(self):
        self.assertEqual(with_context("P", "  "), "P")


if __name__ == "__main__":
    unittest.main()
