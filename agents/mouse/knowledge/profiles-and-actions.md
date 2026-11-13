# Profiles and actions

Binding resolution, the action kinds, and the caps on chained actions.

## Resolution order

1. The **enabled profile** for the frontmost app's bundle id.
2. The **global map**.
3. If neither binds the control, the event passes through untouched.

Sources: `AppConfig.swift:141-150` (`action(for:frontmostBundleID:)`),
`EventTapService.swift:179-180` (the call site).

Details that are easy to get wrong:

- A profile whose `enabled` is `false` is skipped, not merely deprioritised —
  `AppConfig.swift:119-122`.
- **The app's own bundle is excluded**: `bundleID != Self.ownBundleIdentifier`
  at `AppConfig.swift:111,120`. Opening Citlla's own window must not change how
  the mouse behaves inside it.
- An unbound override **falls back to the global map**, it does not unbind —
  `AppConfig.swift:146-149`.
- `frontmostBundleID` defaults to `nil` so every older caller keeps the plain
  global lookup — `AppConfig.swift:143-145`.
- Profiles survive *Reset to defaults* (`PROGRESS.md:52`).

## Action kinds

macOS actions (Mission Control, Show Desktop, Launchpad, screenshot…), any
keyboard shortcut, mouse clicks, open app / URL / shell command —
`PROGRESS.md:166`. Mission Control, App Exposé, Show Desktop and Launchpad go
through `DockControl`; everything else is posted as events — same line, and
`architecture.md` for why.

- `EventSink` is the seam: the real sink posts marked events
  (`ActionExecutor.swift:144`), the tester's silent sink counts steps without
  posting — `PROGRESS.md:169`.
- Consumer-key bindings exist (`ShortcutBinding.source == .consumer`) but nothing
  in the UI creates one yet — `PROGRESS.md:268-271`.

## Which buttons actually exist

The hardware reports buttons 1–3 only. Buttons 4–8 are trimmed from older configs
on load (`ButtonBinding.retiredButtons`, `PROGRESS.md:337-338`). The thumb buttons
are **not** buttons 4/5 — they are mouse-sent `⌃←` / `⌃→` keystrokes
(`PROGRESS.md:35-38`), and callout 9 is `⌃⌘F` (`PROGRESS.md:228,234-237`).

## Chords

A click with `⌃⌥⇧⌘` held **for real** around it, through the shared
`withModifiers` helper, so the app receives a genuine chord rather than a
simulated modifier state — `PROGRESS.md:167`.

## Sequences (caps)

| limit | value | source |
| --- | --- | --- |
| max steps | 8 | `MouseAction.swift:59` |
| max wait per step | 500 ms | `MouseAction.swift:60` |
| max total | 3000 ms | `MouseAction.swift:61` |

- Steps are normalised on load; nested sequences and empty steps are dropped —
  `MacroRunner.swift:61-72,138-144`.
- When the total cap would be exceeded, the run stops early and logs how many of
  how many steps ran — `MacroRunner.swift:69-72`.
- One run per owner, with cancel-and-restart; a `defer` releases modifiers —
  `PROGRESS.md:168`.
- Switching remapping off cancels in-flight runs — `EventTapService.swift:141-151`.

## Presets

`ActionPreset.all` fills the editor: Copy → Paste, Screenshot Area to Clipboard,
Safari: New Tab, Finder: New Folder, Open App → New Window, ⌘-Click —
`PROGRESS.md:169`.

## Tester

A listen-only tap at head insert, highlighting and counting diagram controls,
with a raw log and *Copy Report*. Mouse-sent keystrokes are labelled **Mouse key**
and marked bindable; keyboard events are labelled separately — `PROGRESS.md:174`.
It uses `peekKeyPress()` so it cannot suppress anything or steal an attribution
sample from the remapper (`PROGRESS.md:295-297`).

## Tilt actions

Left/right tilt actions fire once per flick behind a 250 ms quiet window —
`ScrollController.swift:28`. A bound tilt swallows the gesture, so the side wheel
stops scrolling sideways (`EventTapService.swift:208-211`).

The **axis sign is unverified on hardware**: a positive horizontal delta maps to
"right" as a convention taken from the tester's labelling, and swapping it is a
one-line change in `TiltDirection.direction(forHorizontalDelta:)` —
`PROGRESS.md:262-267`.
