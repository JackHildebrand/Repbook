# Repbook for iPhone

SwiftUI app targeting iOS 17+, with ActivityKit Lock Screen/Dynamic Island controls and a WidgetKit Home Screen launcher. No server, subscription, push notifications, or Apple login is used by the app.

## Implemented

- Upper/Lower routines, exercise search/custom exercises, editable working sets, 0–2 warmup sets (default 2).
- Reorder mode collapses exercises to names and uses native list drag handles; ordinary scrolling does not initiate a reorder. This first version uses an explicit Reorder button rather than the web app's long-press gesture.
- Active workout, previous working weight/reps, log/unlog, add/delete sets, add exercises, automatic rest countdown, finish/discard, local history.
- Atomic on-device JSON persistence, native backup export/import, and migration from the latest web app JSON export including active workouts, exercise IDs, and PR medals. Retain the original export as a backup.
- Local Live Activities with current exercise/set, weight/reps adjustment buttons and log button. Requests identify both session and set so repeated/stale Log taps cannot log the following set. LiveActivityIntent executes in the host app; no shared App Group container is required for these controls.
- Configurable scheduled-routine widgets for the Home Screen and circular Lock Screen slot. Tapping their control starts today's routine and Live Activity without opening the app.
- Unit changes convert all saved weights rather than relabeling them.
- Version 0.3 uses the blue theme, shows current-set progress in Live Activities, restores PR medals, moves Settings into the Workout toolbar, and improves numeric editing and keyboard dismissal.
- Updates keep the same `com.jackhildebrand.repbook` bundle identifier and Application Support data file. Running a new build over the installed app preserves data; deleting the app removes local data, so export a backup before deletion.

## Build on a Mac

### Scheduled workout widgets (0.7)

Add **Scheduled workout** from the Repbook widget gallery. Hold the widget and select **Edit Widget**. Enter the exact saved routine name for each weekday; leave a field empty for a rest day. The schedule is stored in the widget configuration, so each widget can have its own week without App Group entitlements. Routine renames require updating the corresponding widget fields.

For the Lock Screen, customize the Lock Screen, tap the widget area, and add **Scheduled workout — Lock Screen**. It uses the same weekday configuration and displays only a barbell; tapping the barbell runs the same start action as the Home Screen widget.

The blue arrow uses a `LiveActivityIntent` with `openAppWhenRun = false`. It starts and saves the scheduled routine in the app process in the background, then awaits the Live Activity request. Existing active workouts are resumed rather than overwritten. The action resolves today's weekday at tap time, and the widget supplies midnight entries for the coming week. Live Activities must be enabled; unsupported or failed requests return an error instead of claiming success. Background launch and Lock Screen behavior must still be tested on a physical iPhone.

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
- Add both scheduled workout widgets; configure the same week and verify their controls start the expected routine. Test large text and VoiceOver.
- Verify installer refresh retains data and includes the extension before relying on automatic renewals.

This project starts the native replacement; it does not yet have full web feature parity. Hevy CSV import, exact long-press reorder behavior, rest notifications, app icon polish, and automated sideload refresh are not implemented. Apple-platform compilation is performed by CI; device installation and behavior require an iPhone test.

### Rest completion notifications

Rest completion now uses a silent local notification scheduled at the stored rest deadline, independent of the app's background execution. Allow notifications when starting a workout in the app. The notification opens the matching active workout; it never starts an old session. Logging another set, changing/skipping rest, finishing/discarding, or disabling the setting clears/replaces the alert. Live Activity sound alerts are disabled to avoid duplicates.

For an unlocked-phone banner only, configure Settings → Notifications → Repbook: Banners on, Lock Screen and Notification Center off, Temporary banner style. These destinations and haptics are controlled by iOS, not the app. Silent notifications do not guarantee vibration. The existing automatic Dynamic Island checkmark limitation remains; notifications do not execute app code at delivery.

Device checks: schedule rest and switch apps; verify silent delivery at the deadline; tap to open the current set; adjust, skip, disable, finish, and discard before expiry and verify no stale alert; deny permission and confirm logging still works. Test Lock Screen/Notification Center destinations using the iPhone settings above.

### Widget launch recovery

Widget starts first resolve today's in-app weekday assignment by routine ID (so routine renames are safe), then fall back to the widget's configured routine name. Existing sessions are resumed. Blank widget days without an app assignment do not choose an arbitrary workout. If starting the workout or its Live Activity fails, the app intent offers foreground continuation to show the error and resume any session already saved. Live Activities being disabled does not prevent the workout from being saved or resumed in the app.

Physical-device checks: tap the circular Lock Screen widget on an assigned Saturday with a blank widget schedule, with a legacy widget name, after renaming a routine, with no assignment, and with Live Activities disabled. Verify the foreground recovery action and that repeated taps never replace the active session. When sideloading, retain the RepbookWidgets extension.
