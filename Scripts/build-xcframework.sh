#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2024 WireGuardKit. All Rights Reserved.
#
# build-xcframework.sh - Phase 2: Create XCFramework
#
# This script creates a WireGuardKit.xcframework from the static libraries
# built in Phase 1. The XCFramework includes:
#   - ios-arm64: For physical devices (iPhone/iPad)
#   - ios-arm64_x86_64-simulator: For simulators (Intel + Apple Silicon)
#
# The script creates proper framework structures with headers, module maps,
# and Info.plist files, then uses xcodebuild to package them into an XCFramework.
#
# Prerequisites:
#   - Phase 1 must be completed (run build-wireguard-go.sh first)
#
# Output:
#   Artifacts/WireGuardKit.xcframework/

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly FRAMEWORK_NAME="WireGuardKit"
readonly BUNDLE_ID="com.wireguard.WireGuardKit"
readonly XCFRAMEWORK_OUTPUT="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}.xcframework"

# Framework build paths
readonly DEVICE_FRAMEWORK="${FRAMEWORKS_DIR}/${FRAMEWORK_NAME}-device.framework"
readonly SIMULATOR_FRAMEWORK="${FRAMEWORKS_DIR}/${FRAMEWORK_NAME}-simulator.framework"

# Framework names inside XCFramework (after xcodebuild processes them)
readonly DEVICE_FRAMEWORK_NAME="${FRAMEWORK_NAME}-device"
readonly SIMULATOR_FRAMEWORK_NAME="${FRAMEWORK_NAME}-simulator"

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
    log_section "Checking Prerequisites"

    # Check if Go libraries exist
    local device_lib="${LIBRARIES_DIR}/${TARGET_DEVICE_ARM64}/libwg-go.a"
    local simulator_lib="${LIBRARIES_DIR}/${TARGET_SIMULATOR_FAT}/libwg-go.a"

    if ! check_file_exists "$device_lib"; then
        log_error "Device library not found: ${device_lib}"
        log_error "Please run Scripts/build-wireguard-go.sh first"
        exit 1
    fi

    if ! check_file_exists "$simulator_lib"; then
        log_error "Simulator library not found: ${simulator_lib}"
        log_error "Please run Scripts/build-wireguard-go.sh first"
        exit 1
    fi

    # Check if header files exist
    if [ ! -f "${WIREGUARD_GO_DIR}/wireguard.h" ]; then
        log_error "WireGuard header not found: ${WIREGUARD_GO_DIR}/wireguard.h"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# ============================================================================
# Framework Creation Functions
# ============================================================================

# Create framework structure and populate it
# Usage: create_framework <framework-path> <library-path> <platform-name>
create_framework() {
    local framework_path="$1"
    local library_path="$2"
    local platform_name="$3"

    log_info "Creating framework for ${platform_name}..."

    # Remove old framework if it exists
    if [ -d "$framework_path" ]; then
        rm -rf "$framework_path"
    fi

    # Create framework directory structure
    local headers_dir="${framework_path}/Headers"
    local modules_dir="${framework_path}/Modules"

    ensure_dir "$headers_dir"
    ensure_dir "$modules_dir"

    # Extract the framework basename (without .framework extension)
    local framework_basename
    framework_basename=$(basename "$framework_path" .framework)

    # Copy the static library as the framework binary
    # The binary name must match the framework basename
    log_info "Copying binary..."
    cp "$library_path" "${framework_path}/${framework_basename}"

    # Create umbrella header
    log_info "Creating umbrella header..."
    cat > "${headers_dir}/${FRAMEWORK_NAME}.h" << 'EOF'
// SPDX-License-Identifier: MIT
// Copyright (C) 2024 WireGuardKit. All Rights Reserved.

#import <Foundation/Foundation.h>

//! Project version number for WireGuardKit
FOUNDATION_EXPORT double WireGuardKitVersionNumber;

//! Project version string for WireGuardKit
FOUNDATION_EXPORT const unsigned char WireGuardKitVersionString[];

// WireGuard C API
#import <WireGuardKit/wireguard.h>
EOF

    # Copy WireGuard header
    log_info "Copying WireGuard header..."
    cp "${WIREGUARD_GO_DIR}/wireguard.h" "${headers_dir}/"

    # Create module map
    log_info "Creating module map..."
    cat > "${modules_dir}/module.modulemap" << 'EOF'
framework module WireGuardKit {
    umbrella header "WireGuardKit.h"
    export *
    module * { export * }

    explicit module C {
        header "wireguard.h"
        export *
    }
}
EOF

    # Create Info.plist
    log_info "Creating Info.plist..."
    cat > "${framework_path}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${framework_basename}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${MIN_IOS_VERSION}</string>
</dict>
</plist>
EOF

    log_success "Framework created: ${framework_path}"
}

# ============================================================================
# XCFramework Creation
# ============================================================================

