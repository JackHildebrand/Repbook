# Repbook for iPhone — initial native version

SwiftUI app targeting iOS 17+, with ActivityKit Lock Screen/Dynamic Island controls and a WidgetKit Home Screen launcher. No server, subscription, push notifications, or Apple login is used by the app.

## Implemented

- Upper/Lower routines, exercise search/custom exercises, editable working sets, 0–2 warmup sets (default 2).
- Reorder mode collapses exercises to names and uses native list drag handles; ordinary scrolling does not initiate a reorder. This first version uses an explicit Reorder button rather than the web app's long-press gesture.
- Active workout, previous working weight/reps, log/unlog, add/delete sets, add exercises, automatic rest countdown, finish/discard, local history.
- Atomic on-device JSON persistence, native backup export/import, and migration from the latest web app JSON export including active workouts and exercise IDs. Web-specific notes/PR metadata are not yet represented; retain the original export.
- Local Live Activities with current exercise/set, weight/reps adjustment buttons and log button. Requests identify both session and set so repeated/stale Log taps cannot log the following set. LiveActivityIntent executes in the host app; no shared App Group container is required for these controls.
- Home Screen launcher widget. Workout summaries/charts and routine-specific interactive widgets are future work.
- Unit changes convert all saved weights rather than relabeling them.

## Build on a Mac

1. Install Xcode and XcodeGen (`brew install xcodegen`).
2. In this directory run `swift test`, then `xcodegen generate`.
3. Open `Repbook.xcodeproj`, choose your signing team for **both** targets and unique bundle IDs if necessary, then Run on your iPhone.
4. Allow Live Activities for Repbook in iOS Settings. Start a workout and lock the phone to test controls.

The GitHub **Native iOS** workflow runs core migration tests, builds app + extension for Simulator and iPhone, and uploads `Repbook-unsigned.ipa`. This IPA must be signed for the device before installation; it is not installable directly. No Apple credentials belong in the repository or workflow. Free-account signing/refresh behavior and extension retention depend on the chosen installer and must be verified on the user's device. Do not strip the widget extension: it contains the Live Activity UI.

## Transfer existing workouts

In the currently installed web app, use Settings/Data → Export JSON. Keep the original as a backup. In the native app choose Settings → Import Repbook backup and confirm replacement. Data on different origins, Safari, and the native app does not migrate automatically. Native exports are intended for this native app.

## Device acceptance checklist

- Install with both app and widget extension signed; confirm Live Activities are allowed.
- Import a copy of real web data and compare routines, history, warmups, and active workout.
- Start a workout; check Lock Screen and compact/expanded Dynamic Island.
- Adjust weight/reps and log while app is backgrounded; verify the same values in-app after unlocking. Rapidly double-tap Log; verify only one set was logged.
- Finish/discard clears the Live Activity. Disable Live Activities and verify normal logging still works.
- Force quit/reopen, restart phone, and confirm workout recovery. Live Activity restart may require foregrounding.
- Add the Home Screen launcher; test large text and VoiceOver.
- Verify installer refresh retains data and includes the extension before relying on automatic renewals.

This project starts the native replacement; it does not yet have full web feature parity. Hevy CSV import, charts/PRs, exact long-press reorder behavior, rest notifications, app icon polish, and automated sideload refresh are not implemented. Apple-platform compilation is performed by CI; device installation and behavior require an iPhone test.
