# Plan: full Citlla E510 app + action sequences

Status: proposal · 2026-11-09

This is the delivery plan for turning the menu bar remapper into a Logi Options+
style app, and for adding chained actions (chords and multi-step sequences).
It is written to be handed to worktree subagents track by track.

---

## 1. Target experience

The app keeps working exactly as it does now in the background, and grows a real
window for configuration.

| State | Activation policy | What the user sees |
| --- | --- | --- |
| Background (default) | `.accessory` (`LSUIElement` stays YES) | Menu bar icon only. Remapping runs. No Dock icon, no ⌘-Tab entry. |
| Full view | `.regular` | Dock icon, app menu, ⌘-Tab entry, one main window with a sidebar. |
| Last window closed | `.accessory` again | Back to menu bar only; remapping never stops. |
| "Keep in Dock" preference on | `.regular` always | Logi Options+ behaviour; the Dock icon launches the main window. |

`LSUIElement` stays `YES` in `Info.plist` so the app starts in the background;
the Dock icon is produced at runtime with
`NSApp.setActivationPolicy(.regular)`. The app already ships a full
`AppIcon.appiconset`, so no artwork work is needed.

Menu bar gets **Open Citlla E510…** (replacing *Settings…*) and the usual
**Test Buttons…**, **Diagnostics…**, **Launch at Login**, **Quit**.

## 2. Suite layout

One main window, `NavigationSplitView`, sidebar in this order:

| Section | Contents | New work |
| --- | --- | --- |
| **Overview** | Device card (receiver, VID/PID, HID interface state), remapping toggle, permission health, active profile, "3 of 9 controls bound" summary | New |
| **Buttons** | Existing Mouse map + Buttons tab, unchanged visually | Move into section |
| **Actions** | Named macros, the step editor, built-in system actions, presets | New |
| **Profiles** | Default profile + per-app overrides, add-app rule | New |
| **Scrolling** | Invert direction, tilt left/right actions, link to system pointer speed | New |
| **Advanced** | Button Tester, Diagnostics, raw HID, config path, reset | Move into section |
| **Permissions** | Existing | Move into section |
| **About** | Existing | Move into section |

Tester and Diagnostics become panes of the main window instead of separate
windows. That removes three window controllers, makes snapshots simpler, and
matches the Logi Options+ shape.

### What this mouse can and cannot do

Be honest in the UI; do not ship dead controls.

- **Can:** button and keystroke remapping, chained actions, per-app profiles,
  scroll direction, tilt remapping (`AC Pan` arrives as horizontal scroll),
  login item, launch app/URL/shell.
- **Cannot (without private APIs):** DPI and polling rate (firmware), gestures
  (no touch surface), battery percentage (receiver does not report it in any
  interface seen so far).
- **Unknown, needs a spike:** pointer speed / acceleration. No public API; the
  honest fallback is a deep link to System Settings → Mouse. Do not promise it.
- **Research spike (optional, 0.5 day):** dump every HID element from the
  receiver and check for battery / DPI usage pages before ruling them out.

## 3. Action engine

Two additions, both behind the existing flat `MouseAction` model so old configs
keep loading.

### 3.1 Chords (small)

Add `clickModifiers: UInt` to `MouseAction`. `postClick` presses the modifiers
for real (same helper as `postKey`), sets them on the click event's `flags`,
then releases them. Editor gets a modifier row under the Click picker.

Unlocks ⌘-click (new tab), ⌥-click (download), ⇧-click (extend selection),
⌃-click, and any modifier+click combination.

### 3.2 Sequences

New `ActionKind.sequence` plus an ordered step list:

```swift
struct ActionStep: Codable, Equatable, Sendable {
    var kind: ActionKind          // .sequence is rejected/flattened on load
    var system: SystemAction
    var keyCode: UInt16
    var modifiers: UInt
    var hasShortcut: Bool
    var click: MouseClickKind
    var clickModifiers: UInt
    var text: String
    var delayMilliseconds: Int    // wait *before* this step, clamped 0…500
}

struct MouseAction {
    // …existing fields…
    var steps: [ActionStep] = []  // used when kind == .sequence
}
```

Limits: **8 steps**, **500 ms** per delay, **3000 ms** total. Nested sequences
are flattened on load with a log line. Invalid steps are dropped, not fatal.

Execution:

- `MacroRunner` (new, `@MainActor`) owns one `Task` per binding owner. A new
  press cancels the in-flight run and starts fresh.
- Steps never sleep on the tap thread. The tap callback only enqueues; a
  blocked tap gets disabled by the system after ~0.5 s.
- Each step is atomic: modifiers down → key/click → modifiers up, with the
  release in a `defer` so a cancel mid-step cannot leave modifiers stuck.
