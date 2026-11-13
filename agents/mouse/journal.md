# mouse journal

Append-only. One entry per run, format in `../PROTOCOL.md` §4. Heading is
`## YYYY-MM-DD live` or `## YYYY-MM-DD dry-run` — the linter rejects anything
else.

Scaffolded 2026-11-11 (phase 0). No runs yet.

## 2026-11-11 live
- did: seeded `knowledge/` from `README.md`, `PROGRESS.md`, `git log`, `Scripts/`
  and the sources; every claim carries a `path:line`, a SHA or a command.
- found: the one fact that makes the gate runnable by an agent is
  `CitllaE510/AppDelegate.swift:9-12` — the app returns before the event tap when
  `XCTestConfigurationFilePath` is set, and the tests are hosted. Without it every
  `check.sh` run would install a real session tap. The companion guard is
  `ConfigStore.isEphemeralLaunch` (`ConfigStore.swift:25-45`), which keeps test and
  `--snapshot` runs off the live `config.json`. The full gate is *not* purely
  passive, though: the `tester` and `main-advanced` renders mount the tester pane
  and can start a listen-only tap, so agent runs use `--no-snapshots`. Also:
  hardened runtime is **off** (`project.yml:37`), not applied at signing as this
  file first claimed; and `check.sh:114`'s skip string does not match
  `Snapshot.swift:75`.
- wrote: `knowledge/{architecture,profiles-and-actions,permissions,gate-and-docs,build-and-sign,decisions,known-issues}.md`,
  `knowledge/README.md`, charter T1 + prohibitions, `inbox.md` (one proposal, two
  open questions).

## 2026-11-12 live
- did: T2 acceptance run. Compared the README Screenshots section
  (`README.md:16-50`) with `docs/snapshots/`: eight `main-*.png` were cited,
  the ninth file (`tester.png`) was not — and it is byte-identical to
  `main-advanced.png` (`md5` `83d822fe3b453c5c761e36b9450f91cc`), so the README
  now accounts for all nine. Brought `PROGRESS.md` up to date: 2026-11-12 date,
  push state (`main` == `origin/main`, `0 0`, `track/*` local only), `8e15ba1`
  and `821e0df` in State and the session log, and the `NavigationSplitView`
  wording replaced with the fixed 210 pt sidebar. Ran
  `Scripts/check.sh --no-snapshots` once: exit 0, 137 tests, Release build,
  `Citlla E510 Local Signing`, bundle verified, snapshots skipped; `xcodegen`
  reported the project up to date, so the tree stayed clean. Commits
  `7d444a4`, `d85b040`, `76c7931` pushed to `origin/main`.
- found: every published render predates the current window — `docs/snapshots/`
  was last written at `44177d6` (2026-11-09), before `8e15ba1` changed the
  sidebar layout and `821e0df` added **New Chord** / **New Sequence** — so the
  fix is a `check.sh --docs` refresh, proposed in `inbox.md`, not a regenerate
  by an agent. Also: this model cannot read images, so the render prose was
  checked against the view sources (`MainWindowView.swift:188-347`,
  `ActionsSectionView.swift:22-24`, `ScrollingView.swift:18-71`) instead of OCR.
- wrote: corrected `knowledge/architecture.md` (window layout, `8e15ba1`),
  `knowledge/known-issues.md` (stale renders replace the now-fixed stale
  PROGRESS section; baseline gate), `knowledge/gate-and-docs.md` (docs pipeline,
  `tester.png` duplicate, 2026-11-12 gate); remapped every `PROGRESS.md:line`
  citation in `knowledge/` after PROGRESS grew by nine lines; added one proposal
  and one open question to `inbox.md`.

## 2026-11-12 live
- did: T3 fix for the dead exit-3 skip, on branch `agents/mouse-2026-11-12`
  (worktree `~/OpenCode/.agents/mouse-2026-11-12`, commit `4a792e6`) — not
  merged, not pushed. Changed the producer, not the consumer: `Snapshot.swift`
  now prints `no window to snapshot`, the exact string `check.sh:114` greps and
  `check.sh:93` already documents, so comment, grep and print agree with one
  file changed. Gate in the worktree: `Scripts/check.sh --no-snapshots` exit 0,
  **137 tests passed**, Release build, `Citlla E510 Local Signing`, bundle
  verified, snapshots skipped; `xcodegen` said `CitllaE510.xcodeproj up to
  date`, so only `Snapshot.swift` was modified. Read-only proof:
  `grep -rn "no window" Scripts/check.sh CitllaE510/Services/Snapshot.swift`
  shows `check.sh:93`, `check.sh:114` and `Snapshot.swift:76` all say
  `no window to snapshot`. The nil-`contentView` path itself was not exercised:
  that needs a render, which an agent does not run.
- found: the two files are coupled by a log string, not by the exit code —
  `snap()` captures the output and greps it, so any future rewording in
  `Snapshot.swift` silently kills the skip again. The one-line comment at the
  print is now the only warning at the edit site; `check.sh:93-94` is the one at
  the consumer.
- wrote: `knowledge/gate-and-docs.md` (branch status and 2026-11-12 T3 gate
  record), `inbox.md` (proposal to `awaiting Eric` with the branch, and the
  2026-11-11 question resolved). No `PROGRESS.md`, `README.md` or `docs/`
  change: the code is unmerged, so nothing on `main` describes it yet.
