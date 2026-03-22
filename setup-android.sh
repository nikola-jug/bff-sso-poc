#!/usr/bin/env bash
# Run this once after creating a new Android emulator (AOSP / Google APIs image, no Google Play Store).
# It installs the mkcert root CA as a system certificate, adds the container hostnames to /etc/hosts,
# and configures Chrome to ignore certificate errors (Chrome Root Store ignores system CAs on API 24+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${ANDROID_HOME:-}" ]; then
  echo "ERROR: ANDROID_HOME is not set. Add it to your shell profile, e.g.:"
  echo "    export ANDROID_HOME=\$HOME/Library/Android/sdk"
  exit 1
fi

ADB="$ANDROID_HOME/platform-tools/adb"

echo "==> Gaining root access on emulator..."
"$ADB" root || {
  echo "ERROR: Could not gain root."
  echo "       Use an AOSP emulator without Google Play Store (e.g. 'Google APIs' image)."
  exit 1
}

echo "==> Remounting system partition as writable..."
"$ADB" remount

echo "==> Installing mkcert root CA as system certificate..."
CERT_HASH=$(openssl x509 -inform PEM -subject_hash_old -in "$ROOT/certs/rootCA.pem" | head -1)
CERT_FILE="/tmp/${CERT_HASH}.0"
openssl x509 -inform PEM -in "$ROOT/certs/rootCA.pem" -out "$CERT_FILE"
"$ADB" push "$CERT_FILE" "/system/etc/security/cacerts/${CERT_HASH}.0"
"$ADB" shell "chmod 644 /system/etc/security/cacerts/${CERT_HASH}.0"

echo "==> Adding container hostnames to /etc/hosts..."
TEMP_HOSTS=$(mktemp)
"$ADB" shell cat /etc/hosts > "$TEMP_HOSTS"
cat >> "$TEMP_HOSTS" <<EOF
10.0.2.2 spring-boot-auth-server
10.0.2.2 spring-boot-web-bff
10.0.2.2 spring-boot-mobile-bff
10.0.2.2 spring-boot-resource-server
10.0.2.2 oidc-identity-provider
10.0.2.2 angular-ui-web
EOF
"$ADB" push "$TEMP_HOSTS" /etc/hosts
rm "$TEMP_HOSTS"

echo "==> Configuring Chrome to ignore certificate errors..."
"$ADB" shell "echo 'chrome --ignore-certificate-errors' > /data/local/tmp/chrome-command-line"
"$ADB" shell chmod 644 /data/local/tmp/chrome-command-line

echo "==> Rebooting emulator..."
"$ADB" reboot
"$ADB" wait-for-device

echo ""
echo "==> Emulator is ready. Run ./run-android.sh to deploy the app."