- Posted events keep `EventMarker`, so the app's own tap ignores them.
- `ActionExecutor.perform` is split into `performStep` (sync) and
  `performSequence` (async), with a small `EventSink` protocol so tests can
  assert order and timing without posting events.
- Tester shows "ran N steps" and highlights the current step; the Mouse legend
  and Buttons rows show `Copy → 100 ms → Paste`.

Presets to ship: Copy/Paste, Screenshot area to Clipboard (⌃⇧⌘4), Open app →
⌘N, Safari new tab, Finder new folder, ⌘+click.

### 3.3 Profiles

```swift
struct AppProfile: Codable, Identifiable, Equatable, Sendable {
    var id: String                 // bundle identifier
    var name: String
    var enabled: Bool
    var buttonActions: [Int: MouseAction]
    var shortcutActions: [String: MouseAction]
}
```

- Stored in `AppConfig`; default profile is the existing global mapping.
- `ActiveAppMonitor` watches `NSWorkspace.didActivateApplicationNotification`
  and caches the frontmost bundle id. The tap does a dictionary lookup, no XPC.
- Resolution order: enabled profile for the frontmost app → global binding.
- The app's own bundle is ignored, so opening Settings cannot change behaviour.
- Profiles reuse `ActionEditorSheet`, so macros work per app for free.

## 4. Delivery strategy

Three ways to run this. Recommendation is **Option B**.

| | Option A — lean | **Option B — suite (recommended)** | Option C — staged |
| --- | --- | --- | --- |
| Worktrees | 3 | 5 | 1–2 at a time, short-lived |
| Scope | chords + sequences + shell + scrolling | everything above incl. profiles | same as B, one track after another |
| Wall clock | ~3 days | ~4–5 days | ~6–7 days |
| Merge risk | low | medium, needs the contract commit | low |
| Best when | you want the macro feature soon | you want the Logi Options+ shape | you want minimal ceremony |

### Option B waves

```
Wave 0 (serial, main):        T0 contract
Wave 1 (parallel):            T1 core-actions   T2 app-shell   T5 scrolling
Wave 2 (parallel):            T3 macro-ui       T4 profiles
Wave 3:                       T6 qa-docs + live hardware pass
```

`T3` starts when `T1` merges. `T4` starts when `T1` and `T2` merge. Scrolling is
independent and can merge any time after the contract.

### Effort per track

| Track | Worktree / branch | Effort | Depends on |
| --- | --- | --- | --- |
| T0 Contract | main, direct | 0.5 day | — |
| T1 Core actions | `core-actions` | 1.5–2 days | T0 |
| T2 App shell | `app-shell` | 1–1.5 days | T0 |
| T3 Macro UI | `macro-ui` | 1–1.5 days | T1 |
| T4 Profiles | `profiles` | 1.5–2 days | T1, T2 |
| T5 Scrolling | `scrolling` | 1 day | T0 |
| T6 QA + docs | `qa-docs` | 0.5–1 day | all merged |

## 5. Track specs

Every track ends with: tests pass, `--no-install` build passes, a 2× snapshot of
its new UI, and a short note in the worktree commit message. No track installs
to `/Applications` or touches TCC (see §6).

### T0 — Contract (main session, no worktree)

Files: `Models/MouseAction.swift`, `Models/MacroOwner.swift`,
`Models/AppProfile.swift` (types only), `Views/MainSection.swift` (sidebar enum),
`Services/MacroRunner.swift` (API signature + TODO bodies), `Services/ActionExecutor.swift`
(`perform(_:owner:)` plus the `.sequence` hand-off), `Services/EventTapService.swift`
(passes the owner), tests compiled against the frozen shapes.

Shipped early because it was small and self-contained: **chords**. `clickModifiers`
is stored, `MouseAction.describe(click:modifiers:)` gives "⌘ Left Click", and
`ActionExecutor` presses the modifiers for real around the click (`withModifiers`,
shared with `postKey`) and stamps them on the click events. Until the editor
row lands there is no UI for it, but the model and executor are done.

Also required for compatibility: `MouseAction` has a hand-written `init(from:)`
using `decodeIfPresent`. The synthesized decoder would have rejected every
config saved before `clickModifiers`/`steps` existed, and `ConfigStore` swallows
that error by falling back to defaults — a silent reset of all bindings.

Acceptance: project builds, all tests pass, no behaviour change beyond chords.
This commit is the base for every worktree so parallel tracks cannot drift on
types.

### T1 — Core actions (`core-actions`)

Files owned: `Models/MouseAction.swift`, `Services/ActionExecutor.swift`,
`Services/MacroRunner.swift`, `Utilities/KeyCodeMap.swift` (if needed),
`CitllaE510Tests/`.

