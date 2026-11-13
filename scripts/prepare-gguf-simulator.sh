#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "Xcode was not found at $DEVELOPER_DIR. Set DEVELOPER_DIR to your Xcode.app/Contents/Developer." >&2
    exit 1
fi

xcodebuild -resolvePackageDependencies \
    -project "$PROJECT_DIR/XiLiteAI.xcodeproj" \
    -scheme XiLiteAI

build_root="$(xcodebuild -showBuildSettings \
    -project "$PROJECT_DIR/XiLiteAI.xcodeproj" \
    -scheme XiLiteAI \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' 2>/dev/null \
    | sed -n 's/^[[:space:]]*BUILD_ROOT = //p' | head -1)"
if [[ -z "$build_root" ]]; then
    echo "Could not determine Xcode's DerivedData build folder." >&2
    exit 1
fi

derived_data="$(dirname "$(dirname "$build_root")")"
package_dir="$derived_data/SourcePackages/checkouts/swift-llama-cpp"
prepare_script="$package_dir/Scripts/prepare-apple-framework.sh"
if [[ ! -f "$prepare_script" ]]; then
    echo "SwiftLlama package checkout not found at $package_dir. Resolve packages in Xcode first." >&2
    exit 1
fi

bash "$prepare_script"
xcodebuild -resolvePackageDependencies \
    -project "$PROJECT_DIR/XiLiteAI.xcodeproj" \
    -scheme XiLiteAI

echo "GGUF simulator runtime prepared. You can now build/run the XiLiteAI scheme in an iOS Simulator."
