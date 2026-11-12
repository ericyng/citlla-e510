# Decisions

Append-only. Date, decision, why, and what it rules out. Never edit an older
entry.

## 2026-11-11 — `mouse` never launches the built app

Why: launching installs a session-level `CGEventTap` at head insert
(`EventTapService.swift:47-56,71-72`) which suppresses and rewrites real mouse
clicks, scrolls and keys. It would remap Eric's physical mouse mid-session, and
there is no way to bound it to a scratch context.

Rules out: `open build/…/CitllaE510.app`, `Scripts/build.sh` without
`--no-install`/`--no-launch`, running the binary directly, and `--snapshot` runs
that start the app's tap (the gate renders offscreen in its own process; an
agent does not add ad-hoc launches).

## 2026-11-11 — the agent's gate is `check.sh --no-snapshots`

Why: `check.sh` already calls `build.sh --no-install --no-launch`
(`Scripts/check.sh:50`), so it is the safe entry point, and it still enforces the
`MainSection.available` section assertion and the per-render `section=` check.
Skipping snapshots keeps a read-only verification run to generate + test + build.

Rules out: calling `build.sh` directly for a verification run, and `--no-tests`
as a way to make a run green.

## 2026-11-11 — never weaken the section assertion

Why: `check.sh:78-90` is the only mechanism that keeps the sidebar
(`MainSection.available`, `MainSection.swift:49-51`) and the rendered set in
agreement. It is friction by design, and the reason a new section cannot ship
without its snapshot.

Rules out: editing `SECTIONS` in `check.sh`, trimming `available`, or relaxing the
`rendered != want_section` failure (`check.sh:108-110`) to make a run pass.

## 2026-11-11 — the gate may sign, but nothing may create an identity

Why: `check.sh` calls `build.sh --no-install --no-launch`, and that still runs the
signing step (`Scripts/check.sh:50`, `build.sh:132-157`). Signing with the existing
local certificate creates nothing, replaces nothing and changes no TCC state, so it
is allowed. Creating or replacing the identity, `--sign`, and manual `security`
calls are not.

Rules out: `--sign`, `SIGN_IDENTITY=`, `create-signing-identity.sh`,
`security unlock-keychain` typed by hand, `tccutil reset`.

## 2026-11-11 — the XCTest-host process is not an app launch

Why: tests are hosted, so the gate starts `CitllaE510.app/Contents/MacOS/CitllaE510`
(`project.yml:62-63`). `AppDelegate.swift:9-12` returns before the tap, the tagger
or any window is touched when `XCTestConfigurationFilePath` is set. Reading "never
launch the app" strictly would forbid the gate entirely — and that guard is the
only reason the gate is safe.

Rules out: deleting or reordering that guard, and any "helpful" refactor that moves
`AppDelegate` work above it.

## 2026-11-11 — never touch signing or TCC

Why: the certificate is what keeps Accessibility and Input Monitoring across
rebuilds, and its requirement is scoped to a key
(`README.md:286-293`). Creating or replacing it, or resetting TCC, changes this
machine's trust state and requires a human re-grant
(`README.md:304-310`).

Rules out: `--sign`, `SIGN_IDENTITY=`, `create-signing-identity.sh`,
`security unlock-keychain`, `tccutil reset`.

## 2026-11-11 — docs commits may push to `origin main`; code may not

Why: Eric approved T2 pushes. The repo has a remote
(`origin → github.com/ericyng/citlla-e510`). A docs push is reversible by another
commit; a code push bypasses the gate.

Rules out: pushing anything outside `agents/`, `PROGRESS.md`, `README.md`,
`docs/`, and pushing from a code branch.