- Sequence: flatten on load, clamp to `SequenceLimits`, execute with delays.
- Cancellation per `MacroOwner`; modifier release guaranteed on cancel.
- `EventSink` seam and tests: order, delay, cancel, modifier release.
- Keep `perform` working for every existing action, including chords.

Acceptance: ~15 new tests; a 3-step sequence runs in the tester.

### T2 — App shell (`app-shell`)

Files owned: `AppDelegate.swift`, `CitllaE510App.swift`,
`Services/WindowManager.swift` → `Services/AppWindows.swift`,
`Views/MainWindowView.swift`, `Views/MainSidebar.swift`,
`Views/MenuBarContent.swift`, `Utilities/Snapshot.swift`.

- `AppPresence`: activation policy switching, "Keep in Dock" preference,
  reopen handling, hide Dock icon when the last window closes.
- Main window with sidebar and the section enum; move existing views into it
  without restyling them.
- SwiftUI scenes: keep `MenuBarExtra`, add the window and `.commands`
  (About, Settings ⌘,, Hide, Quit) so a real app menu exists in full view.
- Snapshot: `--window main --section <id>`.

First task is a 2-hour spike proving: Dock icon appears, ⌘-Tab works, app menu
is correct, closing hides the icon, remapping keeps running, `.accessory`
restores cleanly. Stop and re-plan if the SwiftUI scene fights the policy switch.

Acceptance: all eight sections open; snapshots for each; menu bar unchanged
except the new Open item; live remap test still passes after the policy switch.

### T3 — Macro UI (`macro-ui`)

Files owned: `Views/ActionEditorSheet.swift`,
`Views/MacroEditorView.swift`, `Views/TesterView.swift`,
`Views/MouseMapView.swift` (legend), `Models/ActionPreset.swift`,
`Services/ButtonTester.swift` (step reporting).

- Extract the per-kind fields from `ActionEditorSheet` into a reusable
  `ActionFieldsView`, so a step row and the top-level editor share one control.
- Step list: add, duplicate, delete, reorder (drag), per-step delay stepper.
- Presets menu; summary strings; tester step counter.
- Rejects `.sequence` inside a step in the UI.

Acceptance: build a 3-step macro entirely with the mouse; snapshot of the
editor; tester reports each step.

### T4 — Profiles (`profiles`)

Files owned: `Models/AppProfile.swift`, `Models/AppConfig.swift`,
`Services/ActiveAppMonitor.swift`, `Services/EventTapService.swift`
(resolution only), `Views/ProfilesView.swift`, plus a small hook in the
sidebar.

- Model + config round-trip, add/remove app rules via `NSOpenPanel`.
- Per-profile overrides using the shared action editor.
- Resolution in the tap for buttons and mouse keystrokes.
- Tests for precedence, disabled profiles, own-bundle exclusion, unknown app.

Acceptance: a profile for Chrome overrides one button; quitting Chrome returns
to the global binding; tests cover the fallback order.

### T5 — Scrolling (`scrolling`)

Files owned: `Services/EventTapService.swift` (scroll case),
`Services/ScrollController.swift` (new), `Views/ScrollingView.swift`,
`Models/AppConfig.swift` (scroll settings), tests.

- Add `.scrollWheel` to the tap mask. Invert vertical/horizontal by rewriting
  the event in place and returning it (no re-post loop).
- Tilt → action on the horizontal axis, one trigger per gesture with a cooldown
  (~250 ms), configurable through the same action editor.
- Pointer speed: link to System Settings only; note it in the UI.

Acceptance: inversion is smooth (no stutter), tilt triggers once per flick, and
disabling the section restores stock behaviour exactly.

### T6 — QA + docs (`qa-docs`)

- Extend snapshots to every section, 2×, into `Docs/snapshots/`.
- README: new window, Dock behaviour, sequences, profiles, scrolling limits.
- PROGRESS: state, open threads, verification notes.
- `Scripts/check.sh`: xcodegen, tests, build, all snapshots, exit non-zero on
  failure. This is the gate every merge runs.

## 6. Worktree + subagent operating rules

### Creating the worktrees

Use the harness worktree tool (or plain git, same result):

```
tools.opencode.worktree_create({ name: "core-actions" })
# → ../citlla-e510-worktrees/core-actions
```

Branches: `track/core-actions`, `track/app-shell`, `track/macro-ui`,
`track/profiles`, `track/scrolling`, `track/qa-docs`. All cut from the T0
contract commit on `main`. Directories are siblings, never inside the repo.

### The TCC rule (this is the important one)

The app is now signed by a local certificate, so its designated requirement is
`identifier … and certificate root = H"…"` — path-independent. TCC grants
therefore survive rebuilds, reinstalls and a change of directory.

