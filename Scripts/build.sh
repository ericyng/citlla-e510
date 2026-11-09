#!/bin/bash
#
# Test, build, and install Citlla E510.
#
#   Scripts/build.sh                     run tests, build Release, install to /Applications
#   Scripts/build.sh --debug             build Debug instead of Release
#   Scripts/build.sh --no-tests          skip the unit tests
#   Scripts/build.sh --no-install        build and verify only
#   Scripts/build.sh --no-launch         install without launching the app
#   Scripts/build.sh --dest DIR          install somewhere other than /Applications
#   Scripts/build.sh --sign IDENTITY     sign with a keychain identity instead of ad hoc
#
# Environment:
#   SIGN_IDENTITY   same as --sign
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="CitllaE510"
DISPLAY_NAME="Citlla E510"
BUNDLE_ID="com.ericng.citllae510"
DERIVED="build/DerivedData"

CONFIG="Release"
RUN_TESTS=1
INSTALL=1
LAUNCH=1
DEST="/Applications"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

usage() {
    awk 'NR > 2 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "${BASH_SOURCE[0]}"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="Debug" ;;
        --release) CONFIG="Release" ;;
        --no-tests) RUN_TESTS=0 ;;
        --no-install) INSTALL=0 ;;
        --no-launch) LAUNCH=0 ;;
        --dest) DEST="${2:?--dest needs a directory}"; shift ;;
        --sign) SIGN_IDENTITY="${2:?--sign needs an identity}"; shift ;;
        -h|--help) usage ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

step() { echo; echo "${BOLD}▸ $*${RESET}"; }
info() { echo "  $*"; }
warn() { echo "  ${YELLOW}!${RESET} $*"; }
fail() { echo "${RED}✗ $*${RESET}" >&2; exit 1; }

SIGN_ARGS=()
if [[ -n "$SIGN_IDENTITY" ]]; then
    SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES)
fi

# ---------------------------------------------------------------------------
step "Preflight"
command -v xcodebuild >/dev/null || fail "xcodebuild not found; install Xcode."
command -v xcodegen >/dev/null || fail "xcodegen not found; run: brew install xcodegen"
info "$(xcodebuild -version | head -1)  ·  $(xcodegen --version 2>/dev/null | head -1)"
info "configuration: $CONFIG"

# ---------------------------------------------------------------------------
step "Generating project"
xcodegen generate >/dev/null
info "CitllaE510.xcodeproj up to date"

# ---------------------------------------------------------------------------
if [[ $RUN_TESTS -eq 1 ]]; then
    step "Running tests"
    TEST_LOG="$(mktemp -t citlla-test)"
    if ! xcodebuild \
        -project CitllaE510.xcodeproj \
        -scheme "$APP_NAME" \
        -configuration Debug \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        test >"$TEST_LOG" 2>&1; then
        tail -40 "$TEST_LOG"
        fail "tests failed (full log: $TEST_LOG)"
    fi
    SUMMARY="$(grep -E "^Test Suite 'All tests' (passed|failed)" "$TEST_LOG" | tail -1)"
    info "$(grep -cE "^Test Case .* passed " "$TEST_LOG") tests passed  ${DIM}($SUMMARY)${RESET}"
    rm -f "$TEST_LOG"
else
    warn "tests skipped"
fi

# ---------------------------------------------------------------------------
step "Building ($CONFIG)"
BUILD_LOG="$(mktemp -t citlla-build)"
if ! xcodebuild \
    -project CitllaE510.xcodeproj \
    -scheme "$APP_NAME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
    build >"$BUILD_LOG" 2>&1; then
    grep -E "error:" "$BUILD_LOG" | head -20 || tail -40 "$BUILD_LOG"
    fail "build failed (full log: $BUILD_LOG)"
fi
grep -E "warning: " "$BUILD_LOG" | grep -v appintentsmetadataprocessor | head -5 || true
rm -f "$BUILD_LOG"

BUILT_APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$BUILT_APP" ]] || fail "expected app not found at $BUILT_APP"
info "built $BUILT_APP"

