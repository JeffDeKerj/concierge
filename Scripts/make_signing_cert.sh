#!/usr/bin/env bash
# One-time: create + trust a stable self-signed code-signing identity.
#
# Why: the WhatsApp database the briefing reads sits behind Full Disk Access,
# and macOS grants that by the app's *code identity*. Ad-hoc signing (`codesign
# --sign -`) makes every code-bearing rebuild a NEW identity, so the grant
# would be lost on each make_app.sh. Signing every build with ONE stable
# identity keeps the grant. The identity is shared with the sibling apps on
# this Mac (copied from finance-advisor), hence its name.
#
# This needs a paid Apple account for a *real* Developer ID — out of scope here — so
# we use a self-signed cert trusted locally for code signing. It is NOT notarized;
# it only stabilises the local code identity. The passphrase remains the root of trust.
#
# Idempotent. The trust step prompts ONCE for your macOS account password.
set -euo pipefail

IDENTITY="${CODESIGN_IDENTITY:-Finance Advisor Dev}"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
[ -f "$LOGIN_KC" ] || LOGIN_KC="$HOME/Library/Keychains/login.keychain"

# A valid identity is one find-identity lists WITHOUT a parenthetical error
# (e.g. "(Invalid Key Usage for policy)" / "(CSSMERR_TP_NOT_TRUSTED)").
if security find-identity -p codesigning -v 2>/dev/null | grep "$IDENTITY" | grep -vq '('; then
    echo "Signing identity '$IDENTITY' already present and valid — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Remove any pre-existing (possibly malformed) cert/identity with this name so a
# re-run repairs it cleanly, then recreate.
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "Removing stale/invalid '$IDENTITY' certificate to recreate it…"
    security delete-identity -c "$IDENTITY" >/dev/null 2>&1 \
        || security delete-certificate -c "$IDENTITY" >/dev/null 2>&1 || true
fi

echo "Generating self-signed code-signing certificate '$IDENTITY'…"
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cert.cnf" -extensions v3 >/dev/null 2>&1
# -legacy: PKCS#12 MAC/cipher that macOS `security import` can read (OpenSSL 3's default cannot).
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -out "$TMP/id.p12" -passout pass:fadev >/dev/null 2>&1
# -T /usr/bin/codesign pre-authorises codesign to use the private key. On its own that's
# not enough on modern macOS — the key's ACL "partition list" still gates access and pops
# a "codesign wants to access key" prompt on every build. set-key-partition-list grants the
# Apple code-signing tools up front so builds never prompt. It needs the login-keychain
# password; KEYCHAIN_PASSWORD env avoids the GUI prompt, otherwise -k "" tries an empty one
# and (failing that) macOS asks once. If you skip it, just click "Always Allow" on the first
# build's prompt — same effect.
security import "$TMP/id.p12" -k "$LOGIN_KC" -P fadev -T /usr/bin/codesign >/dev/null
echo "Imported into the login keychain."

echo "Granting the Apple code-signing tools access to the key (so builds don't prompt)…"
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "${KEYCHAIN_PASSWORD:-}" "$LOGIN_KC" >/dev/null 2>&1 \
    || echo "  (couldn't set partition list non-interactively — click \"Always Allow\" on the first build prompt instead.)"

echo "Trusting '$IDENTITY' for code signing — approve the prompt with your macOS account password…"
security find-certificate -c "$IDENTITY" -p "$LOGIN_KC" > "$TMP/leaf.pem"
security add-trusted-cert -r trustRoot -p codeSign "$TMP/leaf.pem"

if security find-identity -p codesigning -v 2>/dev/null | grep "$IDENTITY" | grep -vq '('; then
    echo "Done — '$IDENTITY' is now a valid code-signing identity. Rebuild with Scripts/make_app.sh."
else
    echo "WARNING: '$IDENTITY' still isn't listed as valid for codesigning. Full Disk Access will" >&2
    echo "         not persist across rebuilds until this is resolved (make_app.sh stays ad-hoc)." >&2
    exit 1
fi
