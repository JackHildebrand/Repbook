# Repbook 0.9.0 (10) — design implementation

Baseline: the supplied Complete Design Specification v1.0, with the user's final navigation override **Home → Routines → Progress → History**. Settings live behind a gear button; there is no You tab.

## Implemented in source

- Semantic light/dark surfaces, 20-point screen padding, 24-point cards, 60-point capsule primary actions, Reduce Motion support, and an opaque fallback for floating controls when Reduce Transparency is enabled. Native system tab navigation; conditional Liquid Glass for the mini-workout bar on iOS 26 with a compatible SDK.
- Home with persisted weekday assignments, selected-day routine, one-tap start/resume, weekday context actions, week navigation, actual month/volume statistics, and recent activity. Repeating assignments use routine IDs so renaming a routine does not break the app schedule.
- Persistent workout presented above the tab navigation, with a minimizable session bar on every main tab. Resume and Live Activity links focus the current set.
- Expanded current-set controls, immediate +/- changes, numeric-entry sheets, previous-session values, exercise expansion, checked completed rows, warmup styling, notes, add/remove/unlog actions, configurable increments, and volume-only PR medals/haptics.
- Captured session/set identities prevent repeated UI or Live Activity Log actions from toggling a completed set back to unfinished.
- Rest card with skip and +/-15 seconds, foreground haptic at completion, optional authorized rest notifications, exercise-specific duration defaults, and durable end timestamps.
- Completion summary with duration, sets, exercises, volume, volume PRs, editable workout note, and a full-session link.
- History month calendar/day filtering/search; session details, historical weight/rep/date/note editing, confirmed deletion, and save-as-routine. Volume medals are recalculated after historical edits/deletion.
- Searchable progress list for all recorded exercises; exercise detail with 1M/3M/6M/1Y/All, best weight/estimated 1RM/total reps/volume, chart scrubbing/selection feedback, and volume PR markers. Weekly primary-muscle set charts with comparisons and editable muscle assignments. Working sets are counted; effort is not inferred.
- Routine menus for edit/duplicate/schedule/delete; hold-name reordering with collapse/pickup/crossing feedback, expansion on release/cancellation, visible move alternatives, set reordering, target values/types, notes, rest, and 0–10 automatically generated warmups. Existing row names and exercise IDs are retained.
- Full-height exercise picker with recent exercises, muscle filter, custom exercise creation, details, and primary-muscle assignment.
- Grouped appearance, workout/set, feedback, schedule, and data preferences. Hevy CSV merge with duplicate detection, explicit units, multiline/escaped CSV support, and import confirmation. Invalid or unsupported timed/distance-only rows fail the whole import instead of silently dropping data. CSV dates use the device time zone. JSON backup/restore remains supported.
- Existing scheduled Home Screen and circular barbell Lock Screen widgets and interactive Live Activity commands retained. Dynamic Island expanded content is reduced to the exercise/set summary; compact content shows rest or elapsed time.

## Verified here

- Swift 6.0.3: 15 core tests passed, zero failures.
- Native Swift parser accepted app, shared activity, and widget sources.
- Full core type checking and package compilation passed.
- Project YAML and matching app/extension versions validated; whitespace checks passed.
- A simulator UI test is prepared for logging, tab navigation, termination/relaunch persistence, completion, and History. It uses isolated test storage and disables ActivityKit only in UI-test launches.

## Still needs completion or verification

- Xcode/iOS type checking, simulator UI test execution, visual comparison, gesture feel, VoiceOver, and large Dynamic Type verification. This workspace has no Apple SDK or iOS simulator.
- Physical iPhone tests for WidgetKit/App Intents, ActivityKit, lock/unlock/background/termination cases, and notification delivery. Feedback and update timing remain subject to iOS execution limits.
- **Unified app/widget schedule**: widget configuration still uses its existing per-widget weekday names. App Group provisioning and shared snapshots have not been added; widgets do not yet follow the in-app weekly schedule automatically. Existing free-signing setup has not been changed.
- HealthKit integration, reminder scheduling, sound options, optional accent colors, intelligent progression recommendations, exercise substitutions, and a SwiftData migration are not implemented. Durable JSON persistence is retained to avoid an unverified migration.
- Cross-presentation matched-geometry transitions are not implemented; native presentation and spring card transitions are used.

## Build handoff

The iOS workflow runs core tests, generates the Xcode project, builds the simulator app/widget, runs the new simulator workout flow test, and builds/packages the unsigned IPA. UI-test results are uploaded as `Repbook-test-results`. No remote push or successful iOS build is claimed by this local implementation.

## Screenshot reference alignment

The six supplied reference screenshots informed a further source pass: monochrome capsule actions; black/white semantic canvas; exercise/equipment subtitles; circular increment controls; separate compact/expanded rest cards; grayscale calendar indicators; compact progression stats and padded weight-axis domains; and a two-panel Live Activity with a full-width Log Set action. Screenshot dates, workout totals and chart values remain illustrative only and are never inserted as real user data. The ChatGPT navigation, input bar and screenshot overlays are excluded. Visual fidelity remains unverified until rendered on iOS.

## Semantic color pass

Primary actions and content remain monochrome. Blue identifies selected tabs, scheduled days, current-set indicators, chart lines and selections. Green identifies completed-day checks, completed sets, volume PR medals and rest completion; non-improvements remain neutral rather than being automatically labeled bad. Red is reserved for destructive native actions and invalid numeric input. Color is paired with symbols or text. This is a local source update; iOS rendering and remote build remain pending.
