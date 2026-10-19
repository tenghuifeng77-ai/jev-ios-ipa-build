#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/source"
out="$root/dist"
logs="$root/logs"
build_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/jev-ios-build"
expected_source=f4b64cc655415091180e4c0573a2a82ca4319212

mkdir -p "$out" "$logs" "$build_root"
test "$(git -C "$src" rev-parse HEAD)" = "$expected_source"
test -z "$(git -C "$src" status --porcelain)"
patch="$root/patches/gpt61-sol.patch"
git -C "$src" apply --check "$patch"
git -C "$src" apply "$patch"
group_patch="$root/patches/app-group.patch"
git -C "$src" apply --check "$group_patch"
git -C "$src" apply "$group_patch"
git -C "$src" diff --check
xcodebuild -version | tee "$logs/xcode-version.txt"

# Exercise the shared-container selection before contacting the local HTTP fixture.
swiftc -swift-version 5 -D JEV_DYNAMIC_GROUP -parse-as-library -o "$build_root/shared-group-check" \
  "$root/tests/SharedGroupCheck/main.swift" "$src"/Shared/*.swift \
  2>&1 | tee "$logs/shared-group-check-build.log"
"$build_root/shared-group-check" 2>&1 | tee "$logs/shared-group-check.log"

# Verify real outgoing requests against a local provider contract before packaging.
python3 "$root/tests/request_contract.py" "$src" "$build_root" \
  2>&1 | tee "$logs/request-contract.log"

# Run the upstream offline checks against the patched application code.
swiftc -swift-version 5 -o "$build_root/prompt-check" \
  "$src/tools/PromptCheck/main.swift" "$src"/Shared/*.swift \
  2>&1 | tee "$logs/prompt-check-build.log"
"$build_root/prompt-check" 2>&1 | tee "$logs/prompt-check.log"

xcodebuild \
  -project "$src/JevJarvis.xcodeproj" \
  -scheme JevJarvis \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_root/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CURRENT_PROJECT_VERSION=4 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
  build 2>&1 | tee "$logs/xcodebuild.log"

stage="$build_root/package"
mkdir -p "$stage/Payload"
app="$stage/Payload/JevJarvis.app"
/usr/bin/ditto "$build_root/DerivedData/Build/Products/Release-iphoneos/JevJarvis.app" "$app"
extension="$app/PlugIns/JevKeyboard.appex"
test -d "$extension"

# Preserve attribution in the binary distribution as well as beside the IPA.
cp "$src/LICENSE" "$app/JevSource-LICENSE.txt"
cp "$src/NOTICE" "$app/JevSource-NOTICE.txt"
cp "$src/LICENSE" "$out/LICENSE.txt"
cp "$src/NOTICE" "$out/NOTICE.txt"
cp "$src/App/JevJarvis.entitlements" "$out/App.entitlements.plist"
cp "$src/Keyboard/JevKeyboard.entitlements" "$out/Keyboard.entitlements.plist"
cp "$root/INSTALL.zh-CN.txt" "$out/INSTALL.zh-CN.txt"

# These are local ad-hoc signatures, NOT Apple-issued installation signatures.
# They carry the original App Group requirements for a re-signing tool to read.
codesign --force --sign - --entitlements "$src/Keyboard/JevKeyboard.entitlements" \
  --generate-entitlement-der "$extension"
codesign --force --sign - --entitlements "$src/App/JevJarvis.entitlements" \
  --generate-entitlement-der "$app"
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | tee "$logs/codesign-verify.log"
codesign -d --entitlements :- "$extension" > "$logs/keyboard-entitlements.plist" 2> "$logs/keyboard-signature.txt"
codesign -d --entitlements :- "$app" > "$logs/app-entitlements.plist" 2> "$logs/app-signature.txt"
python3 "$root/scripts/verify-package.py" "$app" | tee "$out/package-verification.json"

ipa="$out/JevKeyboard-0.1.0-appgroup-fix-resign.ipa"
/usr/bin/ditto -c -k --keepParent "$stage/Payload" "$ipa"
unzip -t "$ipa" > "$logs/ipa-integrity.txt"
(cd "$out" && shasum -a 256 "$(basename "$ipa")" > SHA256SUMS.txt)
{
  printf 'Upstream: https://github.com/jev-chat/jev-chat-jarvis-ios\n'
  printf 'Source commit: %s\n' "$expected_source"
  printf 'Local patch: GPT-6.1 Sol request compatibility and 120-second request budget\n'
  printf 'Local patch: select a provisioned App Group after OS container authorization\n'
  printf 'Application build: 4\n'
  printf 'Signing: local ad-hoc only; requires valid Apple re-signing before installation\n'
  printf 'Architecture: arm64; SDK: iphoneos; configuration: Release\n'
  printf 'Build run: https://github.com/%s/actions/runs/%s\n' "${GITHUB_REPOSITORY:-local}" "${GITHUB_RUN_ID:-local}"
  cat "$logs/xcode-version.txt"
} > "$out/BUILD-INFO.txt"
git -C "$src" apply --reverse --check "$patch"
git -C "$src" apply --reverse --check "$group_patch"
git -C "$src" diff --binary > "$out/SOURCE-CHANGES.patch"
git -C "$src" apply --reverse "$group_patch"
git -C "$src" apply --reverse "$patch"
test -z "$(git -C "$src" status --porcelain)"
