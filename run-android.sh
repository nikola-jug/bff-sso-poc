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
EMULATOR="$ANDROID_HOME/emulator/emulator"

# /etc/hosts changes don't survive reboot on API 36. We re-establish hostname resolution
# two ways: --host-resolver-rules for Chrome/WebView, and /etc/hosts for native OkHttp
# (used by CapacitorHttp). Both are refreshed on every run.
RESOLVER_RULES="MAP spring-boot-auth-server 127.0.0.1,MAP oidc-identity-provider 127.0.0.1,MAP spring-boot-mobile-bff 127.0.0.1,MAP spring-boot-resource-server 127.0.0.1"

# Parse --target flag (device serial or AVD name).
# Usage: ./run-android.sh --target <serial|avd-name>
REQUESTED_TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) REQUESTED_TARGET="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Copy the mkcert root CA into res/raw so the Android Network Security Config
# can trust it at the app level (required for CapacitorHttp's OkHttp client).
echo "==> Copying mkcert CA into Android resources..."
mkdir -p "$MOBILE/android/app/src/main/res/raw"
cp "$ROOT/certs/rootCA.pem" "$MOBILE/android/app/src/main/res/raw/mkcert_ca.pem"

echo "==> Building Angular app (android)..."
npm --prefix "$MOBILE" run build -- --configuration=android

echo "sdk.dir=$ANDROID_HOME" > "$MOBILE/android/local.properties"

cd "$MOBILE"

echo "==> Syncing Capacitor..."
npx cap sync android

echo "==> Resolving target device..."

start_avd() {
  local avd="$1"
  echo "    Starting AVD: $avd..."
  # -writable-system is required so adb remount can re-populate /etc/hosts on each run,
  # which is needed for native OkHttp (CapacitorHttp) to resolve container hostnames.
  "$EMULATOR" -avd "$avd" -writable-system &
  echo "    Waiting for emulator to boot..."
  "$ADB" wait-for-device
  until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2
  done
  echo "    Emulator ready."
}

if [ -n "$REQUESTED_TARGET" ]; then
  # Check if it's already a connected device/emulator.
  if "$ADB" devices | awk 'NR>1 && $2=="device" {print $1}' | grep -qx "$REQUESTED_TARGET"; then
    TARGET="$REQUESTED_TARGET"
  else
    # Treat it as an AVD name and start it.
    start_avd "$REQUESTED_TARGET"
    TARGET=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')
  fi
else
  # No --target: list connected devices. If multiple, prompt to use --target.
  CONNECTED=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')
  COUNT=$(echo "$CONNECTED" | grep -c . 2>/dev/null || true)
  if [ "$COUNT" -gt 1 ]; then
    echo "ERROR: Multiple devices connected. Specify one with --target:"
    echo "$CONNECTED" | sed 's/^/    /'
    echo ""
    echo "    AVDs available:"
    "$EMULATOR" -list-avds 2>/dev/null | sed 's/^/    /'
    exit 1
  elif [ "$COUNT" -eq 1 ]; then
    TARGET="$CONNECTED"
  else
    # No device running — start the first available AVD.
    AVDS=$("$EMULATOR" -list-avds 2>/dev/null)
    if [ -z "$AVDS" ]; then
      echo "ERROR: No running device and no AVDs found. Create one in Android Studio/IntelliJ IDEA."
      exit 1
    fi
    start_avd "$(echo "$AVDS" | head -1)"
    TARGET=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')
  fi
fi
echo "    Target: $TARGET"

# /etc/hosts entries and the mkcert CA don't survive emulator restarts without
# -writable-system. Re-apply both so native OkHttp (CapacitorHttp) can resolve
# container hostnames and trust the mkcert TLS certificates.
# --host-resolver-rules only works for the WebView/Chrome, not native HTTP clients.
echo "==> Refreshing system partition (CA cert + /etc/hosts)..."
if "$ADB" root > /dev/null 2>&1 && "$ADB" remount > /dev/null 2>&1; then
  # Reinstall mkcert root CA so OkHttp trusts our self-signed certificates.
  CERT_HASH=$(openssl x509 -inform PEM -subject_hash_old -in "$ROOT/certs/rootCA.pem" | head -1)
  CERT_FILE="/tmp/${CERT_HASH}.0"
  openssl x509 -inform PEM -in "$ROOT/certs/rootCA.pem" -out "$CERT_FILE"
  "$ADB" push "$CERT_FILE" "/system/etc/security/cacerts/${CERT_HASH}.0" > /dev/null
  "$ADB" shell "chmod 644 /system/etc/security/cacerts/${CERT_HASH}.0"
  rm "$CERT_FILE"
  echo "    mkcert CA installed."

  # Re-add container hostnames so OkHttp can resolve them via DNS.
  TEMP_HOSTS=$(mktemp)
  "$ADB" shell cat /etc/hosts > "$TEMP_HOSTS"
  for HOST in spring-boot-auth-server spring-boot-web-bff spring-boot-mobile-bff spring-boot-resource-server oidc-identity-provider angular-ui-web; do
    if ! grep -q "$HOST" "$TEMP_HOSTS"; then
      echo "10.0.2.2 $HOST" >> "$TEMP_HOSTS"
    fi
  done
  "$ADB" push "$TEMP_HOSTS" /etc/hosts > /dev/null
  rm "$TEMP_HOSTS"
  echo "    /etc/hosts updated."
else
  echo "    WARNING: Could not remount system partition. If the emulator was started without"
  echo "    -writable-system, native HTTP (CapacitorHttp) will fail (cert + DNS not configured)."
  echo "    Stop the emulator and re-run this script to start it with -writable-system."
fi

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
