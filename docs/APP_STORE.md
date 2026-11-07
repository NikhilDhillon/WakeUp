# Publishing WakeUp: what you need

The app works for you today with a free Apple ID, but the build expires after 7 days. Anything beyond your own phone needs these.

## 1. Apple Developer Program ($99 a year)

- Needed for TestFlight, the App Store, and builds that don't expire.
- After joining, change the signing team in Xcode (Signing & Capabilities) and keep the bundle ID or pick a new one.
- AlarmKit needs no special entitlement; keep the `NSAlarmKitUsageDescription` text in `Config/Info.plist`.

## 2. A shared backend

Other people can't be asked to bring an OpenAI key. Deploy `proxy/` (see [proxy/README.md](../proxy/README.md)), then in the app choose **Settings > Check with > WakeUp service** and enter its address. Set a spend limit on the OpenAI key you give the proxy.

Before wide release, replace the per-device counter with Apple's App Attest so a copied app can't use the service. That needs the paid program.

## 3. App Store Connect answers

**App Privacy ("nutrition label")**

| Question | Answer |
|---|---|
| Data collected: Photos or Videos | Yes. Used for app functionality (checking the proof photo). Not linked to the user's identity. Not used for tracking. |
| Data collected: other | Device ID is a random per-install value used only for rate limiting; declare it as Identifiers > Device ID, app functionality, not linked, not tracking. |
| Tracking | No |

With the on-phone check or the user's own OpenAI key the app itself collects nothing; the answers above cover the hosted service.

**Privacy policy URL:** host [PRIVACY.md](PRIVACY.md) as a web page.

**In-app notice:** done. Before the first photo is sent, the app asks the user to agree (and Setup explains it).

## 4. Review notes (paste into App Store Connect)

> WakeUp is an alarm app. AlarmKit always shows a Stop button, so each wake-up is a chain of alarms a few minutes apart. The alarm's "Prove I'm up" button opens the app, where the user takes a live photo that an AI checks against their reference photos. When the check passes, the rest of the chain is cancelled.
>
> To review without a key: Settings > Check with > "On this phone only". Create a proof in Setup (reference photos can be any 3 photos of a room), add an alarm for a minute from now, and when it rings choose "Prove I'm up". The "Stop alarms without proof" button on the wake screen is always available if no proof is set up, so a user can't be trapped.

## 5. Before submitting

- [ ] Real-device pass of every check in [PHONE_TESTS.md](PHONE_TESTS.md)
- [ ] A week of real mornings with no surprises
- [ ] Screenshots, description, age rating (4+), support URL
- [ ] Privacy policy hosted and linked
