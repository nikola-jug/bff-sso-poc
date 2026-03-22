#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MOBILE="$ROOT/ionic-mobile"

echo "==> Building Angular app (ios)..."
npm --prefix "$MOBILE" run build -- --configuration=ios

cd "$MOBILE"

echo "==> Syncing Capacitor..."
npx cap sync ios

echo "==> Opening Xcode..."
npx cap open ios
