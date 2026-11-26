#!/bin/bash
# Builds the Liftoff target in release mode and assembles an ad-hoc signed build/Ignition.app.
# (The product is called Ignition; targets, bundle id and data dir keep the internal name Liftoff.)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP=build/Ignition.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/Liftoff" "$APP/Contents/MacOS/Ignition"  # CFBundleExecutable
cp Sources/LiftoffCore/Resources/voices.json "$APP/Contents/Resources/voices.json"
# SwiftPM resource bundles (e.g. Liftoff_LiftoffCore.bundle). VoiceCatalog looks in Contents/Resources;
# the generated Bundle.module would only look at the .app root, which codesign doesn't allow.
shopt -s nullglob
bundles=("$BIN"/*.bundle)
if [ ${#bundles[@]} -eq 0 ]; then
    echo "make-app: no SwiftPM resource bundle found in $BIN" >&2
    exit 1
fi
for bundle in "${bundles[@]}"; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# Default music + sample voice clips, seeded into the data dir on first launch.
mkdir -p "$APP/Contents/Resources/DefaultAssets"
cp -R Assets/music Assets/voices Assets/CREDITS.md "$APP/Contents/Resources/DefaultAssets/"

codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP"
