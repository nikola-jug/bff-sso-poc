#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MOBILE="$ROOT/ionic-mobile"

if [ -z "${ANDROID_HOME:-}" ]; then
  echo "ERROR: ANDROID_HOME is not set. Add it to your shell profile, e.g.:"
  echo "    export ANDROID_HOME=\$HOME/Library/Android/sdk"
  exit 1
fi

ADB="$ANDROID_HOME/platform-tools/adb"

# /etc/hosts changes don't survive reboot on API 36, so we re-establish hostname
# resolution via --host-resolver-rules on every run.
RESOLVER_RULES="MAP spring-boot-auth-server 127.0.0.1,MAP oidc-identity-provider 127.0.0.1,MAP spring-boot-mobile-bff 127.0.0.1,MAP spring-boot-resource-server 127.0.0.1"

echo "==> Building Angular app (android)..."
npm --prefix "$MOBILE" run build -- --configuration=android

echo "sdk.dir=$ANDROID_HOME" > "$MOBILE/android/local.properties"

cd "$MOBILE"

echo "==> Syncing Capacitor..."
npx cap sync android

echo "==> Launching on Android Emulator..."
# Auto-select the first connected device/emulator to avoid the interactive picker.
TARGET=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')
if [ -z "$TARGET" ]; then
  echo "ERROR: No connected Android device or emulator found."
  exit 1
fi
echo "    Target: $TARGET"
npx cap run android --target "$TARGET"

# Re-establish tunnels after deploy — APK install can briefly reset adb state.
echo "==> Setting up adb reverse tunnels..."
"$ADB" reverse tcp:9000 tcp:9000   # spring-boot-auth-server
"$ADB" reverse tcp:8443 tcp:8443   # oidc-identity-provider (Keycloak)
"$ADB" reverse tcp:8082 tcp:8082   # spring-boot-mobile-bff
"$ADB" reverse tcp:8090 tcp:8090   # spring-boot-resource-server

echo "==> Configuring hostname resolution in browser and WebView..."
"$ADB" shell "echo '_ --ignore-certificate-errors --host-resolver-rules=\"${RESOLVER_RULES}\"' > /data/local/tmp/webview-command-line"
"$ADB" shell chmod 644 /data/local/tmp/webview-command-line
"$ADB" shell "echo 'chrome --ignore-certificate-errors --host-resolver-rules=\"${RESOLVER_RULES}\"' > /data/local/tmp/chrome-command-line"
"$ADB" shell chmod 644 /data/local/tmp/chrome-command-line
echo "==> Ready."
