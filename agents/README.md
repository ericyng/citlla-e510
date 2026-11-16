# Agents — Citlla E510

`mouse` is the durable agent for this repo. It answers questions about the event
tap, profiles, chords, permissions and the snapshot gate from dated, sourced
knowledge in `mouse/knowledge/`, and it can run the check gate read-only.
Everything else it proposes. It never launches the app: that would grab the real
event tap and remap Eric's mouse.

- Contract, tiers, report format, journal and inbox rules: `PROTOCOL.md`
- The agent itself: `mouse/charter.md` (scope, boot order, T0/T1, prohibitions)
- Shared canonical copies: `~/OpenCode/agentkit/` (`sync.sh deploy citlla-e510`, `sync.sh check`)

## Dispatch

Both harnesses read the same charter. `agentkit/sync.sh deploy citlla-e510`
promotes it to `.claude/agents/mouse.md` (a byte-for-byte copy) and
`.opencode/agents/mouse.md` (same body, read-only frontmatter), so a session
started in this repo resolves `mouse` with no prompt pasting.

**Interactive, either harness** — full tiers, the agent may do its T2 writes:

```bash
claude --agent mouse "…"          # Claude Code, from this directory
opencode run --agent mouse "…"    # OpenCode
```

**Delegated from a parent session** — the same `root:`/`mode:`/`today:`/
`caller:`/`task:` preamble works with `subagent_type: general`
("general-purpose" in Claude Code), or with the `subagent` tool naming `mouse`.

**Scheduled** — `agentkit/sweep.sh` (LaunchAgent `com.ericng.agent-sweep`,
weekdays 07:30) runs `opencode run --agent mouse` read-only and writes the digest
into today's daily note. In that pass the OpenCode copy's frontmatter denies
every edit and every shell command except read-only git (`git status`, `log`,
`diff`, `show`, `rev-parse`, `rev-list`, `describe`, `ls-files`,
`branch --show-current`, `remote -v`, and their `-C <path>` / `--no-pager`
forms), so the scheduled pass cannot write even if it is asked to. It still
never launches the app.

Ends its turn with six sections: `Answer`, `Did`/`Would do`, `Proposes`,
`Knowledge changes`, `Open questions`, `Sources`.

## Check it

```bash
node agents/lint.mjs          # shape of charter, journal, inbox
bash ~/OpenCode/agentkit/sync.sh check citlla-e510   # promoted copies match the charter
```

After a charter edit, redeploy and then restart the OpenCode service — it caches
agent definitions by name, so a changed file is otherwise ignored:

```bash
bash ~/OpenCode/agentkit/sync.sh deploy citlla-e510 && opencode service restart
```

T2 is in effect: journal, knowledge, `PROGRESS.md`, `README.md`, `docs/` and
`docs/snapshots` commit straight to `main` and push to `origin main`. Code is
T3: a branch in a worktree, the gate, then a proposal.
