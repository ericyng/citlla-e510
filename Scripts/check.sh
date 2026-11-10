#!/bin/bash
#
# The gate every track runs before it merges, and main runs after each merge.
#
#   Scripts/check.sh                 generate, test, build, snapshot everything
#   Scripts/check.sh --no-snapshots  skip the renders (faster)
#
# Snapshots need no permission: they render the app's own views with
# `cacheDisplay`. A section that does not exist yet is skipped rather than
# failed, so the same gate works before and after the shell track lands.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SNAPSHOTS=1
for arg in "$@"; do
    case "$arg" in
        --no-snapshots) SNAPSHOTS=0 ;;
        -h|--help) awk 'NR > 2 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
step() { echo; echo "${DIM}▸ $*${RESET}"; }
info() { echo "  $*"; }
ok() { echo "  ${GREEN}✓${RESET} $*"; }
fail() { echo "${RED}✗ $*${RESET}" >&2; exit 1; }

step "Generate"
command -v xcodegen >/dev/null || fail "xcodegen not found; run: brew install xcodegen"
xcodegen generate >/dev/null
ok "project generated"

step "Tests and build"
Scripts/build.sh --no-install --no-launch
ok "tests and build green"

if [[ $SNAPSHOTS -eq 0 ]]; then
    step "Done"
    info "snapshots skipped"
    exit 0
fi

step "Snapshots"
APP="build/DerivedData/Build/Products/Release/CitllaE510.app/Contents/MacOS/CitllaE510"
[[ -x "$APP" ]] || fail "built binary missing at $APP"
OUT="build/snapshots"
rm -rf "$OUT"
mkdir -p "$OUT"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# Renders one window. Exit 3 is "no window to snapshot", which is how a window
# that a later track adds reports itself; anything else is a real failure.
snap() {
    local name="$1"; shift
    if "$APP" "$@" >"$LOG" 2>&1; then
        ok "$name"
        return
    fi
    if grep -q "no window to snapshot" "$LOG"; then
        info "skip $name (window not built yet)"
        return
    fi
    cat "$LOG"
    fail "snapshot failed: $name"
}

snap "tester" --snapshot "$OUT/tester.png" --window tester --scale 2
for tab in mouse buttons permissions about; do
    snap "settings-$tab" --snapshot "$OUT/settings-$tab.png" --tab "$tab" --scale 2
done

# The main window arrives with the app-shell track. Until `Snapshot` knows
# `--window main`, it falls back to rendering Settings for any unknown name, so
# rendering these now would be a false green. Enable this loop in the merge
# commit that lands the shell:
#
# for section in overview buttons actions profiles scrolling advanced permissions about; do
#     snap "main-$section" --snapshot "$OUT/main-$section.png" --window main --section "$section" --scale 2
# done

step "Done"
info "snapshots in $OUT"
info "look at them (the Read tool renders PNGs) before merging"
