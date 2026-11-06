# WakeUp: build plan

An iPhone alarm that keeps ringing until an AI checks a live photo and agrees you're out of bed.

This plan covers every phase: what's built, what's left, and how each remaining phase gets done. It's written for one user (you) on one iPhone. Phase 7 covers what changes if other people use it.

_Last updated: November 6, 2026_

## At a glance

| Phase | What | Status | Effort |
|---|---|---|---|
| 0 | Project setup and signing | ✅ Done | — |
| 1 | Alarm chain and "Prove I'm up" button | ✅ Built, one item to check on the phone | — |
| 2 | Proofs: description and reference photos | ✅ Done | — |
| 3 | Live camera and the AI check (Decisions API) | ✅ Built, needs a real run with your key | — |
| 4 | Real morning alarms: repeating days and the follow-up check | ✅ Built, unit tested; not yet run on the phone | — |
| 5 | Accuracy, offline backup and history | ✅ Built, unit tested; the photo evaluation needs your photos | — |
| 6 | Polish and first-run setup | ✅ Built (no widget); needs a week of real mornings | — |
| 7 | Optional: sharing it with other people | ✅ Code and docs in the repo; needs the paid program to ship | — |

**Everything from phase 3 on has only been tested in the simulator and with unit tests.** Run the phone checks in [Open checks](#open-checks) and the phase 4 morning test below before trusting it.

### What was built differently from the plan

- **Scheduling (4.2):** I used the fallback. Each alarm keeps fixed-date chains scheduled for the next four calendar days, topped up when the app opens, after every pass, on a time-zone change, and by a background refresh (`BGAppRefreshTask`). I couldn't test how AlarmKit treats repeating alarms when one is stopped, so I built on fixed alarms, which are known to work. If iOS refuses alarms (`maximumLimitReached`) the app learns the limit and schedules fewer days. The limit is still unknown.
- **Follow-up (4.4):** the "Still up?" chain is 4 alarms with a different challenge. Ignoring it just keeps ringing, which is the "back into the main chain" behaviour; a chain that rings out unanswered is recorded as "went back to bed".
- **Per-check thresholds (5.1):** the mechanism and starting offsets are in (`ProofThresholds`: place +5, awake −10 points). They're guesses until `eval/run_eval.py` runs on your photos.
- **Offline distances (5.2):** the Vision feature-print distances that count as the "same place" are starting values too.
- **Lock Screen widget (6):** skipped. It needs a new Xcode target, which is risky in a hand-written project file, and it was optional.
- **Phase 7:** the Cloudflare Worker (`proxy/`), the in-app service address, the photo-upload notice, an on-phone-only mode, and drafts of the privacy policy and App Store notes (`docs/`) are done. The Developer Program, App Attest and a real hosted deployment are not.

### Phase 4 test on the phone

Set an alarm for every day a few minutes ahead, pass it, and check the follow-up rings and the next morning rings without opening the app.

---

## Decisions so far

| Decision | Choice | Why |
|---|---|---|
| Platform | iPhone only, SwiftUI, iOS 26.1+ | AlarmKit is the only way an app's alarm can ring through silent mode, and it's Swift-only |
| Alarm escape | A **chain** of alarms a few minutes apart, cancelled only by a pass | AlarmKit always shows a Stop button that apps can't remove |
| AI check | OpenAI **Decisions API**, `gpt-6-luna` | One `predicate` per check returns a probability; input-only billing (about $0.10 per million tokens); reported to be much faster than the Responses API |
| Backup method | OpenAI Responses API (Settings switch) | Gives a written reason when you want one |
| Pass rule | Decided in code: **every** check must reach the strictness level | Predictable; the AI can't talk its way into a pass |
| Swappable AI | Everything goes through the `WakeVerifier` protocol | Jev, Claude or an on-phone model can be added later without touching the rest |
| API key | iPhone Keychain, this device only | Never in the repo, never synced |
| Commits | You are the only author, no co-author lines | Your request |

---

## Phase 0: Setup ✅

- Xcode project (hand-written, using folder-synced groups), bundle ID `com.nikhildhillon.WakeUp`, your free Personal Team.
- Private GitHub repo with a README.

## Phase 1: Alarm chain ✅

- `AlarmService` schedules a chain of AlarmKit alarms (for example 7:00, 7:03, 7:06 …) and cancels the rest of it after a pass.
- The ringing alarm has a camera button, **Prove I'm up** (`ProveAwakeIntent`), that silences the ring and opens the proof screen.
- Opening the app while a chain is going jumps straight to the proof screen.
- **Open:** in the simulator, the Prove I'm up button fails with "Could not find an intent". The likely cause is that simulator builds aren't signed with your team. It needs checking on the phone. If it still fails there, the chain still works and opening the app yourself still gets you to the proof screen.

## Phase 2: Proofs ✅

- A proof is a name, a description ("me sitting in the washroom with the light on") and 3–5 reference photos, stored with SwiftData. Photos are shrunk to 1024 px.
- You can keep several proofs and pick which one the alarm uses.

## Phase 3: Camera and AI check ✅

- A live camera only: no photo library on the phone.
- Six checks, each judged by its own probability: `same_place`, `person_present`, `matches_description`, `challenge_completed`, `appears_awake` and `looks_like_photo_of_screen_or_print` (this last one must be unlikely).
- A random challenge each morning ("hold up 3 fingers", "thumbs up" …).
- Settings for the key, the API (Decisions or Responses) and strictness (50 / 70 / 85%).
- **Practice with this proof** shows what the AI says without touching any alarms.
- If there's no proof or no key, the wake screen offers **Stop alarms without proof**, so a setup problem can't trap you.
- 30 unit tests. A mock verdict (`-WakeUpMockVerdict pass|fail`) lets you test without a key.

---

## Phase 4: Real morning alarms ✅

**Goal:** set it once ("weekdays at 7:00") and it works every morning without you opening the app the night before. After you pass, a follow-up check makes sure you didn't go back to bed.

### 4.1 Alarm model

A new SwiftData model, `WakeAlarm`:

| Field | Example |
|---|---|
| `time` | 7:00 |
| `weekdays` | Mon–Fri |
| `missionID` | Washroom |
| `isEnabled` | true |
| `chainLength` / `chainInterval` | 10 alarms, 3 min apart |
| `followUpDelay` | 12 min (0 = off) |

The home screen becomes a list of alarms with an add/edit screen. The current "Quick test" and "Morning alarm" sections move behind a **Developer** switch in Settings.

### 4.2 Scheduling that survives without the app

Today a chain covers one morning only, and the app must open to set up the next. Two ways to fix that:

1. **Repeating chain (preferred).** Each slot in the chain (7:00, 7:03 …) is an AlarmKit `.relative` alarm that repeats `.weekly(days)`. AlarmKit then rings every chosen morning on its own. After a pass, the app cancels the remaining slots and adds them back as repeating, so they skip today and return tomorrow.
2. **Fallback if (1) misbehaves:** schedule fixed-date chains for the next 2 mornings and refresh them every time the app opens, plus a nightly background refresh (`BGAppRefreshTask`).

**First task of the phase:** a short test on the phone of how AlarmKit treats repeating alarms when one is stopped or cancelled. It also needs to find how many alarms iOS allows (`maximumLimitReached`). A 10-slot chain × several alarms could hit the limit, so the editor will cap the total.

### 4.3 Wake state

A small saved state machine replaces today's `ChainStore` and `lastPassed`:

```
idle → ringing → passed → followUpRinging → done
           ↑______________________|  (follow-up failed or ignored)
```

It's stored so a crash or restart mid-morning resumes in the right place.

### 4.4 Follow-up check

- After a pass, one alarm (a short chain of 2–3) is scheduled at +`followUpDelay`, titled "Still up?".
- It uses the same proof but a **different** challenge.
- Ignoring it or failing it puts you back into the main chain.
- A pass ends the morning and is recorded.

### 4.5 Skip a day

**Skip tomorrow** on an alarm, for a sick day or a day off. It has to be done the day before, from the home screen, never while ringing. A cap (for example 2 per week) stops it becoming an escape hatch.

### 4.6 Tests

- Unit tests for the next-occurrence date math (weekdays, a week wrapping, daylight-saving changes, time zones).
- Unit tests for the state machine and the skip cap.
- On the phone: a full morning at a near-future time, both the main chain and the follow-up.

**Done when:** an alarm set for "every day at 7:00" rings two mornings in a row without the app being opened in between, and the follow-up catches going back to bed.

---

## Phase 5: Accuracy, offline backup and history ✅

**Goal:** trust the check. It should pass honest morning photos, catch cheats, and still work without the internet.

### 5.1 Test-photo evaluation

- Take about 20–30 labelled photos:
  - **pass:** you in the washroom doing a challenge
  - **fail:** in bed, an empty room, a different room, a photo of a screen, the wrong challenge
- A small script (`eval/run_eval.py`, run on your Mac with your key in an environment variable) sends each one through the Decisions API with the same questions the app uses. It prints each check's probability and whether the photo would pass at 50 / 70 / 85%.
- Use the results to:
  - set the default strictness
  - possibly set a **different threshold per check** (for example strict on `same_place`, looser on `appears_awake`)
  - reword any question that keeps misjudging
- Rerun the script whenever a question or the model changes.

### 5.2 Offline and API-failure backup

When OpenAI can't be reached (no Wi-Fi, an outage, credits gone) after a retry:

- **On-phone check** with Apple's Vision framework:
  - a face must be in the photo (`VNDetectFaceRectanglesRequest`)
  - the photo must look like your reference photos (`VNGenerateImageFeaturePrintRequest` distance)
- It's weaker than the AI (no challenge check, no description check), so the result screen says "Checked offline" and the follow-up check is always required that morning.
- Plus a retry with a short timeout (about 20 s) and one automatic retry before falling back.

### 5.3 History and streak

- A new SwiftData model, `ProofAttempt`: time, proof, method (Decisions / Responses / offline), each check's probability, pass or fail, how long the check took, and input tokens.
- A **History** screen: each morning's attempts, how many tries it took, and the time you were up. Plus a streak.
- Wake photos are **not** kept by default (privacy). An optional setting keeps a small thumbnail.

**Done when:** the evaluation script shows the chosen strictness passes all the honest photos and fails all the cheat photos (or you've accepted the misses), and a check with Wi-Fi off still lets you pass.

---

## Phase 6: Polish and first-run setup ✅

- **First-run setup:** permissions, then the API key, then the first proof (with a "take reference photos now" camera option), then a practice run, then the first alarm.
- **App icon and sounds:** a real icon, and a louder custom alarm sound if AlarmKit's sound options allow it.
- **Edge cases:**
  - the phone restarts overnight (AlarmKit alarms persist; check that the app's state does too)
  - time zone changes and daylight saving
  - the alarm rings while the phone is locked and the camera opens from the Lock Screen
  - low battery or Low Power Mode
  - removing or changing a proof that an alarm uses
- **Accessibility:** Dynamic Type, VoiceOver labels on the camera and result screens, and enough contrast in dark mode.
- **Optional:** a Lock Screen widget showing the next alarm and your streak.

**Done when:** a fresh install on your phone goes from first launch to a working alarm without help, and a week of real mornings has no surprises.

---

## Phase 7 (optional): Sharing it with other people ✅ (code and docs)

Only needed if anyone else will use it.

- **API keys:** each user can't be expected to bring their own. Add a small proxy (for example a Cloudflare Worker) that holds the key and forwards check requests. Add per-device rate limits so a leaked app can't drain your credits.
- **Apple Developer Program** ($99 a year): needed for TestFlight, the App Store, and for the app to keep working past 7 days.
- **App Store needs:**
  - a privacy policy
  - App Privacy details (photos sent to a third party for analysis)
  - a clear in-app notice that photos are checked by OpenAI
  - review notes explaining the alarm chain
- **Model choice per user:** the `WakeVerifier` protocol already allows another provider, or an on-phone model such as a small Jev or Gemma vision model for people who don't want photos leaving the phone.

---

## Open checks

These need your iPhone and your OpenAI key. Still open.

| # | Check | Why it's open |
|---|---|---|
| 1 | Tapping **Prove I'm up** on the ringing alarm opens the proof screen | Fails in the simulator ("Could not find an intent"), most likely because simulator builds aren't team-signed |
| 2 | Saving an API key in Settings | The simulator's lagging taps made this impractical to test |
| 3 | A real Decisions API check: a pass, a fail and a bad key | Built from OpenAI's guide; refusal and error shapes aren't fully documented |
| 4 | The live camera, front and back | The simulator has no camera |
| 5 | The alarm rings with the ringer switch on silent | AlarmKit's main promise; simulator only |
| 6 | The on-phone check tells a different place from the right one | In the simulator Vision's image comparison reports distance 0 for very different images, so the "same place" distances (`OfflineVerifier.sameDistance` / `differentDistance`) are untested and untuned |
| 7 | A full morning: repeating mornings without opening the app, then the follow-up | Phase 4's done-when; only unit tested |

## Risks

| Risk | What happens | Plan |
|---|---|---|
| AlarmKit limits the number of alarms | Long chains × several alarms fail to schedule | Find the limit in the phase 4 test; cap chain length in the editor |
| Repeating alarms behave unexpectedly when cancelled | Mornings get skipped, or slots ring after a pass | Phase 4 test first; fall back to fixed chains plus background refresh |
| The Decisions API is new | Format changes or downtime | Responses API switch in Settings; offline backup in phase 5 |
| The AI is too strict on real dim morning photos | Annoying fails while the alarm rings | Phase 5 evaluation; per-check thresholds |
| Free Apple ID | The app stops opening after 7 days | Reinstall from Xcode weekly, or join the Developer Program |
| No internet in the morning | Can't pass | Phase 5 offline check |
