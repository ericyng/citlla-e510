# Gate and docs

`Scripts/check.sh` is the gate. `Scripts/build.sh` is what it calls. They have
different defaults and only one of them is safe to run unattended.

## `check.sh` — the merge gate

```
Scripts/check.sh                 generate, test, build, snapshot everything
Scripts/check.sh --no-snapshots  skip the renders (faster)
Scripts/check.sh --docs          also copy the main-window renders into docs/snapshots/
```

— `Scripts/check.sh:5-8`.

What it does, in order:

1. Requires `xcodegen`, then `xcodegen generate` — `check.sh:45-46`. **This
   rewrites the committed `CitllaE510.xcodeproj/project.pbxproj`.**
2. Calls `Scripts/build.sh --no-install --no-launch` — `check.sh:50`. So the gate
   itself never installs or launches; the dangerous defaults are overridden here.
3. If `--no-snapshots`, exits 0 after the build — `check.sh:53-57`.
4. Otherwise renders 13 PNGs at 2× into `build/snapshots` — `check.sh:60-133`:
   `tester`, four legacy `settings-*` shapes (`mouse`, `buttons`, `permissions`,
   `about`), and eight `main-*` sections in sidebar order.
5. With `--docs`, copies `main-*.png` + `tester.png` into `docs/snapshots/` —
   `check.sh:135-142`.

`--docs` cannot be combined with `--no-snapshots`; it exits 2 —
`check.sh:33-36`.

## The section assertion

This is the part with real value, and it must not be weakened:

- `check.sh` reads `MainSection.available` out of
  `CitllaE510/Views/MainSection.swift` by `sed`/`grep` — `check.sh:72-76`.
- It fails if a section it renders is not in `available`, **and** if `available`
  lists a section it does not render — `check.sh:78-90`.
- Each render must also report the `section=` it actually drew, because
  `Snapshot` silently falls back to Overview for an unknown section —
  `check.sh:104-110`.
- Section list today: overview, buttons, actions, profiles, scrolling, advanced,
  permissions, about — `MainSection.swift:49-51`.
- The "no window to snapshot" skip is **latent-broken**: `check.sh:114` greps for
  `no window to snapshot`, while `Snapshot.swift:75` prints
  `no window content to snapshot`, so the skip can never fire and the case would
  be reported as a failure (`check.sh:118-119`). It is near-unreachable — exit 3
  only happens when `window.contentView` is nil (`Snapshot.swift:74-77`) — but do
  not describe the skip as working. A fix is proposed in `inbox.md`.

Weakening this assertion to make a run pass is a T4-class act: it removes the only
check that the sidebar and the snapshot set agree.

## `build.sh` — defaults that are wrong for an agent

| default | where | flag |
| --- | --- | --- |
| `CONFIG=Release` | `build.sh:26` | `--debug` |
| `RUN_TESTS=1` | `build.sh:27` | `--no-tests` (`:42`) |
| `INSTALL=1` | `build.sh:28` | `--no-install` (`:43`) |
| `LAUNCH=1` | `build.sh:29` | `--no-launch` (`:44`) |
| `DEST="/Applications"` | `build.sh:30` | `--dest DIR` (`:45`) |
| no explicit identity | `build.sh:31` | `--sign ID` (`:46`) |

With no flags it tests, builds Release, verifies, installs to `/Applications` and
**launches** (`build.sh:5`, `README.md:260-261,273-274`). The install step also
quits a running copy first (`build.sh:196-209`), which is exactly what an agent
must not do to Eric's session.

Use `--no-install --no-launch`; `--no-install` exits before both
(`build.sh:186-189`).

`--no-tests` exists but a run without tests is not a green gate.

## What green proves — and what it does not

The gate can run at all because the app detects the XCTest host and stands down:
`AppDelegate.applicationDidFinishLaunching` returns immediately when
`XCTestConfigurationFilePath` is set — `CitllaE510/AppDelegate.swift:9-12`. No
event tap, no HID tagger, no menu bar plumbing, no window prompt. Tests are
hosted (`TEST_HOST` is `CitllaE510.app/Contents/MacOS/CitllaE510`,
`project.yml:54-55`), so without that guard every gate run would install a real
session tap.

