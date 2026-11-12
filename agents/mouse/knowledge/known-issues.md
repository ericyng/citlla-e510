# Known issues

Live problems, stale claims, and things that cannot be verified here.

## Stale documentation — `PROGRESS.md` is behind the repo

`PROGRESS.md:3` says `Last updated: 2026-11-09`, and its last session-log line is
the T6 merge. Since then `821e0df` (New Chord/Sequence creation flow) and
`8e15ba1` (main window sidebar vanishing on tall sections) landed.

Specific stale claims — do **not** quote these as current:

| line | claim | reality |
| --- | --- | --- |
| `PROGRESS.md:114-115` | "Push state: nothing is pushed. `track/qa-docs` and the feature branches are local" | `origin` → `github.com/ericyng/citlla-e510`; `main` is pushed through `c631ee4` |
| `PROGRESS.md:174-179` | screenshot service note about system actions | still true, but see `architecture.md` for the current `DockControl` routes |

Anything about binding state in `PROGRESS.md:22-27` describes
`~/Library/Application Support/CitllaE510/config.json` at the time of writing —
it is machine state, not code. Do not treat it as a repository fact.

## Cannot be verified without hardware

These are real and open; a green gate says nothing about them
(`PROGRESS.md:103-113`):

- The tilt **axis sign** (positive horizontal delta mapped to "right") and whether
  250 ms of quiet matches one physical flick — `PROGRESS.md:253-258`,
  `ScrollController.swift:28`.
- `NSOpenPanel` add-app interaction and the real app icons it resolves.
- Profile switching in a live app: Chrome's override applying while frontmost and
  the global map returning when it quits.
- The Dock icon and ⌘-Tab entry — snapshots render the sidebar offscreen and this
  machine grants no screen recording.

An agent cannot close any of these, because closing them requires launching the
app. Report them as open.

## Open product threads

- **Spotlight (⌘Space) and Lock Screen (⌃⌘Q)** are symbolic hotkeys with no
  working Dock or private-notification route found — `PROGRESS.md:199-201,245-252`.
- **Unidentified consumer key**: the receiver sends `NX_KEYTYPE_SOUND_UP` from a
  control not matched to a diagram number. Consumer bindings exist in the model
  (`ShortcutBinding.source == .consumer`) but nothing in the UI creates one —
  `PROGRESS.md:221-229,259-262`.
- **Diagram hotspots**: badges sit on the renders at the manufacturer's callout
  points (`MouseControl.badgePoint`) but the renders are not clickable yet; the
  legend remains the interactive surface — `PROGRESS.md:263-266`.
- **Row 6 (`⌘Tab`) has no binding row yet.** Tilt is handled; row 6 is not —
  `PROGRESS.md:229`.

## Environment traps that look like bugs

- `--status` from a shell borrows the terminal's TCC identity and can report
  trusted when the app is not — `PROGRESS.md:294-296`.
- The app's windows cannot be inspected through AX: for a `MenuBarExtra` app,
  `AXWindows` returns proxies that resolve back to the application element.
  `--snapshot` + OCR is the working method — `PROGRESS.md:281-285`.
- The HID listener must be on a **background** run loop, or reports arrive after
  the main-thread tap callback for the matching key — `PROGRESS.md:289-291`.
- `CGEventSourceStateID`: private `-1`, combined session `0`, HID system `1`. Real
  HID events are state `1`; older tester labels were inverted —
  `PROGRESS.md:292-293`.
- Dock expose modes close if another app activates. A probe without `open -g`
  closes what it just opened, which reads as "the notification does not work" —
  `PROGRESS.md:297-300`.

## Known-good baseline

Do not report these as regressions:

- Gate on 2026-11-09: 137 tests, 13 snapshots — `PROGRESS.md:73-75`.
- Test count today: 137 (`grep -c 'func test' CitllaE510Tests/CitllaE510Tests.swift`).
- The `settings-*` renders are the legacy tab shapes and are intentionally not
  published in the README — `check.sh:122-128,141`.
