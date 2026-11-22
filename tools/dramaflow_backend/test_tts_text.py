import unittest

from tts_text import normalize_for_tts, number_words


class NumberTests(unittest.TestCase):
    def test_words(self):
        self.assertEqual(number_words(0), "သုံည")
        self.assertEqual(number_words(7), "ခုနစ်")
        self.assertEqual(number_words(10), "ဆယ်")
        self.assertEqual(number_words(11), "ဆယ့်တစ်")
        self.assertEqual(number_words(20), "နှစ်ဆယ်")
        self.assertEqual(number_words(25), "နှစ်ဆယ့်ငါး")
        self.assertEqual(number_words(99), "ကိုးဆယ့်ကိုး")
        with self.assertRaises(ValueError):
            number_words(100)


class NormalizeTests(unittest.TestCase):
    def test_small_numbers_spelled(self):
        self.assertEqual(normalize_for_tts("သူက 25 နှစ်"), "သူက နှစ်ဆယ့်ငါး နှစ်")

    def test_other_numbers_kept(self):
        for t in ("2024 ခုနှစ်", "3.5 ကီလို", "12:30 မှာ", "1,000 ယွမ်", "3/4", "1-2 ရက်", "v1.2.3"):
            self.assertEqual(normalize_for_tts(t), t, t)

    def test_emoji_marks_brackets(self):
        self.assertEqual(normalize_for_tts("**ကောင်းပါတယ်** 😀🔥 (ရယ်သံ) ပြီးပြီ"), "ကောင်းပါတယ် ပြီးပြီ")

    def test_lines_and_spaces(self):
        self.assertEqual(normalize_for_tts("a   b\n\n  c  "), "a b\nc")

    def test_never_empty(self):
        self.assertEqual(normalize_for_tts("😀"), "😀")
        self.assertEqual(normalize_for_tts(""), "")


if __name__ == "__main__":
    unittest.main()
