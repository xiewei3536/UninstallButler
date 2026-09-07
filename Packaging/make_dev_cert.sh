#!/bin/bash
# 建立固定的自簽「程式碼簽章」身分（UninstallButler Dev），放在專用鑰匙圈。
# 每次建置都用同一個身分簽名，macOS 的「完整磁碟取用」授權才會跨版本保留
#（ad-hoc 簽章每次建置都不同，授權會失效）。
#
#   ./Packaging/make_dev_cert.sh      # 執行一次；之後 build.sh 會自動偵測並使用
#
# 唯一需要互動的步驤：信任這張憑證用於簽章，macOS 會要求輸入一次登入密碼。
set -euo pipefail

NAME="${UNINSTALLBUTLER_SIGN_IDENTITY:-UninstallButler Dev}"
KC="$HOME/Library/Keychains/uninstallbutler-dev.keychain-db"
PASS_FILE="$HOME/Library/Application Support/UninstallButler/dev-keychain.pass"

if [[ -f "$KC" ]] && security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "✓ 身分「$NAME」已存在於 $KC"
  exit 0
fi

mkdir -p "$(dirname "$PASS_FILE")"
if [[ -f "$PASS_FILE" ]]; then
  PASS="$(cat "$PASS_FILE")"
else
  PASS="$(openssl rand -hex 24)"
  (umask 077; printf '%s' "$PASS" > "$PASS_FILE")
fi

if [[ ! -f "$KC" ]]; then
  security create-keychain -p "$PASS" "$KC"
fi
security set-keychain-settings "$KC"
security unlock-keychain -p "$PASS" "$KC"

if ! security list-keychains -d user | grep -q "uninstallbutler-dev.keychain-db"; then
  existing=()
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
    [[ -n "$line" ]] && existing+=("$line")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "${existing[@]}" "$KC"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
O = UninstallButler (local development)
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/ext.cnf" 2>/dev/null

openssl rsa -in "$TMP/key.pem" -out "$TMP/key_rsa.pem" 2>/dev/null
security import "$TMP/key_rsa.pem" -k "$KC" -t priv -f openssl -T /usr/bin/codesign -T /usr/bin/security >/dev/null
echo "▸ 信任「$NAME」用於程式碼簽章 — macOS 會要求輸入一次登入密碼。"
if ! security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"; then
  echo "✗ 未套用信任設定（對話框被取消？）。憑證在被信任前無法使用，請重新執行本腳本。"
  exit 1
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null 2>&1 || true

echo "✓ 身分已就緒："
security find-identity -v -p codesigning "$KC" | grep "$NAME" || true
echo "  build.sh 之後會自動用「$NAME」簽名。"
