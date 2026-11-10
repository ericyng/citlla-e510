#!/bin/bash
#
# The gate every track runs before it merges, and main runs after each merge.
#
#   Scripts/check.sh                 generate, test, build, snapshot everything
#   Scripts/check.sh --no-snapshots  skip the renders (faster)
#   Scripts/check.sh --docs          also copy the main-window renders into
#                                    docs/snapshots/ for the README
#
# Snapshots need no permission: they render the app's own views with
# `cacheDisplay`. The section list is checked against `MainSection.available`
# before rendering, so a section added to the code without a render here (or a
# render for a section that no longer exists) fails the gate instead of quietly
# drifting. Each render also asserts the `section=` the binary reports, because
# `Snapshot` falls back to Overview for an unknown section.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SNAPSHOTS=1
DOCS=0
for arg in "$@"; do
    case "$arg" in
        --no-snapshots) SNAPSHOTS=0 ;;
        --docs) DOCS=1 ;;
        -h|--help) awk 'NR > 2 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

[[ $DOCS -eq 1 && $SNAPSHOTS -eq 0 ]] && {
    echo "--docs copies the renders, so it cannot be combined with --no-snapshots" >&2
    exit 2
}

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

# The sections rendered below must match the sidebar. Reading the enum rather
# than trusting a comment here is what keeps the two from drifting: a new case
# in `MainSection.available` with no render fails, and so does a render for a
# section the app does not show.
SECTION_SOURCE="CitllaE510/Views/MainSection.swift"
[[ -f "$SECTION_SOURCE" ]] || fail "cannot read $SECTION_SOURCE"
AVAILABLE="$(sed -n '/static var available/,/}/p' "$SECTION_SOURCE" \
    | grep -oE '\.[a-z]+' | tr -d '.' | tr '\n' ' ' | sed 's/ *$//')"
[[ -n "$AVAILABLE" ]] || fail "could not read MainSection.available from $SECTION_SOURCE"

SECTIONS="overview buttons actions profiles scrolling advanced permissions about"
for section in $SECTIONS; do
    case " $AVAILABLE " in
        *" $section "*) ;;
        *) fail "check.sh renders '$section', but MainSection.available does not list it" ;;
    esac
done
for section in $AVAILABLE; do
    case " $SECTIONS " in
        *" $section "*) ;;
        *) fail "MainSection.available lists '$section', but check.sh does not render it" ;;
    esac
done
info "sections match MainSection.available: $AVAILABLE"

# Renders one window. Exit 3 is "no window to snapshot", which is how a window
# that a later track adds reports itself; anything else is a real failure.
snap() {
    local name="$1"; shift
    local want_section="" prev=""
    for arg in "$@"; do
        [[ "$prev" == "--section" ]] && want_section="$arg"
        prev="$arg"
    done
    if "$APP" "$@" >"$LOG" 2>&1; then
        # `Snapshot` falls back to Overview for a section that is not in
        # `MainSection.available`, so a success alone does not prove the right
        # pane was drawn. It prints the section it actually rendered.
        local rendered
        rendered="$(sed -n 's/.*section=\([a-z]*\).*/\1/p' "$LOG" | tail -1)"
        if [[ -n "$rendered" && -n "$want_section" && "$rendered" != "$want_section" ]]; then
            fail "snapshot $name rendered section=$rendered, expected $want_section"
        fi
        ok "$name${rendered:+  $DIM(section=$rendered)$RESET}"
        return
    fi
    if grep -q "no window to snapshot" "$LOG"; then
        info "skip $name (window not built yet)"
        return
    fi
    cat "$LOG"
    fail "snapshot failed: $name"
}

# The Advanced pane's Button Tester, and the legacy `--tab` mapping. These stay
# in the gate because they exercise the old entry points; only the main-window
# renders are published in the README.
snap "tester" --snapshot "$OUT/tester.png" --window tester --scale 2
for tab in mouse buttons permissions about; do
    snap "settings-$tab" --snapshot "$OUT/settings-$tab.png" --tab "$tab" --scale 2
done

# One render per sidebar section, in the order the sidebar lists them.
for section in $SECTIONS; do
    snap "main-$section" --snapshot "$OUT/main-$section.png" --window main --section "$section" --scale 2
done

if [[ $DOCS -eq 1 ]]; then
    step "Docs"
    mkdir -p docs/snapshots
    cp "$OUT"/main-*.png docs/snapshots/
    cp "$OUT"/tester.png docs/snapshots/
    ok "copied main-*.png and tester.png into docs/snapshots"
    info "settings-* are the legacy shapes and are not published"
fi

step "Done"
info "snapshots in $OUT"
info "look at them (the Read tool renders PNGs) before merging"