create_xcframework() {
    log_section "Creating XCFramework"

    # Create device framework
    local device_lib="${LIBRARIES_DIR}/${TARGET_DEVICE_ARM64}/libwg-go.a"
    create_framework "$DEVICE_FRAMEWORK" "$device_lib" "iOS Device"

    # Create simulator framework
    local simulator_lib="${LIBRARIES_DIR}/${TARGET_SIMULATOR_FAT}/libwg-go.a"
    create_framework "$SIMULATOR_FRAMEWORK" "$simulator_lib" "iOS Simulator"

    # Remove old XCFramework if it exists
    if [ -d "$XCFRAMEWORK_OUTPUT" ]; then
        log_info "Removing existing XCFramework..."
        rm -rf "$XCFRAMEWORK_OUTPUT"
    fi

    # Create output directory
    ensure_dir "$ARTIFACTS_DIR"

    # Create XCFramework using xcodebuild
    log_info "Running xcodebuild to create XCFramework..."

    xcodebuild -create-xcframework \
        -framework "$DEVICE_FRAMEWORK" \
        -framework "$SIMULATOR_FRAMEWORK" \
        -output "$XCFRAMEWORK_OUTPUT"

    # Verify XCFramework was created
    if ! check_file_exists "${XCFRAMEWORK_OUTPUT}/Info.plist"; then
        log_error "XCFramework creation failed"
        exit 1
    fi

    log_success "XCFramework created successfully"
}

# ============================================================================
# Validation
# ============================================================================

validate_xcframework() {
    log_section "Validating XCFramework"

    # Check XCFramework structure
    if [ ! -d "$XCFRAMEWORK_OUTPUT" ]; then
        log_error "XCFramework directory not found"
        exit 1
    fi

    # Check Info.plist
    if ! check_file_exists "${XCFRAMEWORK_OUTPUT}/Info.plist"; then
        log_error "XCFramework Info.plist not found"
        exit 1
    fi

    # Check for both platform variants
    local device_variant="${XCFRAMEWORK_OUTPUT}/ios-arm64"
    local simulator_variant="${XCFRAMEWORK_OUTPUT}/ios-arm64_x86_64-simulator"

    if [ ! -d "$device_variant" ]; then
        log_error "Device variant not found in XCFramework"
        exit 1
    fi

    if [ ! -d "$simulator_variant" ]; then
        log_error "Simulator variant not found in XCFramework"
        exit 1
    fi

    # Verify device binary architecture
    local device_binary="${device_variant}/${DEVICE_FRAMEWORK_NAME}.framework/${DEVICE_FRAMEWORK_NAME}"
    if check_file_exists "$device_binary"; then
        if check_binary_arch "$device_binary" "arm64"; then
            log_success "Device binary has correct architecture (arm64)"
        else
            log_error "Device binary has incorrect architecture"
            exit 1
        fi
    else
        log_error "Device binary not found"
        exit 1
    fi

    # Verify simulator binary architectures
    local simulator_binary="${simulator_variant}/${SIMULATOR_FRAMEWORK_NAME}.framework/${SIMULATOR_FRAMEWORK_NAME}"
    if check_file_exists "$simulator_binary"; then
        if check_binary_arch "$simulator_binary" "x86_64" "arm64"; then
            log_success "Simulator binary has correct architectures (x86_64, arm64)"
        else
            log_error "Simulator binary has incorrect architectures"
            exit 1
        fi
    else
        log_error "Simulator binary not found"
        exit 1
    fi

    # Check for headers
    local device_headers="${device_variant}/${DEVICE_FRAMEWORK_NAME}.framework/Headers"
    if [ -d "$device_headers" ]; then
        if [ -f "${device_headers}/wireguard.h" ] && [ -f "${device_headers}/${FRAMEWORK_NAME}.h" ]; then
            log_success "Headers found and valid"
        else
            log_error "Required headers missing"
            exit 1
        fi
    else
        log_error "Headers directory not found"
        exit 1
    fi

    # Check for module map
    local device_modules="${device_variant}/${DEVICE_FRAMEWORK_NAME}.framework/Modules"
    if [ -f "${device_modules}/module.modulemap" ]; then
        log_success "Module map found"
    else
        log_error "Module map not found"
        exit 1
    fi

    log_success "XCFramework validation passed"
}

# ============================================================================
# Main Build Flow
# ============================================================================

main() {
    log_section "XCFramework Build - Phase 2"

    # Step 1: Check prerequisites
    check_prerequisites

    # Step 2: Create frameworks
    log_section "Creating Framework Structures"
    ensure_dir "$FRAMEWORKS_DIR"

    # Step 3: Create XCFramework
    create_xcframework

    # Step 4: Validate XCFramework
    validate_xcframework

    # Step 5: Summary
    log_section "Build Summary"
    log_success "XCFramework built successfully"
    echo ""
    log_info "Output:"
    log_info "  ${XCFRAMEWORK_OUTPUT}"
    echo ""
    log_info "Framework size:"

    # Calculate total size
    local xcf_size
    xcf_size=$(du -sh "$XCFRAMEWORK_OUTPUT" | awk '{print $1}')
    log_info "  Total: ${xcf_size}"

    echo ""
    log_info "Platforms:"
    log_info "  ✓ ios-arm64 (iPhone, iPad)"
    log_info "  ✓ ios-arm64_x86_64-simulator (Intel + Apple Silicon Macs)"
    echo ""
    log_info "Next step: Run Scripts/verify-build.sh"
}

# Run main function
main "$@"
