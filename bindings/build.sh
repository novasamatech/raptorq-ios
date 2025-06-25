#!/bin/bash

set -e

# Configuration
lib_name="raptorq"
output_dir="./xcframework"
release_dir="./target"
temp_dir="./temp"
bundle_id="com.yourcompany.${lib_name}"
min_macos_version="10.15"
min_ios_version="14.0"

# Get version from git or fallback to default
version=$(git describe --tags 2>/dev/null || echo "1.0.0")

# Terminal colors
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Logging function with colored output
log() {
    local level=$1
    shift
    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $@" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $@"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $@"
            ;;
        *)
            echo -e "${BLUE}[INFO]${NC} $@"
            ;;
    esac
}

# Check prerequisites
for cmd in cargo xcodebuild; do
    if ! command -v $cmd &> /dev/null; then
        log "ERROR" "$cmd command not found. Please install it first."
        exit 1
    fi
done

# Cleanup
log "INFO" "Cleaning previous builds"
rm -rf $output_dir $temp_dir
mkdir -p $output_dir $temp_dir

log "INFO" "Building .a libraries"

# All target architectures
targets=(
    "aarch64-apple-darwin"     # Apple Silicon Mac
    "aarch64-apple-ios"        # iOS devices
    "aarch64-apple-ios-sim"    # iOS Simulator (ARM)
)

# Determine number of CPU cores for parallel builds
cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)

for target in "${targets[@]}"; do
    log "INFO" "Building for $target"
    cargo build --release --target $target -j$cores || {
        log "ERROR" "Failed to build for $target"
        exit 1
    }
    
    # Create temporary framework structure
    framework_dir="$temp_dir/$target/$lib_name.framework"
    mkdir -p "$framework_dir/Headers" "$framework_dir/Modules"
    
    # Copy library
    cp "$release_dir/$target/release/lib${lib_name}.a" "$framework_dir/$lib_name" || {
        log "ERROR" "Failed to copy library for $target"
        exit 1
    }

    header_name="raptorq"
    
    # Copy headers
    if [[ ! -f "./generated/${header_name}/${header_name}.h" ]]; then
        log "ERROR" "Header files not found. Make sure they have been generated."
        exit 1
    fi
    
    cp "./generated/${header_name}/${header_name}.h" "$framework_dir/Headers/"
    
    # Determine platform-specific settings
    case $target in
        *"-apple-darwin")
            platform="MacOSX"
            sdk="macosx"
            min_os_version="$min_macos_version"
            ;;
        *"-apple-ios-sim")
            platform="iPhoneSimulator"
            sdk="iphonesimulator"
            min_os_version="$min_ios_version"
            ;;
        *"-apple-ios")
            platform="iPhoneOS"
            sdk="iphoneos"
            min_os_version="$min_ios_version"
            ;;
        *)
            log "ERROR" "Unsupported target: $target"
            continue
            ;;
    esac

    # Generate Info.plist
    cat <<EOF > "$framework_dir/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleName</key>
    <string>$lib_name</string>
    <key>CFBundleExecutable</key>
    <string>$lib_name</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleVersion</key>
    <string>${version}</string>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$platform</string>
    </array>
    <key>DTPlatformName</key>
    <string>$sdk</string>
    <key>DTSDKName</key>
    <string>$sdk</string>
    <key>MinimumOSVersion</key>
    <string>$min_os_version</string>
</dict>
</plist>
EOF

    # Create module map
    cat <<EOF >"$framework_dir/Modules/module.modulemap"
framework module ${lib_name} {
    umbrella header "../Headers/${header_name}.h"
    export *
}
EOF
    log "INFO" "Created framework for $target"
done

# Collect successful builds
log "INFO" "Creating XCFramework"
xcframework_args=()
for target in "${targets[@]}"; do
    if [[ -d "$temp_dir/$target/$lib_name.framework" ]]; then
        xcframework_args+=(
            -framework "$temp_dir/$target/$lib_name.framework"
        )
    else
        log "WARN" "Skipping missing framework for $target"
    fi
done

if [[ ${#xcframework_args[@]} -eq 0 ]]; then
    log "ERROR" "No frameworks were successfully built"
    exit 1
fi

# Create xcframework
xcodebuild -create-xcframework "${xcframework_args[@]}" -output "$output_dir/${lib_name}.xcframework" || {
    log "ERROR" "Failed to create XCFramework"
    exit 1
}

log "SUCCESS" "XCFramework created at $output_dir/${lib_name}.xcframework"

# Clean up temporary files
log "INFO" "Cleaning up"
rm -rf $temp_dir 

# Only remove generated files if build was successful
if [[ -d "$output_dir/${lib_name}.xcframework" ]]; then
    rm -rf generated $release_dir
    log "INFO" "Cleanup finished"
else
    log "WARN" "Keeping build artifacts for troubleshooting"
fi