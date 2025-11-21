#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2024 WireGuardKit. All Rights Reserved.
#
# verify-build.sh - Phase 3: Comprehensive Validation
#
# This script performs comprehensive validation of the built XCFramework:
#   - Verifies XCFramework structure and Info.plist
#   - Checks both platform variants (device and simulator)
#   - Validates binary architectures using lipo
#   - Verifies WireGuard symbols are present
#   - Checks headers and module maps
#   - Reports sizes and provides detailed summary
#
# Prerequisites:
#   - Phase 2 must be completed (run build-xcframework.sh first)
#
# Exit codes:
#   0 - All validations passed
#   1 - One or more validations failed

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly FRAMEWORK_NAME="WireGuardKit"
readonly XCFRAMEWORK_PATH="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}.xcframework"

# Framework names inside XCFramework (as created by xcodebuild)
readonly DEVICE_FRAMEWORK_NAME="WireGuardKit-device"
readonly SIMULATOR_FRAMEWORK_NAME="WireGuardKit-simulator"

# Track validation results
VALIDATION_PASSED=0
VALIDATION_FAILED=0

# ============================================================================
# Validation Helper Functions
# ============================================================================

# Run a validation check and track results
# Usage: run_check "Check description" check_function [args...]
run_check() {
    local description="$1"
    shift
    local check_func="$1"
    shift

    echo -n "  ${description}... "

    if "$check_func" "$@" &> /dev/null; then
        echo -e "${COLOR_GREEN}✓${COLOR_RESET}"
        ((VALIDATION_PASSED++)) || true
        return 0
    else
        echo -e "${COLOR_RED}✗${COLOR_RESET}"
        ((VALIDATION_FAILED++)) || true
        return 1
    fi
}

# ============================================================================
# XCFramework Structure Validation
# ============================================================================

validate_xcframework_exists() {
    [ -d "$XCFRAMEWORK_PATH" ]
}

validate_info_plist() {
    [ -f "${XCFRAMEWORK_PATH}/Info.plist" ]
}

validate_device_variant_exists() {
    [ -d "${XCFRAMEWORK_PATH}/ios-arm64" ]
}

validate_simulator_variant_exists() {
    [ -d "${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator" ]
}

# ============================================================================
# Binary Validation Functions
# ============================================================================

validate_device_binary() {
    local binary="${XCFRAMEWORK_PATH}/ios-arm64/${DEVICE_FRAMEWORK_NAME}.framework/${DEVICE_FRAMEWORK_NAME}"
    check_file_exists "$binary" && check_binary_arch "$binary" "arm64"
}

validate_simulator_binary() {
    local binary="${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${SIMULATOR_FRAMEWORK_NAME}.framework/${SIMULATOR_FRAMEWORK_NAME}"
    check_file_exists "$binary" && check_binary_arch "$binary" "x86_64" "arm64"
}

validate_device_symbols() {
    local binary="${XCFRAMEWORK_PATH}/ios-arm64/${DEVICE_FRAMEWORK_NAME}.framework/${DEVICE_FRAMEWORK_NAME}"
    check_wireguard_symbols "$binary"
}

validate_simulator_symbols() {
    local binary="${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${SIMULATOR_FRAMEWORK_NAME}.framework/${SIMULATOR_FRAMEWORK_NAME}"
    check_wireguard_symbols "$binary"
}

# ============================================================================
# Header and Module Validation
# ============================================================================

validate_device_headers() {
    local headers_dir="${XCFRAMEWORK_PATH}/ios-arm64/${DEVICE_FRAMEWORK_NAME}.framework/Headers"
    [ -f "${headers_dir}/${FRAMEWORK_NAME}.h" ] && [ -f "${headers_dir}/wireguard.h" ]
}

validate_simulator_headers() {
    local headers_dir="${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${SIMULATOR_FRAMEWORK_NAME}.framework/Headers"
    [ -f "${headers_dir}/${FRAMEWORK_NAME}.h" ] && [ -f "${headers_dir}/wireguard.h" ]
}

validate_device_modulemap() {
    local modulemap="${XCFRAMEWORK_PATH}/ios-arm64/${DEVICE_FRAMEWORK_NAME}.framework/Modules/module.modulemap"
    [ -f "$modulemap" ]
}

validate_simulator_modulemap() {
    local modulemap="${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${SIMULATOR_FRAMEWORK_NAME}.framework/Modules/module.modulemap"
    [ -f "$modulemap" ]
}

validate_device_info_plist() {
    local plist="${XCFRAMEWORK_PATH}/ios-arm64/${DEVICE_FRAMEWORK_NAME}.framework/Info.plist"
    [ -f "$plist" ]
}

validate_simulator_info_plist() {
    local plist="${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${SIMULATOR_FRAMEWORK_NAME}.framework/Info.plist"
    [ -f "$plist" ]
}

# ============================================================================
# Detailed Analysis Functions
# ============================================================================

