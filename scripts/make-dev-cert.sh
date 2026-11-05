#!/bin/zsh
# Creates a self-signed code-signing certificate called "Shades Dev" in your login
# keychain, for local development only. scripts/bundle.sh then signs with it, so
# rebuilds keep the same identity and macOS remembers the permissions you've granted.
#
# This changes your keychain, so nothing runs it for you. It adds one certificate and
# its private key, and asks for your password to trust it for code signing. Nothing
# leaves your Mac, and a build signed this way won't run on anyone else's without a warning.
# The first time scripts/bundle.sh signs with it, macOS may ask whether codesign can use
# the key. Choose Always Allow.
#
# To undo it:
#   security delete-identity -c "Shades Dev" ~/Library/Keychains/login.keychain-db
set -euo pipefail

name="Shades Dev"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -qF "\"$name\""; then
  echo "\"$name\" already exists, so there's nothing to do."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.conf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $name
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cert.conf" 2>/dev/null

# macOS's importer can't read the newer default encryption, so use the older one.
password="$(uuidgen)"
openssl pkcs12 -export -legacy -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/cert.p12" -passout "pass:$password" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
       -out "$work/cert.p12" -passout "pass:$password"

security import "$work/cert.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work/cert.pem"

echo "Created \"$name\". scripts/bundle.sh will sign with it from now on."
