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
  `check.sh` run would install a real session tap. Also: `check.sh` overrides
  `build.sh`'s dangerous defaults itself (`check.sh:50`), so the gate is safe
  where a bare `build.sh` is not; signing still runs and there is no `--no-sign`
  flag; and `PROGRESS.md:114-115` still claims nothing is pushed, which is false.
- wrote: `knowledge/{architecture,profiles-and-actions,permissions,gate-and-docs,build-and-sign,decisions,known-issues}.md`,
  `knowledge/README.md`, charter T1 + prohibitions.
