#!/usr/bin/env python3
"""Run labelled test photos through the Decisions API, the way the app does.

Put photos like this (see eval/README.md):

    eval/proof/config.json          {"description": "...", "challenge": "thumbsUp"}
    eval/proof/reference/*.jpg      3-5 reference photos of the place
    eval/photos/pass/*.jpg          honest morning photos that should pass
    eval/photos/fail/*.jpg          cheats/mistakes that should fail (any reason)
    eval/photos/fail/<check>/*.jpg  photos that should fail one particular check,
                                    e.g. fail/same_place or fail/appears_awake

Then:

    export OPENAI_API_KEY=sk-...
    python3 eval/run_eval.py

It prints every check's confidence for every photo, whether the photo would
pass at lenient / normal / strict, and a suggested threshold per check.
Keep QUESTIONS, CHALLENGES and OFFSETS in step with the app
(WakeUp/Verify/VerifierPrompt.swift, Wake/Challenge.swift,
Settings/AppSettings.swift) and rerun whenever they change.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ENDPOINT = "https://api.openai.com/v1/decisions"
MODEL = "gpt-6-luna"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".heic"}

CHECKS = [
    "same_place",
    "person_present",
    "matches_description",
    "challenge_completed",
    "appears_awake",
    "looks_like_photo_of_screen_or_print",
]

LEVELS = {"lenient": 0.5, "normal": 0.7, "strict": 0.85}

# Per-check adjustment added to the strictness level (ProofThresholds.offsets
# in the app). Edit eval/thresholds.json to try other values.
DEFAULT_OFFSETS = {"same_place": 0.05, "appears_awake": -0.10}

CHALLENGES = {
    "threeFingers": "Hold up 3 fingers",
    "twoFingers": "Hold up 2 fingers",
    "thumbsUp": "Give a thumbs up",
    "peaceSign": "Make a peace sign",
    "handOnHead": "Put one hand on your head",
    "pointUp": "Point at the ceiling",
}

CONTEXT = (
    "You check whether someone has really gotten out of bed in the morning. "
    "You get reference photos of a place, the person's own description of what "
    "their proof photo should show, a small challenge they must do in the photo, "
    "and a new photo taken just now with the app's camera. Judge only the new "
    "photo. Be strict but fair: an honest, slightly blurry or dim morning photo "
    "should pass; a different room, nobody in the shot, or a missing challenge "
    "should not."
)


def question(check, description, challenge):
    return {
        "same_place": "The new photo was taken in the same place as the reference photos. Angle, zoom and lighting may differ; look for the same fixtures, walls, tiles, furniture or layout.",
        "person_present": "A real person is in the new photo (a face, or at least the body part doing the challenge).",
        "matches_description": f"The new photo shows what this description says: {description}",
        "challenge_completed": f"The person in the new photo is clearly doing this challenge: {challenge}",
        "appears_awake": "The person in the new photo looks up and about: eyes open, upright, not lying in bed.",
        "looks_like_photo_of_screen_or_print": "The new photo is a picture of a screen or of a printed photo (bezels, glare, moire, pixel grid, paper edges) rather than a live scene.",
    }[check]


def shrink(path):
    """JPEG at most 1024 px on the long side, like the app (uses macOS sips)."""
    out = Path(tempfile.mkdtemp()) / "photo.jpg"
    subprocess.run(
        ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "80", "-Z", "1024", str(path), "--out", str(out)],
        check=True, capture_output=True,
    )
    return out.read_bytes()


def image_part(data):
    return {
        "type": "input_image",
        "image_url": "data:image/jpeg;base64," + base64.b64encode(data).decode(),
        "detail": "auto",
    }


def build_body(photo, references, description, challenge_text):
    content = [{
        "type": "input_text",
        "text": f"Description of the proof photo: {description}\nToday's challenge: {challenge_text}\nPhoto taken at: 7:00 AM",
    }]
    for i, ref in enumerate(references, 1):
        content.append({"type": "input_text", "text": f"Reference photo {i} of {len(references)}:"})
        content.append(image_part(ref))
    content.append({"type": "input_text", "text": "New photo, taken just now with the in-app camera:"})
    content.append(image_part(photo))
    return {
        "model": MODEL,
        "input": [
            {"role": "developer", "content": [{"type": "input_text", "text": CONTEXT}]},
            {"role": "user", "content": content},
        ],
        "questions": [
            {"type": "predicate", "name": c, "instructions": question(c, description, challenge_text)}
            for c in CHECKS
        ],
    }


def parse_answers(response):
    """Probability per check, or raise if any answer is missing."""
    answers = response.get("answers", [])
    for a in answers:
        if a.get("type") == "refusal":
            raise RuntimeError("refused: " + str(a.get("refusal") or a.get("message") or "no reason"))
    probabilities = {
        a["name"]: min(max(float(a["probability"]), 0.0), 1.0)
        for a in answers
        if a.get("type") == "predicate" and a.get("name") in CHECKS and "probability" in a
    }
    if len(probabilities) != len(CHECKS):
        raise RuntimeError("missing answers: " + ", ".join(c for c in CHECKS if c not in probabilities))
    return probabilities


def confidences(probabilities):
    """How likely each check came out the way you want (screen check inverted)."""
    return {
        c: (1 - p if c == "looks_like_photo_of_screen_or_print" else p)
        for c, p in probabilities.items()
    }


def threshold(level, check, offsets):
    return min(max(LEVELS[level] + offsets.get(check, 0.0), 0.0), 1.0)


def passes(conf, level, offsets):
    return all(conf[c] >= threshold(level, c, offsets) for c in CHECKS)


def failed_checks(conf, level, offsets):
    return [c for c in CHECKS if conf[c] < threshold(level, c, offsets)]


def post(body, key):
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"HTTP {error.code}: {error.read().decode()[:300]}")


def load_cases(photos_dir):
    """[(path, expected 'pass'|'fail', check the photo should fail or None)]."""
    cases = []
    for path in sorted((photos_dir / "pass").glob("*")):
        if path.suffix.lower() in IMAGE_SUFFIXES:
            cases.append((path, "pass", None))
    fail_dir = photos_dir / "fail"
    for path in sorted(fail_dir.rglob("*")):
        if path.suffix.lower() not in IMAGE_SUFFIXES:
            continue
        sub = path.parent.name
        cases.append((path, "fail", sub if sub in CHECKS else None))
    return cases


def suggest(results, offsets):
    """For each check: the lowest honest-photo confidence vs the highest
    confidence among cheat photos that were meant to fail that check."""
    lines = []
    for c in CHECKS:
        honest = [r["conf"][c] for r in results if r["expected"] == "pass"]
        cheats = [r["conf"][c] for r in results if r["expected"] == "fail" and r["target"] == c]
        if not honest:
            continue
        low = min(honest)
        if not cheats:
            lines.append(f"  {c:38} honest photos start at {low:.0%}; no cheat photos for this check")
            continue
        high = max(cheats)
        if high < low:
            lines.append(f"  {c:38} separable: cheats <= {high:.0%}, honest >= {low:.0%}; try a threshold near {(high + low) / 2:.0%}")
        else:
            lines.append(f"  {c:38} overlap: a cheat reached {high:.0%} but an honest photo was {low:.0%}; reword the question or retake photos")
    return lines


def run(args):
    offsets = dict(DEFAULT_OFFSETS)
    thresholds_file = ROOT / "thresholds.json"
    if thresholds_file.exists():
        offsets.update(json.loads(thresholds_file.read_text()))

    config = json.loads((args.proof / "config.json").read_text())
    description = config["description"]
    challenge_text = CHALLENGES.get(config.get("challenge", "thumbsUp"), config.get("challenge"))
    references = [shrink(p) for p in sorted((args.proof / "reference").glob("*")) if p.suffix.lower() in IMAGE_SUFFIXES]
    if not references:
        sys.exit("No reference photos in " + str(args.proof / "reference"))

    cases = load_cases(args.photos)
    if not cases:
        sys.exit("No photos found in " + str(args.photos))

    key = os.environ.get("OPENAI_API_KEY")
    if not key and not args.dry_run:
        sys.exit("Set OPENAI_API_KEY first.")

    results = []
    for path, expected, target in cases:
        body = build_body(shrink(path), references, description, challenge_text)
        if args.dry_run:
            print(f"{path.relative_to(ROOT)}: {len(json.dumps(body)) // 1024} KB request")
            continue
        try:
            conf = confidences(parse_answers(post(body, key)))
        except RuntimeError as error:
            print(f"{path.relative_to(ROOT)}: ERROR {error}")
            continue
        results.append({"path": path, "expected": expected, "target": target, "conf": conf})
        print(f"\n{path.relative_to(ROOT)}  (should {expected}{' ' + target if target else ''})")
        for c in CHECKS:
            print(f"  {c:38} {conf[c]:6.1%}")
        print("  " + "  ".join(f"{level}: {'PASS' if passes(conf, level, offsets) else 'fail'}" for level in LEVELS))

    if args.dry_run or not results:
        return
    print_summary(results, offsets)


def print_summary(results, offsets):
    honest = [r for r in results if r["expected"] == "pass"]
    cheats = [r for r in results if r["expected"] == "fail"]
    print("\n=== Summary ===")
    print(f"per-check offsets: {offsets}")
    for level in LEVELS:
        ok = sum(passes(r["conf"], level, offsets) for r in honest)
        caught = sum(not passes(r["conf"], level, offsets) for r in cheats)
        print(f"{level:8} ({LEVELS[level]:.0%}): honest passed {ok}/{len(honest)}, cheats caught {caught}/{len(cheats)}")
        for r in honest:
            if not passes(r["conf"], level, offsets):
                print(f"           wrongly failed: {r['path'].name} ({', '.join(failed_checks(r['conf'], level, offsets))})")
        for r in cheats:
            if passes(r["conf"], level, offsets):
                print(f"           wrongly passed: {r['path'].name}")
    print("\nPer-check suggestion:")
    print("\n".join(suggest(results, offsets)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--proof", type=Path, default=ROOT / "proof")
    parser.add_argument("--photos", type=Path, default=ROOT / "photos")
    parser.add_argument("--dry-run", action="store_true", help="build the requests but don't call the API")
    run(parser.parse_args())


if __name__ == "__main__":
    main()
