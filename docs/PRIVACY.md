# WakeUp privacy policy (draft)

_Draft for the App Store listing. Have it read over, and fill in the contact address and your name or company, before publishing._

WakeUp is an alarm that stops once you prove you're out of bed with a live photo.

## What the app handles

| Data | Where it goes | How long |
|---|---|---|
| Reference photos of your place | Stored on your iPhone. Sent with each check to the checking service. | Until you delete the proof |
| The live photo you take each morning | Sent to be checked, then discarded by WakeUp. A tiny 200 px thumbnail is kept on your iPhone only if you turn that on. | Not kept by default |
| Your proof description and today's challenge | Sent with the photo | Not kept by WakeUp |
| Alarm times, history, streak | Your iPhone only | Until you delete them |
| Your OpenAI key (if you use your own) | iPhone Keychain; sent only to OpenAI | Until you remove it |
| A random device ID (hosted service only) | Sent to the WakeUp service to count checks per device | Counters expire after about a day and store a hash of the ID |

## Who sees your photos

- **Your own OpenAI key:** photos go from your iPhone straight to OpenAI. OpenAI's policy applies. WakeUp sets `store: false` on Responses API requests.
- **WakeUp service:** photos go to the service, which forwards them to OpenAI and keeps nothing.
- **On-phone check:** photos never leave your iPhone.

WakeUp has no accounts, no analytics, no ads and no tracking.

## Your choices

You can choose the on-phone check in Settings, delete any proof, clear history, and remove your key at any time. Deleting the app removes everything stored on your iPhone.

## Contact

_Add a contact address._
