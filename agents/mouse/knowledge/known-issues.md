# Known issues

Live problems, stale claims, and things that cannot be verified here.

## Stale documentation — `docs/snapshots/` predates the current window

`PROGRESS.md` was brought up to date on 2026-11-12 and no longer claims nothing
is pushed (`git rev-list --left-right --count origin/main...main` → `0 0`).

The published renders are stale instead: `docs/snapshots/*.png` was last
written at `44177d6` (2026-11-09, `git log -1 -- docs/snapshots`), and since
then `8e15ba1` (2026-11-10) replaced the `NavigationSplitView` sidebar with a
fixed 210 pt `HStack` (`MainWindowView.swift:12-23`) and `821e0df` (2026-11-11)
added the **New Chord** / **New Sequence** buttons to Actions
(`ActionsSectionView.swift:90-110`). All nine files show the older window.

`tester.png` and `main-advanced.png` are byte-identical
(`md5` → `83d822fe3b453c5c761e36b9450f91cc`), which is expected: `--window
tester` is the Advanced section with the Button Tester pane selected, and that
is the pane the Advanced section defaults to. The README cites both files.

Regeneration is proposed in `inbox.md`; an agent must not run
`check.sh --docs` (it renders, and the tester pane's `.onAppear` may start a
listen-only tap — `gate-and-docs.md`).

Anything about binding state in `PROGRESS.md:25-30` describes
`~/Library/Application Support/CitllaE510/config.json` at the time of writing —
it is machine state, not code. Do not treat it as a repository fact.

## Cannot be verified without hardware

These are real and open; a green gate says nothing about them
(`PROGRESS.md:112-122`):

- The tilt **axis sign** (positive horizontal delta mapped to "right") and whether
  250 ms of quiet matches one physical flick — `PROGRESS.md:262-267`,
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
  working Dock or private-notification route found — `PROGRESS.md:208-210,254-261`.
- **Unidentified consumer key**: the receiver sends `NX_KEYTYPE_SOUND_UP` from a
  control not matched to a diagram number. Consumer bindings exist in the model
  (`ShortcutBinding.source == .consumer`) but nothing in the UI creates one —
  `PROGRESS.md:230-238,268-271`.
- **Diagram hotspots**: badges sit on the renders at the manufacturer's callout
  points (`MouseControl.badgePoint`) but the renders are not clickable yet; the
  legend remains the interactive surface — `PROGRESS.md:272-275`.
- **Row 6 (`⌘Tab`) has no binding row yet.** Tilt is handled; row 6 is not —
  `PROGRESS.md:238`.

## Environment traps that look like bugs

- `--status` from a shell borrows the terminal's TCC identity and can report
  trusted when the app is not — `PROGRESS.md:303-305`.
- The app's windows cannot be inspected through AX: for a `MenuBarExtra` app,
  `AXWindows` returns proxies that resolve back to the application element.
  `--snapshot` + OCR is the working method — `PROGRESS.md:290-294`.
- The HID listener must be on a **background** run loop, or reports arrive after
  the main-thread tap callback for the matching key — `PROGRESS.md:298-300`.
- `CGEventSourceStateID`: private `-1`, combined session `0`, HID system `1`. Real
  HID events are state `1`; older tester labels were inverted —
  `PROGRESS.md:301-302`.
- Dock expose modes close if another app activates. A probe without `open -g`
  closes what it just opened, which reads as "the notification does not work" —
  `PROGRESS.md:306-309`.

## Known-good baseline

Do not report these as regressions:

- Gate on 2026-11-09: 137 tests, 13 snapshots — `PROGRESS.md:82-84`. Gate on
  2026-11-12 (`--no-snapshots`): 137 tests, renders skipped — `gate-and-docs.md`.
- Test count today: 137 (`grep -c 'func test' CitllaE510Tests/CitllaE510Tests.swift`).
- The `settings-*` renders are the legacy tab shapes and are intentionally not
  published in the README — `check.sh:122-128,141`.