analyze_binary() {
    local binary_path="$1"
    local platform="$2"

    if [ ! -f "$binary_path" ]; then
        log_error "Binary not found: ${binary_path}"
        return 1
    fi

    echo ""
    log_info "Analyzing ${platform} binary:"

    # Get file size
    local size
    size=$(get_file_size "$binary_path")
    echo "    Size: ${size}"

    # Get architectures
    local archs
    archs=$(get_binary_archs "$binary_path")
    echo "    Architectures: ${archs}"

    # List some key symbols
    echo "    Key WireGuard symbols:"
    if nm "$binary_path" 2>/dev/null | grep -E "wgTurnOn|wgTurnOff|wgSetConfig|wgGetConfig" | head -5 | while read -r line; do
        local symbol
        symbol=$(echo "$line" | awk '{print $NF}')
        echo "      - ${symbol}"
    done; then
        :
    else
        echo "      (no symbols found)"
    fi

    # Check for bitcode (deprecated, but good to know)
    if otool -l "$binary_path" 2>/dev/null | grep -q "__LLVM"; then
        log_warn "    Bitcode section detected (deprecated in Xcode 14+)"
    fi
}

# ============================================================================
# Main Validation Flow
# ============================================================================

main() {
    log_section "XCFramework Verification - Phase 3"

    # Check if XCFramework exists
    if [ ! -d "$XCFRAMEWORK_PATH" ]; then
        log_error "XCFramework not found: ${XCFRAMEWORK_PATH}"
        log_error "Please run Scripts/build-xcframework.sh first"
        exit 1
    fi

    # ========================================================================
    # Structure Validation
    # ========================================================================

    log_section "Validating XCFramework Structure"

    run_check "XCFramework exists" validate_xcframework_exists
    run_check "Info.plist present" validate_info_plist
    run_check "Device variant (ios-arm64)" validate_device_variant_exists
    run_check "Simulator variant (ios-arm64_x86_64-simulator)" validate_simulator_variant_exists

    # ========================================================================
    # Device Binary Validation
    # ========================================================================

    log_section "Validating Device Binary (ios-arm64)"

    run_check "Binary exists and has arm64" validate_device_binary
    run_check "WireGuard symbols present" validate_device_symbols
    run_check "Headers present" validate_device_headers
    run_check "Module map present" validate_device_modulemap
    run_check "Info.plist present" validate_device_info_plist

    # ========================================================================
    # Simulator Binary Validation
    # ========================================================================

    log_section "Validating Simulator Binary (ios-arm64_x86_64-simulator)"

    run_check "Binary exists and has x86_64 + arm64" validate_simulator_binary
    run_check "WireGuard symbols present" validate_simulator_symbols
    run_check "Headers present" validate_simulator_headers
    run_check "Module map present" validate_simulator_modulemap
    run_check "Info.plist present" validate_simulator_info_plist

    # ========================================================================
    # Detailed Analysis
    # ========================================================================

    log_section "Detailed Binary Analysis"

    local device_binary="${XCFRAMEWORK_PATH}/ios-arm64/${DEVICE_FRAMEWORK_NAME}.framework/${DEVICE_FRAMEWORK_NAME}"
    local simulator_binary="${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${SIMULATOR_FRAMEWORK_NAME}.framework/${SIMULATOR_FRAMEWORK_NAME}"

    analyze_binary "$device_binary" "Device"
    analyze_binary "$simulator_binary" "Simulator"

    # ========================================================================
    # Size Report
    # ========================================================================

    log_section "Size Report"

    echo ""
    log_info "XCFramework total size:"
    local total_size
    total_size=$(du -sh "$XCFRAMEWORK_PATH" | awk '{print $1}')
    echo "  ${total_size}"

    echo ""
    log_info "Individual platform sizes:"

    local device_size
    device_size=$(du -sh "${XCFRAMEWORK_PATH}/ios-arm64" | awk '{print $1}')
    echo "  Device (arm64):       ${device_size}"

    local simulator_size
    simulator_size=$(du -sh "${XCFRAMEWORK_PATH}/ios-arm64_x86_64-simulator" | awk '{print $1}')
    echo "  Simulator (fat):      ${simulator_size}"

    # ========================================================================
    # Final Summary
    # ========================================================================

    log_section "Verification Summary"

    echo ""
    local total_checks=$((VALIDATION_PASSED + VALIDATION_FAILED))
    log_info "Total checks: ${total_checks}"
    echo -e "  ${COLOR_GREEN}Passed: ${VALIDATION_PASSED}${COLOR_RESET}"

    if [ $VALIDATION_FAILED -gt 0 ]; then
        echo -e "  ${COLOR_RED}Failed: ${VALIDATION_FAILED}${COLOR_RESET}"
        echo ""
        log_error "Some validations failed"
        exit 1
    else
        echo ""
        log_success "All validations passed! ✓"
        echo ""
        log_info "XCFramework is ready for distribution"
        echo ""
        log_info "Location:"
        echo "  ${XCFRAMEWORK_PATH}"
        echo ""
        log_info "Usage in Podfile:"
        echo "  pod 'WireGuardKit', :path => '/path/to/wireguard-apple'"
        echo ""
        log_info "Or for development:"
        echo "  pod 'WireGuardKit', :git => 'https://github.com/taofu-labs/wireguard-apple.git'"
        exit 0
    fi
}

# Run main function
main "$@"
