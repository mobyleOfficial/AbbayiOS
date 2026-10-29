#!/bin/bash
# Captures the five App Store screenshots of one slot in one language (#252).
#
#   StoreConfig/screenshots/capture.sh <simulator-udid> <en-US|pt-BR> <slot> [library-udid]
#
# <slot> names the files: StoreConfig/screenshots/<lang>/<slot>_<n>-<screen>.jpg, e.g. duo-inner.
# [library-udid] is a simulator whose Abbay already holds that language's demo library (the
# LibriVox books the shots show); its app data is copied over the target's first. Without it the
# target's own library is used.
#
# What it does:
#  1. builds Abbay and its UI tests for the target (Debug, as UI tests need);
#  2. copies the demo library (app container and App Group container) from [library-udid];
#  3. sets the status bar to 9:41, full battery and signal;
#  4. runs StoreScreenshotsUITests/test_storeScreens, which drives the five screens and asks for a
#     shot at each; this script takes it with `xcrun simctl io screenshot` (the only capture that
#     sees the unfolded iPhone Duo's inner display);
#  5. converts each PNG to a JPEG with no alpha channel, as App Store Connect wants.
#
# The simulator's posture (an iPhone Duo folded or unfolded) is whatever it is: fold it in DeviceHub
# first. A 13-inch iPad simulator opens the app full screen (a smaller one can open a window).
set -euo pipefail

UDID=$1; LANG_CODE=$2; SLOT=$3; LIBRARY=${4:-}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT_DIR="$ROOT/StoreConfig/screenshots/$LANG_CODE"
WORK=$(mktemp -d "$ROOT/build/store-shots.XXXX")
BUNDLE=com.edyuto.Abbay
GROUP=group.com.edyuto.abbay
DEVICES=~/Library/Developer/CoreSimulator/Devices

# The data container (or App Group container) of $BUNDLE on a simulator, from the containers'
# metadata, so the source simulator need not be booted.
container() {
  local udid=$1 kind=$2 id=$3
  for dir in "$DEVICES/$udid/data/Containers/$kind"/*; do
    if [ "$(plutil -extract MCMMetadataIdentifier raw "$dir/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null)" = "$id" ]; then
      echo "$dir"; return
    fi
  done
}

cd "$ROOT"
mkdir -p build "$OUT_DIR"
xcrun simctl boot "$UDID" 2>/dev/null || true
bundle exec Scripts/xcodegen >/dev/null
ruby Scripts/updateversion.rb >/dev/null

echo "Building for $UDID"
xcodebuild build-for-testing -project Abbay.xcodeproj -scheme AbbayUITests -destination "id=$UDID" \
  -derivedDataPath build/store-shots-dd-$UDID > "$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log"; exit 1; }
xcrun simctl install "$UDID" build/store-shots-dd-$UDID/Build/Products/Debug-iphonesimulator/Abbay.app


if [ -n "$LIBRARY" ]; then
  echo "Copying the $LANG_CODE library from $LIBRARY"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  SRC_APP=$(container "$LIBRARY" Data/Application "$BUNDLE")
  SRC_GROUP=$(container "$LIBRARY" Shared/AppGroup "$GROUP")
  DST_APP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  DST_GROUP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" groups | awk -v g="$GROUP" '$1 == g { print $2 }')
  [ -n "$SRC_APP" ] && [ -n "$DST_APP" ] || { echo "no Abbay container on $LIBRARY or $UDID"; exit 1; }
  rsync -a --delete --exclude .com.apple.mobile_container_manager.metadata.plist --exclude 'Library/Caches' \
    --exclude 'Library/SplashBoard' "$SRC_APP/" "$DST_APP/"
  if [ -n "$SRC_GROUP" ] && [ -n "$DST_GROUP" ]; then
    rsync -a --delete --exclude .com.apple.mobile_container_manager.metadata.plist "$SRC_GROUP/" "$DST_GROUP/"
  fi
fi

xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

# Serve the test's shot requests.
( while true; do
    for request in "$WORK"/*.request; do
      [ -e "$request" ] || continue
      xcrun simctl io "$UDID" screenshot "${request%.request}.png" >/dev/null 2>&1
      rm -f "$request"
    done
    sleep 0.3
  done ) & SHOOTER=$!
trap 'kill $SHOOTER 2>/dev/null || true' EXIT

echo "Driving the screens ($LANG_CODE)"
TEST_RUNNER_ABBAY_STORE_SHOTS_DIR="$WORK" TEST_RUNNER_ABBAY_STORE_SHOTS_PREFIX="$SLOT" \
  TEST_RUNNER_ABBAY_STORE_SHOTS_LANG="$LANG_CODE" \
  xcodebuild test-without-building -project Abbay.xcodeproj -scheme AbbayUITests -destination "id=$UDID" \
  -derivedDataPath build/store-shots-dd-$UDID -parallel-testing-enabled NO \
  -only-testing:AbbayUITests/StoreScreenshotsUITests/test_storeScreens > "$WORK/test.log" 2>&1 \
  || { grep -E "error: -\[|failed" "$WORK/test.log" | head -5; ls "$WORK"/*.png 2>/dev/null; exit 1; }

for png in "$WORK/$SLOT"-[0-9]*.png; do
  name=$(basename "$png" .png)
  sips -s format jpeg -s formatOptions 90 "$png" --out "$OUT_DIR/${SLOT}_${name#"$SLOT"-}.jpg" >/dev/null
  echo "  $OUT_DIR/${SLOT}_${name#"$SLOT"-}.jpg"
done