# ---------------------------------------------------------------------------
step "Signing"
if [[ -n "$SIGN_IDENTITY" ]]; then
    info "signed with $SIGN_IDENTITY"
else
    # A plain ad hoc signature pins the exact binary, so every rebuild looks
    # like a different app to TCC and the Accessibility / Input Monitoring
    # grants are silently dropped. Re-sign with a designated requirement that
    # names the app rather than the build, so a rebuild keeps its grants.
    # A leading "=" tells codesign this is a requirement string, not a file.
    REQUIREMENT="=designated => identifier \"$BUNDLE_ID\""
    codesign --force --sign - \
        --identifier "$BUNDLE_ID" \
        --requirements "$REQUIREMENT" \
        --entitlements CitllaE510/CitllaE510.entitlements \
        "$BUILT_APP" >/dev/null 2>&1 || fail "ad hoc re-sign failed"
    info "ad hoc, stable designated requirement (grants survive rebuilds)"
fi

# ---------------------------------------------------------------------------
step "Verifying bundle"
codesign --verify --deep --strict "$BUILT_APP" 2>/dev/null || fail "code signature does not verify"

plist() { /usr/libexec/PlistBuddy -c "Print $1" "$BUILT_APP/Contents/Info.plist" 2>/dev/null || echo ""; }

[[ "$(plist CFBundleIdentifier)" == "$BUNDLE_ID" ]] || fail "unexpected bundle identifier: $(plist CFBundleIdentifier)"
[[ "$(plist LSUIElement)" == "true" ]] || fail "LSUIElement is missing; the app would show a Dock icon"
[[ -x "$BUILT_APP/Contents/MacOS/$APP_NAME" ]] || fail "executable missing from the bundle"

VERSION="$(plist CFBundleShortVersionString)"
BUILD_NUMBER="$(plist CFBundleVersion)"
SIGNATURE="$(codesign -dv "$BUILT_APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')"
[[ -n "$SIGNATURE" ]] || SIGNATURE="ad hoc"
info "bundle id   $BUNDLE_ID"
info "version     $VERSION ($BUILD_NUMBER)"
info "signature   $SIGNATURE"
info "arch        $(lipo -archs "$BUILT_APP/Contents/MacOS/$APP_NAME" 2>/dev/null || echo unknown)"

# ---------------------------------------------------------------------------
if [[ $INSTALL -eq 0 ]]; then
    step "Done"
    info "install skipped"
    exit 0
fi

step "Installing to $DEST"
if [[ ! -d "$DEST" ]]; then
    mkdir -p "$DEST" || fail "could not create $DEST"
fi
[[ -w "$DEST" ]] || fail "$DEST is not writable; re-run with sudo or pass --dest DIR"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    info "quitting the running copy"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        warn "$DISPLAY_NAME is still running (stop it in Xcode first); the old copy stays in place"
        fail "could not quit $APP_NAME"
    fi
fi

TARGET="$DEST/$APP_NAME.app"
rm -rf "$TARGET"
ditto "$BUILT_APP" "$TARGET" || fail "copy to $TARGET failed"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$TARGET/Contents/Info.plist" >/dev/null \
    || fail "installed bundle looks incomplete"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$TARGET" >/dev/null 2>&1 || true
info "installed $TARGET"

# The ad hoc signature uses an identifier-based designated requirement, so a
# grant from an earlier build still matches. Only builds made before that
# change (or with a different identity) need the list entry refreshed.
if ! codesign -dv "$TARGET" 2>&1 | grep -q "^Authority="; then
    info "ad hoc signature keeps existing TCC grants across rebuilds"
    info "if remapping stops working anyway: tccutil reset Accessibility $BUNDLE_ID"
fi

# ---------------------------------------------------------------------------
if [[ $LAUNCH -eq 1 ]]; then
    step "Launching"
    open "$TARGET"
    info "look for the mouse icon in the menu bar; Settings opens on first run"
else
    step "Done"
    info "installed without launching"
fi
