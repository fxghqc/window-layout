#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_NAME="${WINDOW_LAYOUT_IDENTITY_NAME:-Window Layout Local Code Signing}"
LOGIN_KEYCHAIN="${WINDOW_LAYOUT_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

has_identity() {
  security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null |
    grep -Fq "\"$IDENTITY_NAME\""
}

work_dir="$(mktemp -d)"
certificate="$work_dir/cert.pem"
password="$(uuidgen)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

identity_exists=false
if has_identity; then
  identity_exists=true
  security find-certificate \
    -c "$IDENTITY_NAME" \
    -p "$LOGIN_KEYCHAIN" > "$certificate"

  if security verify-cert -c "$certificate" -p codeSign >/dev/null 2>&1; then
    echo "Signing identity already exists and is trusted: $IDENTITY_NAME"
    exit 0
  fi
fi

if [[ "${1:-}" != "--yes" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Creating or repairing the local signing identity requires confirmation." >&2
    echo "Run: $0" >&2
    exit 1
  fi

  echo "Window Layout needs a stable local code-signing identity so macOS can"
  echo "remember Accessibility permission after application updates."
  echo
  echo "This creates or repairs a self-signed Code Signing identity in:"
  echo "  $LOGIN_KEYCHAIN"
  read -r -p "Create '$IDENTITY_NAME'? [Y/n] " answer
  case "${answer:-Y}" in
    Y|y|Yes|yes) ;;
    *) echo "Cancelled."; exit 1 ;;
  esac
fi

if [[ "$identity_exists" == false ]]; then
  if ! openssl req \
    -new \
    -newkey rsa:2048 \
    -x509 \
    -sha256 \
    -days 3650 \
    -nodes \
    -config "$ROOT/Resources/local-codesign.cnf" \
    -subj "/CN=$IDENTITY_NAME/O=Window Layout" \
    -keyout "$work_dir/key.pem" \
    -out "$certificate" \
    2>"$work_dir/openssl.log"; then
    cat "$work_dir/openssl.log" >&2
    exit 1
  fi

  pkcs12_compatibility=()
  if openssl version 2>/dev/null | grep -q '^OpenSSL 3'; then
    pkcs12_compatibility=(-legacy)
  fi

  if ! openssl pkcs12 \
    -export \
    "${pkcs12_compatibility[@]}" \
    -inkey "$work_dir/key.pem" \
    -in "$certificate" \
    -name "$IDENTITY_NAME" \
    -passout "pass:$password" \
    -out "$work_dir/identity.p12" \
    2>"$work_dir/pkcs12.log"; then
    cat "$work_dir/pkcs12.log" >&2
    exit 1
  fi

  security import "$work_dir/identity.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$password" \
    -T /usr/bin/codesign
fi

security add-trusted-cert \
  -r trustRoot \
  -k "$LOGIN_KEYCHAIN" \
  "$certificate"

if ! has_identity; then
  echo "The signing identity was imported but is not available to codesign." >&2
  exit 1
fi

identity_hash="$(
  security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" |
    awk -v name="\"$IDENTITY_NAME\"" 'index($0, name) { print $2; exit }'
)"
cp /usr/bin/true "$work_dir/signing-probe"
codesign \
  --force \
  --keychain "$LOGIN_KEYCHAIN" \
  --sign "$identity_hash" \
  --identifier io.github.fxghqc.window-layout.signing-probe \
  "$work_dir/signing-probe"
codesign --verify --strict "$work_dir/signing-probe"

if [[ "$identity_exists" == true ]]; then
  echo "Repaired signing identity trust: $IDENTITY_NAME"
else
  echo "Created signing identity: $IDENTITY_NAME"
fi
