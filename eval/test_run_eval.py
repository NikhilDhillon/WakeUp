import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_eval as e


def answer(name, p):
    return {"type": "predicate", "name": name, "probability": p}


def good():
    return {"answers": [answer(c, 0.02 if c == "looks_like_photo_of_screen_or_print" else 0.95) for c in e.CHECKS]}


class EvalTests(unittest.TestCase):
    def test_parse_and_invert_screen_check(self):
        conf = e.confidences(e.parse_answers(good()))
        self.assertAlmostEqual(conf["looks_like_photo_of_screen_or_print"], 0.98)
        self.assertAlmostEqual(conf["same_place"], 0.95)

    def test_missing_answer_raises(self):
        response = good()
        response["answers"].pop()
        with self.assertRaises(RuntimeError):
            e.parse_answers(response)

    def test_refusal_raises(self):
        with self.assertRaises(RuntimeError):
            e.parse_answers({"answers": [{"type": "refusal", "refusal": "no"}]})

    def test_per_check_offsets_change_the_bar(self):
        conf = e.confidences(e.parse_answers(good()))
        conf["appears_awake"] = 0.62
        self.assertFalse(e.passes(conf, "normal", {}))  # 0.62 < 0.70
        self.assertTrue(e.passes(conf, "normal", {"appears_awake": -0.10}))  # bar is 0.60
        conf["same_place"] = 0.72
        self.assertFalse(e.passes(conf, "normal", {"same_place": 0.05}))  # bar is 0.75

    def test_body_matches_the_apps_shape(self):
        body = e.build_body(b"x", [b"r1", b"r2"], "me in the washroom", "Give a thumbs up")
        self.assertEqual(body["model"], "gpt-6-luna")
        self.assertEqual([q["name"] for q in body["questions"]], e.CHECKS)
        user = body["input"][1]["content"]
        self.assertEqual(sum(1 for part in user if part["type"] == "input_image"), 3)
        self.assertIn("me in the washroom", body["questions"][2]["instructions"])

    def test_suggestion_finds_a_gap(self):
        results = [
            {"expected": "pass", "target": None, "conf": {c: 0.9 for c in e.CHECKS}},
            {"expected": "fail", "target": "same_place", "conf": {**{c: 0.9 for c in e.CHECKS}, "same_place": 0.2}},
        ]
        line = [l for l in e.suggest(results, {}) if "same_place" in l][0]
        self.assertIn("separable", line)


if __name__ == "__main__":
    unittest.main()
