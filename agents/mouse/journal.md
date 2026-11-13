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
