# TiltFace

A watchOS app that looks like a watch face: 40 physics pieces (tennis balls, gold bars, diamonds or basketballs) that slide to the lowest corner when you tilt your wrist, with the time and date drawn on top.

SwiftUI + SpriteKit (`SpriteView`), CoreMotion `deviceMotion` at 60 Hz mapped to `physicsWorld.gravity`.

## Build: no Mac needed

The pipeline is the same one partikel-capture uses:

1. A push to `main` (or *Actions → Watch build → Run workflow*) starts `.github/workflows/build.yml` on a Boat VM.
2. That calls `tools/codemagic_build.py`, which runs the `watch-unsigned` workflow in `codemagic.yaml` on a Codemagic Mac mini M2.
3. `tools/build.py` generates the project with pinned XcodeGen and compiles the **iPhone host app with the watch app embedded** (`TiltFace.app/Watch/TiltFaceWatch.app`). It checks both bundles and packages an unsigned IPA.
4. The IPA is published as a GitHub release of that commit: `TiltFace-<version>-build.<n>-<commit>-unsigned.ipa`.

One-time setup for the repo:
- Codemagic: *Add application → GitHub → SVRN-Digital/tiltface* (the codemagic.yaml workflow is picked up automatically).
- GitHub: repository secret `CODEMAGIC_TOKEN` (the same token partikel-capture uses).
- boat.dev: add this repository so the `runs-on: boat` job has a runner.

## Install on the watch (Windows)

1. Download the IPA from the latest release.
2. In Sideloadly, select the **iPhone paired with the watch**, drop the IPA and sign with your Apple ID.
3. On the iPhone, open the Watch app → *My Watch* → *Available Apps* → TiltFace → *Install* (if it doesn't install automatically).
4. On the watch: *Settings → Privacy & Security → Developer Mode → On* if it asks.

The CI artifact is unsigned and not installable as-is. Watch apps installed through a sideloaded iPhone app aren't something this repo has proven yet. Report a build, a Sideloadly install and a working app on the wrist as three separate results.

Free Apple ID: signing lasts 7 days, and the host and watch app each use an App ID (the free tier allows 10 per 7 days). With a paid Developer account, the same build can go through TestFlight instead (Codemagic signing + App Store Connect API key).

## Using it

- **Tilt** your wrist: everything rolls downhill.
- **Tap**: shake (throws everything against gravity, with a haptic click).
- **Long-press**: settings. Pick the sprite set, or use *Flip tilt* if things roll uphill on your wrist/crown setup.
- To keep it as your "face": *Watch Settings → General → Return to Clock → TiltFace → After 1 hour*. Third-party watch faces aren't possible on watchOS, so this is an app.

## Layout

| Path | What |
|---|---|
| `Watch/` | The watch app: `BallScene` (physics + motion), `ContentView` (SpriteView, gestures), `FaceOverlay` (time/date), `SpriteStyle` + `SpriteArtwork` (4 sprite sets drawn in code, physics shapes), `SettingsView` |
| `iOS/` | Minimal iPhone host that carries the watch app |
| `WatchInfo.plist` | `WKApplication`, companion bundle ID, runs independently |
| `project.yml` | XcodeGen spec (two targets, watch app embedded in `Watch/`) |
| `tools/build.py` | Mac build + IPA packaging + bundle checks |
| `tools/codemagic_build.py` | Starts/follows the Codemagic build and publishes the release |

On a Mac: `xcodegen generate`, open `TiltFace.xcodeproj`, set your team, run the `TiltFaceWatch` scheme on the watch.