LaunchServices is still per path, though: `open`ing a worktree build registers a
second copy of `com.ericng.citllae510`, which can hijack `open -a` for the real
app. And a second running copy would install a second event tap, double-posting
every remapped event.

Therefore:

- Subagents run **only** `Scripts/build.sh --no-install --no-launch` and the
  built binary's `--snapshot` (which needs no permission). Unit tests and
  snapshots are the whole verification surface in a worktree.
- Nobody runs `open` on a worktree build. The certificate means a worktree build
  would *share* the installed app's TCC identity, so this is a correctness rule,
  not just a permissions rule.
- Live hardware testing happens **only** on the integration build installed to
  `/Applications` from `main`, one copy at a time. `Scripts/build.sh` already
  quits the running copy before installing.
- The certificate requirement keeps the existing grants across rebuilds, so
  integrating does not cost a re-grant.

### Subagent brief template

Each dispatch gets exactly this, with the track section pasted in:

```
Repo: /Users/ericng/OpenCode/citlla-e510-worktrees/<track>  (branch track/<track>)
Base: commit <T0 hash>
Goal: <track summary>
Own these files: <list>
Read but do not edit: <list>
Contract (do not change): <types from T0>
Acceptance: xcodegen generate && Scripts/build.sh --no-install --no-launch
            plus: <tests / snapshot command>
Hard rules: do not install to /Applications, do not run `open`, do not touch TCC,
            do not edit project.pbxproj by hand, do not edit README/PROGRESS.
Return: commit hash, test count, snapshot path, anything you had to leave out.
```

Use `general` for the implementation tracks and `explore` for the activation
policy spike and the HID battery/DPI research spike. Run at most three build
tracks at once; Xcode builds are the bottleneck.

### Merge order and gates

1. T1 core-actions → main
2. T2 app-shell → main
3. T3 macro-ui
4. T5 scrolling
5. T4 profiles (touches the tap after T1/T5; last)
6. T6 qa-docs

After every merge: `xcodegen generate`, then `Scripts/check.sh`, then one live
smoke test (middle click, thumb buttons, one macro). Resolve conflicts in
source only; regenerate `project.pbxproj` instead of merging it. README and
PROGRESS have a single owner (T6).

## 7. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Activation policy switch fights SwiftUI `MenuBarExtra` | Dock icon or app menu wrong, or remapping stops | T2 spike first; fall back to a manual `NSWindow` + `NSMenu` if the scene misbehaves |
| Tap disabled by timeout during a long sequence | Buttons stop working until re-enabled | Never sleep on the tap; async runner; 3 s cap; re-enable on `.tapDisabledByTimeout` already exists |
| Modifiers stuck after cancel/quit | App or system feels shifted | tracked modifiers + `defer` release; test cancellation explicitly |
| Sequence clicks merge into double-clicks | Wrong selection behaviour | `clickState = 1` per step; dedicated Double Click step later |
| Drag-reorder in SwiftUI Form is finicky | Editor feels broken | spike the list inside the sheet; fall back to up/down buttons if needed |
| Profile lookup on every event is slow | Latency in clicks | cached frontmost bundle id, dictionary lookup, no XPC |
| Scroll inversion causes stutter or feedback | Bad scroll feel | rewrite in place, return same event, marker check; cooldown for tilt |
| Worktree builds hijack LaunchServices | `open -a` launches the wrong copy | no `open` in worktrees; `lsregister -f` the installed app after each install |
| Per-app profiles surprise the user | Button does something unexpected | show the active profile in the menu bar tooltip and Overview; "Default" is always visible |

## 8. Open decisions

1. **Profiles in v1?** Recommended yes — it is the main thing that makes the app
   feel like Logi Options+.
2. **Macro library vs inline steps?** Recommended inline for v1 (one sequence
   per binding), library in a later release. A library needs stable macro ids
   and a binding reference; it is easy to add once sequences exist.
3. **Dock icon default?** Recommended "only while a window is open", with a
   *Keep in Dock* switch in Overview.
4. **Scrolling scope?** Recommended invert + tilt now; pointer speed as a link.
5. **Typed-text steps?** Recommended defer to Plan C unless a preset needs it.

## 9. Acceptance for the whole suite

- Existing 48 tests plus ~40 new ones pass; `Scripts/check.sh` green.
- Non-installed build in every worktree builds and snapshots.
- Live, on the `/Applications` build: middle click → Mission Control, thumb
  Back/Forward, a 3-step macro, a Chrome-only profile that reverts on quit,
  Dock icon lifecycle, and remapping still running after closing the window.
- README, PROGRESS and `Docs/snapshots/` reflect the shipped app.
