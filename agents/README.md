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

```
subagent_type: general          # "general-purpose" in Claude Code
prompt: <body of agents/mouse/charter.md, everything after the closing --->
        + "" +
        root: /Users/ericng/OpenCode/citlla-e510
        mode: live            (or dry-run)
        today: <YYYY-MM-DD>
        caller: <who is asking>
        task: <the question or job>
```

Ends its turn with six sections: `Answer`, `Did`/`Would do`, `Proposes`,
`Knowledge changes`, `Open questions`, `Sources`.

## Check it

```bash
node agents/lint.mjs          # shape of charter, journal, inbox
```

T2 is in effect: journal, knowledge, `PROGRESS.md`, `README.md`, `docs/` and
`docs/snapshots` commit straight to `main` and push to `origin main`. Code is
T3: a branch in a worktree, the gate, then a proposal.
