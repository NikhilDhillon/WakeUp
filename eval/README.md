# Checking the AI check

`run_eval.py` sends labelled test photos through the Decisions API with the same questions the app uses, and shows how each check scored. Use it to pick a strictness, to tune per-check thresholds, and to see which question to reword. Rerun it whenever a question, the model or a threshold changes.

## Set up (about 20 minutes)

1. **A proof.** In `eval/proof/` put `config.json`:

   ```json
   { "description": "Me sitting in the washroom with the light on", "challenge": "thumbsUp" }
   ```

   `challenge` is one of `threeFingers`, `twoFingers`, `thumbsUp`, `peaceSign`, `handOnHead`, `pointUp`. Put 3–5 reference photos in `eval/proof/reference/`.

2. **Honest photos** in `eval/photos/pass/`: 8–12 photos of you in that place doing that challenge, at your real morning light (dim, blurry, half-awake).

3. **Cheats and mistakes** in `eval/photos/fail/`. Put photos that should fail *one particular check* in a folder named after it, so the script can suggest thresholds:

   | Folder | Photos to take |
   |---|---|
   | `fail/same_place/` | the right pose in a different room |
   | `fail/person_present/` | the right place, nobody in it |
   | `fail/challenge_completed/` | the right place, wrong gesture or no gesture |
   | `fail/appears_awake/` | you lying in bed, eyes closed |
   | `fail/looks_like_photo_of_screen_or_print/` | a photo of a screen showing an old pass photo |
   | `fail/` (loose) | anything else that should fail |

   Aim for 2–4 photos per folder. Photos stay on your Mac; the folders are git-ignored.

4. Optional: `eval/thresholds.json` such as `{"same_place": 0.05, "appears_awake": -0.10}` to try other per-check offsets (added to the strictness level).

## Run

```bash
export OPENAI_API_KEY=sk-...
python3 eval/run_eval.py
```

It needs macOS (it shrinks photos with `sips` the way the app does) and costs a few cents. `--dry-run` builds the requests without calling the API. `python3 eval/test_run_eval.py` runs the script's own tests.

## Reading the result

- Each photo shows every check's confidence and whether it passes at lenient (50%), normal (70%) and strict (85%).
- The summary says, per strictness, how many honest photos passed and how many cheats were caught, and names the photos it got wrong.
- **Per-check suggestion** compares the lowest honest score for a check with the highest score among cheats meant to fail it. "separable" gives a threshold between them; "overlap" means the question or the photos need work.

To use a result in the app, change `ProofThresholds.offsets` (and the default strictness) in `WakeUp/Settings/AppSettings.swift`, and change `DEFAULT_OFFSETS` here to match.
