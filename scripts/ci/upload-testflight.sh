#!/usr/bin/env bash
# Uploads an .ipa to App Store Connect (TestFlight) with an App Store Connect
# API key. Tries `altool` first and falls back to `xcodebuild -exportArchive`
# with destination=upload (Apple's two supported command-line upload paths).
#
# Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, APPLE_TEAM_ID, BUNDLE_ID, PP_NAME
set -euo pipefail

IPA="$1"
KEY_DIR="$HOME/.appstoreconnect/private_keys"
KEY_PATH="$KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
mkdir -p "$KEY_DIR"
printf '%s\n' "$ASC_PRIVATE_KEY" > "$KEY_PATH"
chmod 600 "$KEY_PATH"

echo "Uploading $IPA with altool…"
if xcrun altool --upload-app --type ios --file "$IPA" \
     --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"; then
  echo "Upload finished (altool)."
  exit 0
fi

echo "::warning::altool upload failed - retrying with xcodebuild -exportArchive (destination=upload)"
cat > "$RUNNER_TEMP/UploadOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key><string>${PP_NAME}</string>
  </dict>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$RUNNER_TEMP/Familoq.xcarchive" \
  -exportOptionsPlist "$RUNNER_TEMP/UploadOptions.plist" \
  -exportPath "$RUNNER_TEMP/upload" \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
echo "Upload finished (xcodebuild)."