`ConfigStore` has the matching guard for settings: `isEphemeralLaunch` is true
under XCTest and for `--snapshot`/`--status`/`--perform`/`--post-shortcut`/
`--coredock`, and such a launch writes to a throwaway directory rather than the
live `config.json` — `ConfigStore.swift:25-45`. Without it every test run would
rewrite Eric's real bindings.

**Both guards are load-bearing.** If someone removes either, the gate edits real
settings and installs a real tap. Treat them as hardware, not tidy-up.

### The full gate's renders are not purely passive

Each render launches the built binary with `--snapshot`; `Snapshot.runIfRequested()`
returns before the tap (`AppDelegate.swift:13`), and the snapshot honours
`isEphemeralLaunch`. But the `tester` render and the `main-advanced` render mount
the tester pane (`Snapshot.swift:44-50`, default pane `.tester` at
`WindowManager.swift:46`), whose `.onAppear` calls `tester.start()`
(`MainWindowView.swift:167-170`). If the built copy is Accessibility-trusted that
starts the HID tagger and creates a **listen-only** tap, and requests Input
Monitoring when it is missing (`ButtonTester.swift:109-122`).

A listen-only tap cannot suppress input and the process exits, so nothing is
remapped. But it is a live tap, and it can raise a permission prompt — which is
why an agent uses `check.sh --no-snapshots` and never clicks through a prompt.
`check.sh:10`'s "snapshots need no permission" is true of the drawing, not of the
tester pane's appear hook.

Proves: compiles, the test suite passes, the Release bundle has the right id and a
verifying signature, and (unless `--no-snapshots`) 13 renders are produced with
the section list in agreement.

Does not prove:

- The tilt axis sign, or that 250 ms of quiet matches one physical flick.
- `NSOpenPanel` add-app behaviour or the real app icons it resolves.
- Profile switching in a live app (Chrome's override applying and the global map
  returning when it quits).
- The Dock icon or ⌘-Tab entry: snapshots render the sidebar offscreen and this
  machine grants no screen recording.

— `PROGRESS.md:112-122`.

Warnings never fail the build; they are printed and skipped (`build.sh:123`).

## Recorded gate result

2026-11-12, T2 acceptance run: `Scripts/check.sh --no-snapshots` exited 0 —
**137 tests passed**, Release build, `signed with "Citlla E510 Local Signing"`,
bundle verified (`com.ericng.citllae510`, 0.1.0, x86_64 arm64), snapshots
skipped, and `xcodegen` reported `CitllaE510.xcodeproj up to date` so the tree
stayed clean.

2026-11-09, T6 QA + docs: **137 tests, 13 snapshots**, Release build,
certificate signing, bundle checks. `--docs` exited 0 and refreshed
`docs/snapshots/`. `build.sh --no-install --no-launch` green —
`PROGRESS.md:99-102,358-359`.

Test count is `grep -c 'func test' CitllaE510Tests/CitllaE510Tests.swift` → 137
(2026-11-11), which matches.

## Docs pipeline

- `docs/snapshots/` holds `main-*.png` (8) and `tester.png` (9 files, listed by
  `ls docs/snapshots/`). `tester.png` is byte-identical to `main-advanced.png`
  (`md5` → `83d822fe3b453c5c761e36b9450f91cc`): `--window tester` is the
  Advanced section with the Button Tester pane, which is the pane Advanced shows
  by default. The README cites both.
- Those nine files were last written at `44177d6` (2026-11-09) and predate
  `8e15ba1` (sidebar layout) and `821e0df` (Actions **New Chord** / **New
  Sequence**), so they are stale — see `known-issues.md`; refreshing them is
  proposed in `inbox.md` and is Eric's call, not an agent run.
- The README Screenshots section shows the real main window with captions checked
  against OCR of the renders — `PROGRESS.md:90-93`.
- The old `docs/screenshots/` directory was deleted; nothing references it —
  `PROGRESS.md:93`.
- Regenerate with `Scripts/check.sh --docs`; the renders land in
  `build/snapshots`, then get copied — `check.sh:62,135-142`.

## Seeing the renders

`screencapture` is not available, but the PNGs are ordinary files: read them
directly. Composite onto white first — panes without an opaque list background
come out transparent (`PROGRESS.md:292-294`).
