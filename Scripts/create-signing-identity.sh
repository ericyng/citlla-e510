#!/bin/bash
#
# Create the local code-signing identity that Scripts/build.sh prefers.
#
# Why: an ad hoc signature pins the binary's cdhash, so every rebuild looks like
# a different app to TCC and Accessibility / Input Monitoring grants are lost.
# A real (even self-signed) certificate gives the app a designated requirement
# of the form
#
#     identifier "com.ericng.citllae510" and certificate root = H"…"
#
# which does not change when the app is rebuilt, so the grants survive. It is
# also narrower than the ad hoc identifier-only fallback: only binaries signed
# with this key match, not any bundle that happens to use the same identifier.
#
#   Scripts/create-signing-identity.sh            create it (no-op if present)
#   Scripts/create-signing-identity.sh --force    delete and recreate it
#
# Files it creates, all outside the repository:
#
#   ~/Library/Keychains/citlla-signing.keychain-db
#   ~/Library/Application Support/CitllaE510/signing/keychain-password
#   ~/Library/Application Support/CitllaE510/signing/certificate.pem
#
# The keychain password is random and stored in that support file (mode 600).
# The private key never leaves the keychain; the temporary PEM files are removed.
#
set -euo pipefail

IDENTITY_NAME="${CITLLA_IDENTITY_NAME:-Citlla E510 Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/citlla-signing.keychain-db"
SUPPORT="$HOME/Library/Application Support/CitllaE510/signing"
PASSWORD_FILE="$SUPPORT/keychain-password"
CERT_FILE="$SUPPORT/certificate.pem"
FORCE=0

usage() {
    awk 'NR > 2 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "${BASH_SOURCE[0]}"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help) usage ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    if [[ $FORCE -eq 0 ]]; then
        echo "Identity \"$IDENTITY_NAME\" already exists in $KEYCHAIN"
        echo "Use --force to replace it. Replacing it invalidates every existing TCC grant."
        exit 0
    fi
    echo "Replacing the existing identity (existing TCC grants will stop matching)"
    security delete-keychain "$KEYCHAIN" 2>/dev/null || rm -f "$KEYCHAIN"
fi

if [[ -e "$KEYCHAIN" && $FORCE -eq 0 ]]; then
    echo "$KEYCHAIN already exists but has no usable identity." >&2
    echo "Re-run with --force to recreate it." >&2
    exit 1
fi

mkdir -p "$SUPPORT"
chmod 700 "$SUPPORT"
umask 077

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSWORD="$(openssl rand -base64 24)"
printf '%s' "$PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

echo "Generating a 10-year self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY_NAME/O=Eric Ng" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# macOS's security tool still expects the older PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout pass:citlla -name "$IDENTITY_NAME" >/dev/null 2>&1

security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P citlla \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
cp "$WORK/cert.pem" "$CERT_FILE"
chmod 644 "$CERT_FILE"

FINGERPRINT="$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha1 \
    | sed 's/^.*=//; s/://g')"

echo
echo "Created \"$IDENTITY_NAME\""
echo "  keychain      $KEYCHAIN"
echo "  fingerprint   $FINGERPRINT (SHA-1)"
echo "  validity      10 years"
echo
echo "Scripts/build.sh will now sign with it automatically."
echo "The certificate is deliberately not trusted for Gatekeeper: the app is"
echo "built locally and never quarantined, so it launches fine, and TCC matches"
echo "the certificate itself rather than a trust chain."
echo
echo "One-time step: the first signed build no longer matches the old ad hoc"
echo "grant. Reset and grant Accessibility + Input Monitoring once:"
echo
echo "  tccutil reset Accessibility com.ericng.citllae510"
echo "  tccutil reset ListenEvent com.ericng.citllae510"
echo
echo "then launch the app and flip both switches in System Settings."
