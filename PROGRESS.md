# Progress

Last updated: 2026-11-07 (late)

Where the Citlla E510 app stands, what was learned about the mouse, and what is
next. `README.md` is the user-facing documentation; this file is the working
log.

## State

- Release build installed at `/Applications/CitllaE510.app`, universal
  (`x86_64 arm64`), ad hoc signed. `Scripts/build.sh` runs tests, builds,
  verifies the bundle, installs and launches.
- 26 unit tests pass (config round-trip, action model, button naming, key codes,
  and the diagram's nine callouts).
- Menu bar app (`LSUIElement`): menu bar icon, Settings (Mouse / Buttons /
  Permissions / About), Diagnostics, Button Tester.
- Current bindings in `~/Library/Application Support/CitllaE510/config.json`:
  buttons 1–3 pass through, 4 → Show Desktop, 5 → Forward, 6–8 unbound.

**One manual step is outstanding:** the last reinstall invalidated the ad hoc
code signature, so Accessibility has to be re-granted once
(System Settings → Privacy & Security → Accessibility → Citlla E510). Until then
the menu shows *Accessibility permission is required* and both the remapper and
the tester are inert.

## What the app does now

| Area | Notes |
| --- | --- |
| Remapping | `CGEventTap` at the session level, head insert, suppresses the original button pair and runs the chosen action. Events it posts itself are stamped so they are not remapped twice. |
| Actions | macOS actions (Mission Control, Show Desktop, Launchpad, screenshot…), any keyboard shortcut, mouse clicks, open app / URL / shell command. |
| Settings → Mouse | The two renders cut from the manufacturer's diagram, next to the nine numbered callouts with the diagram's own wording. Clicking a row opens the action editor for the button behind it. Fixed 860×720 window. |
| Test Buttons… | Listen-only tap at head insert: highlights and counts each diagram control as it is pressed, shows a raw log of mouse / scroll / keyboard / system-defined events, and *Copy Report* for pasting into a bug report. Controls the firmware sends that are not on the diagram are called out separately. |
| Diagnostics | Raw HID reports from the receiver (needs Input Monitoring). |
| `--status` | Prints accessibility / input monitoring / tap state and exits. |
| `--snapshot` | Renders one of the app's own windows to PNG — the only way to check layout on this machine, which does not grant screen recording. |

## What the diagram says about the mouse

The diagram is `Design/citlla-diagram.png` (1500×1500). Its blue badges
(`#0075F9`) were located by exact-colour connected components and the numerals
were read by template matching against the badge 1–9 glyphs:

| # | Control | Diagram text | Reality on the Mac |
| --- | --- | --- | --- |
| 1 | Left Button | primary click | button 1 |
| 2 | Right Button | secondary click | button 2 |
| 3 | Smart Flying Scroll Wheel | scroll + middle click | scroll, button 3 |
| 4 | DPI Button | DPI presets | firmware only, sends nothing |
| 5 | Side Wheel | horizontal scroll | arrives as a wheel tilt, not a button |
| 6 | Devices Switch Button | switch paired device | factory profile sends `⌘Tab` |
| 7 | Devices Indicators | 2.4G / BT1 / BT2 / DPI / low power | LEDs, not a button |
| 8 | Forward / Back Buttons | the two thumb buttons | buttons 4 and 5 |
| 9 | Return to Desktop / Full Screen | bottom-right thumb button | factory profile sends `⌃⌘F` |

Rows 6 and 9 are keyboard shortcuts, not mouse buttons, so the remapper cannot
touch them yet (they also cannot be told apart from a real keyboard `⌘Tab`).
Tilt is not handled at all.

The renders in `Assets.xcassets/Mouse/` are produced by
`Scripts/extract-assets.swift`; it keys out the studio background, erodes away
the callout leader lines and the floor strip, keeps the largest blob, dilates
back and writes 1x + 2x images. Re-run it if the diagram changes.

## Open threads

1. **Learn what each physical control sends.** Open *Test Buttons…*, press every
   control once, then *Copy Report*. Expected surprises: the side wheel may send
   `NSEvent` tilt via `scrollWheel` (`deltaAxis2`) rather than a button, and the
   bottom-right button may send a keyboard shortcut instead of button 6.
2. **Extend `EventTapService` for whatever the report shows** — at minimum
   horizontal scroll/tilt, so the side wheel can be bound.
3. **Handle shortcut-sending buttons.** Either swallow the synthetic shortcut
   when it is recognisably from the mouse (needs a way to tell the source
   apart), or document that those two buttons must be remapped to "no function"
   in the mouse's own software first.
4. **Diagram hotspots.** The renders are currently artwork only; the numbered
   legend is the interactive surface. Overlaying hit targets on the renders
   would need the badge positions mapped to the render crops (coordinates are
   recorded in the git history of this session), and it was skipped because a
   wrong hotspot is worse than none.
5. **Signing.** No codesigning identity is present on this machine, so every
   rebuild requires `tccutil reset Accessibility com.ericng.citllae510` and a
   fresh grant. Creating a self-signed certificate in the login keychain and
   using `Scripts/build.sh --sign` would end that cycle.

## Verification notes

- The app's windows cannot be inspected through AX: for a `MenuBarExtra` app,
  `AXWindows` returns proxy elements that resolve back to the application
  element. `--snapshot` plus OCR (`Vision`) and pixel analysis of the PNG works
  instead, and was used to confirm both windows fit their content.
- The tester tap is at head insert so it still sees buttons the remapper
  swallows a moment later. It is listen-only, so it cannot suppress anything.
- `AXIsProcessTrusted()` reports the truth for the `open`-launched app; running
  the binary from a terminal borrows the terminal's TCC identity, so `--status`
  from a shell can say *trusted* while the app itself is not.

## Session log

- `0377507` `--status` probe and stale-grant documentation
- `b65ede4` real Settings window, AppKit-managed windows, first-run prompt
- `9e327f3` unit tests and `Scripts/build.sh`
- `95fbbce` diagram-based mouse map, button tester, asset extraction, snapshots
- `0161699` tap recovery when Accessibility is granted after launch
- `307e340` tester tap at head insert
