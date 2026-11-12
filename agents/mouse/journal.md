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
