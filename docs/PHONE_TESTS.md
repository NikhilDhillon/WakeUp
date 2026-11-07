# Testing WakeUp on your iPhone

Everything here needs the real phone (the simulator can't do alarms, the camera or the ringer switch). Do it in order; each part builds on the last. Tick a box only when you saw it happen. Write down anything odd, with the time, for the notes at the end.

**Before you start**

- [ ] Install from Xcode onto the phone (scheme `WakeUp`, your Personal Team). Note the date: a free Apple ID build stops opening after 7 days.
- [ ] Have your OpenAI key ready, and a spot with the lighting and room you'll use in the morning.
- [ ] Settings > Developer tools on (in the app), so you can see what's scheduled.

## 1. Setup flow (5 min)

- [ ] First launch shows the setup screens. **Allow alarms** and **Allow camera** each show a checkmark afterwards.
- [ ] Paste the key, **Save key and agree**. It shows "OpenAI key saved on this iPhone".
- [ ] Create a proof. **Take photos now** opens the back camera; 3 photos fill it, and Save works.
- [ ] Practice run: take a photo doing the challenge. The result card appears with a pass or a list of failed checks.
- [ ] Add the 7:00 weekday alarm (or choose your own). Finish.
- [ ] Settings > Run setup again opens the flow again.

## 2. The AI check

- [ ] **Saving the key** worked in step 1; also try Settings > Remove key, then save it again.
- [ ] **A pass:** practice with the right place and challenge. Note how long the check took (History shows it later).
- [ ] **A fail:** practice in a different room, then with the wrong gesture, then with nobody in the shot. Each should fail and name the check that missed.
- [ ] **A bad key:** save a wrong key (for example `sk-test`). Expect "OpenAI didn't accept the API key". Then, with **Check on this phone if offline** on, the check falls back and says "Checked offline". Put the right key back.
- [ ] **Camera:** front and back both work (flip button). Photos are upright.
- [ ] Dim light: try a practice photo in bad morning light. If an honest photo fails, note which check missed (this is what `eval/run_eval.py` is for).

## 3. The alarm button and silent mode

- [ ] Developer tools > **Ring in 1 minute** with 3 alarms, 1 minute apart. Lock the phone.
- [ ] It rings on the Lock Screen with a **Prove I'm up** button.
- [ ] **Prove I'm up** silences that ring and opens WakeUp (it may ask for Face ID first). The wake screen shows the challenge and your proof.
- [ ] Choose **Not yet**. The next alarm in the chain still rings.
- [ ] Repeat with the **ringer switch on silent**: it still rings.
- [ ] Pass the check. The remaining alarms in the chain are cancelled (Developer tools list shows them gone).
- [ ] Open an alarm, set Sound to **Loud beeps**, and set it a few minutes ahead. Confirm the loud tone plays when it rings. (Developer test chains always use the standard sound.)

## 4. A full morning

Set a real alarm for every day, 5 minutes from now. Follow-up after 5 minutes.

- [ ] It rings. Tap **Prove I'm up**, pass.
- [ ] About 5 minutes later **Still up?** rings, with a *different* challenge. Pass it. The morning ends.
- [ ] Try failing the follow-up and ignoring it: it keeps ringing through its 4 alarms.
- [ ] History shows the morning: time up, number of tries, and the follow-up result.
- [ ] Change the alarm time to the next day's morning, **don't open the app** the next day, and let it ring. Do this two days in a row (set it for tomorrow and the day after). Confirm it rings both days without opening WakeUp in between.
- [ ] Skip: tap **Skip Fri** (or the next day) on an alarm and confirm that day doesn't ring. Try a third skip within a week: it should be refused.

## 4b. The redesigned screens (10 min)

- [ ] **Home:** the pill under "Alarms" says "Ready for tomorrow" (or the right day). The Next Up card shows the alarm that rings next, its countdown, days and place.
- [ ] **Skip:** the chip names the next morning ("Skip Monday"); tapping it moves the card to the next real ring and the chip becomes "Undo skip". With 2 skips already in that week it is greyed out and says why.
- [ ] **Problems:** turn off camera access in iOS Settings; the pill changes to "Camera is blocked" with an **Open Settings** button. Put it back.
- [ ] **Difficulty:** in the alarm editor Gentle, Firm and Relentless set the ring count, gap and follow-up; **Customize** shows the individual settings.
- [ ] **Wake screen:** it is full white even in dark mode, shows "Ring 2 of 10" and the next ring time under "Not yet", and **Show photos** reveals the reference photos.
- [ ] **Brightness:** the screen goes to full brightness on the wake screen. If you force-quit the app while it's up, brightness stays high until the phone locks (expected).
- [ ] Largest Dynamic Type size and VoiceOver on Home and the wake screen: everything reachable, the Next Up card reads as one item with Skip, Edit and Turn off actions.

## 5. Odd situations

- [ ] **Restart overnight:** restart the phone in the evening, don't open WakeUp, and confirm the morning alarm still rings.
- [ ] **Low Power Mode on:** the home screen shows the warning; alarms still ring.
- [ ] **Airplane mode, then a check:** the check retries once, then says "Checked offline", and a follow-up is scheduled even if the alarm has follow-up off.
- [ ] **On-phone only** (Settings > Check with): a face in the right room passes; an empty room fails. Note whether the same-place result feels right: this is the untested one.
- [ ] **Time zone:** change the phone's time zone (Settings > General > Date & Time), reopen WakeUp, and confirm the alarms are rescheduled for the new zone (Developer tools list).
- [ ] **Delete a proof an alarm uses:** the delete prompt says how many alarms use it; afterwards the alarm still has something to check against.
- [ ] **Large text:** Settings > Display & Brightness > Text Size to the largest; the wake screen scrolls and both buttons are reachable.
- [ ] **VoiceOver:** the shutter button, the result and the challenge are read out.
- [ ] **How many alarms:** with several alarms of 10 rings each, open Developer tools. If an "iOS only allows N alarms" message appears, write N down.

## 6. A week of real mornings

Use it as your real alarm for a week. Reinstall from Xcode on day 5 or 6 (the home screen warns from day 5). Keep notes:

| Date | Rang on time? | Tries to pass | Wrongly failed? | Wrongly passed? | Anything odd |
|---|---|---|---|---|---|
| | | | | | |

## What to send back

- Anything that failed above, with the step number.
- The alarm limit N, if you hit it.
- Honest photos that failed: put the photos in `eval/photos/` and run `python3 eval/run_eval.py` (see `eval/README.md`) so the thresholds can be tuned.
- Whether the on-phone check told rooms apart.
