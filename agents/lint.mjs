#!/usr/bin/env node
//
// Shape check for project agents. No dependencies, no network.
//
//   node agentkit/lint.mjs [--root DIR]      lint one checkout (default: cwd)
//
// Validates, for every <root>/agents/<name>/ that has a charter.md:
//   - charter frontmatter has name (matching the directory) and description,
//     and the body has the five required headings
//   - journal.md headings are all `## YYYY-MM-DD live|dry-run`
//   - inbox.md has `## open questions` and `## proposals`, with at most 6
//     proposals still waiting
//   - knowledge/ exists, and agents/PROTOCOL.md is present
// Exits 1 on any problem, printing one line per problem.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, basename } from "node:path";

const args = process.argv.slice(2);
let root = process.cwd();
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--root") root = args[++i];
  else if (args[i] === "-h" || args[i] === "--help") {
    console.log("usage: lint.mjs [--root DIR]");
    process.exit(0);
  } else {
    console.error(`lint: unknown argument ${args[i]}`);
    process.exit(2);
  }
}

const problems = [];
const note = (msg) => problems.push(msg);

const agentsDir = join(root, "agents");
if (!existsSync(agentsDir) || !statSync(agentsDir).isDirectory()) {
  console.error(`lint: no agents/ directory in ${root}`);
  process.exit(1);
}
if (!existsSync(join(agentsDir, "PROTOCOL.md"))) {
  note(`${root}: agents/PROTOCOL.md missing (run agentkit/sync.sh deploy ${basename(root)})`);
}

const REQUIRED_HEADINGS = ["## Scope", "## Boot", "## Tiers", "## Prohibited", "## Report"];
const JOURNAL_HEADING = /^## \d{4}-\d{2}-\d{2} (live|dry-run)$/;
const PROPOSAL_HEADING = /^### \S/;

function lines(path) {
  return readFileSync(path, "utf8").split("\n");
}

function checkFrontmatter(name, text) {
  const parts = text.split(/^---$/m);
  if (parts.length < 3) {
    note(`${name}: charter.md has no frontmatter`);
    return;
  }
  const fm = parts[1];
  const got = {};
  for (const line of fm.split("\n")) {
    const m = /^([a-zA-Z_]+):\s*(.*)$/.exec(line.trim());
    if (m) got[m[1]] = m[2].trim();
  }
  if (!got.name) note(`${name}: charter frontmatter has no name`);
  else if (got.name !== name) note(`${name}: charter name is "${got.name}", expected "${name}"`);
  if (!got.description) note(`${name}: charter frontmatter has no description`);
}

function checkJournal(name, path) {
  if (!existsSync(path)) {
    note(`${name}: journal.md missing`);
    return;
  }
  for (const line of lines(path)) {
    if (line.startsWith("## ") && !JOURNAL_HEADING.test(line)) {
      note(`${name}: journal heading "${line}" is not "## YYYY-MM-DD live|dry-run"`);
    }
  }
}

function checkInbox(name, path) {
  if (!existsSync(path)) {
    note(`${name}: inbox.md missing`);
    return;
  }
  const body = lines(path);
  if (!body.includes("## open questions")) note(`${name}: inbox.md has no "## open questions"`);
  if (!body.includes("## proposals")) note(`${name}: inbox.md has no "## proposals"`);

  let inProposals = false;
  let waiting = 0;
  let under = null;
  for (const line of body) {
    if (line === "## proposals") { inProposals = true; continue; }
    if (line.startsWith("## ") && line !== "## proposals") { inProposals = false; continue; }
    if (!inProposals) continue;
    if (PROPOSAL_HEADING.test(line)) { under = line; continue; }
    if (under && /^- Status:\s*waiting\s*$/.test(line)) waiting++;
  }
  if (waiting > 6) note(`${name}: ${waiting} proposals waiting, the cap is 6`);
}

for (const entry of readdirSync(agentsDir)) {
  const dir = join(agentsDir, entry);
  if (!statSync(dir).isDirectory()) continue;
  const charter = join(dir, "charter.md");
  if (!existsSync(charter)) continue;            // not an agent directory

  const text = readFileSync(charter, "utf8");
  checkFrontmatter(entry, text);
  for (const heading of REQUIRED_HEADINGS) {
    if (!text.split("\n").includes(heading)) {
      note(`${entry}: charter.md has no "${heading}"`);
    }
  }
  if (!existsSync(join(dir, "knowledge"))) note(`${entry}: knowledge/ missing`);
  checkJournal(entry, join(dir, "journal.md"));
  checkInbox(entry, join(dir, "inbox.md"));
}

if (problems.length === 0) {
  console.log(`lint: clean (${root})`);
  process.exit(0);
}
for (const p of problems) console.error(`lint: ${p}`);
console.error(`lint: ${problems.length} problem(s) in ${root}`);
process.exit(1);
