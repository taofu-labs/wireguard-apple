#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2024 WireGuardKit. All Rights Reserved.
#
# common.sh - Shared utilities for WireGuardKit build scripts
#
# This file provides common functions, constants, and utilities used across
# all WireGuardKit build scripts. It includes logging, validation, and
# error handling functionality.

set -euo pipefail

# ============================================================================
# ANSI Color Codes for Terminal Output
# ============================================================================
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# ============================================================================
# Build Configuration Constants
# ============================================================================
readonly MIN_IOS_VERSION="12.0"
readonly MIN_GO_VERSION="1.20"
readonly MIN_XCODE_VERSION="14.0"

# ============================================================================
# Directory Structure Constants
# ============================================================================
# Get the repository root directory (parent of Scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${REPO_ROOT}/.build"
readonly ARTIFACTS_DIR="${REPO_ROOT}/Artifacts"
readonly SOURCES_DIR="${REPO_ROOT}/Sources"

# Build subdirectories
readonly GOROOT_DIR="${BUILD_DIR}/goroot"
readonly LIBRARIES_DIR="${BUILD_DIR}/libraries"
readonly FRAMEWORKS_DIR="${BUILD_DIR}/frameworks"

# Source directories
readonly WIREGUARD_GO_DIR="${SOURCES_DIR}/WireGuardKitGo"
readonly WIREGUARD_KIT_C_DIR="${SOURCES_DIR}/WireGuardKitC"

# ============================================================================
# Build Target Constants
# ============================================================================
# Architecture mappings
readonly GO_ARCH_arm64="arm64"
readonly GO_ARCH_x86_64="amd64"

# Platform mappings
readonly GO_OS_iphoneos="ios"
readonly GO_OS_iphonesimulator="ios"

# Build targets (platform-arch combinations)
readonly TARGET_DEVICE_ARM64="ios-device-arm64"
readonly TARGET_SIMULATOR_X86_64="ios-simulator-x86_64"
readonly TARGET_SIMULATOR_ARM64="ios-simulator-arm64"
readonly TARGET_SIMULATOR_FAT="ios-simulator"

# SDK names
readonly SDK_IPHONEOS="iphoneos"
readonly SDK_IPHONESIMULATOR="iphonesimulator"

# ============================================================================
# Logging Functions
# ============================================================================

# Log an informational message in green
# Usage: log_info "Building WireGuard..."
log_info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*"
}

# Log a warning message in yellow
# Usage: log_warn "Go patches may already be applied"
log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
}

# Log an error message in red
# Usage: log_error "Go is not installed"
log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

# Log a success message with checkmark
# Usage: log_success "Build completed successfully"
log_success() {
    echo -e "${COLOR_GREEN}[INFO] ✓${COLOR_RESET} $*"
}

# Log a step/section header in blue
# Usage: log_section "Phase 1: Building WireGuard Go"
log_section() {
    echo ""
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}$*${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
}

# ============================================================================
# Prerequisite Checking Functions
# ============================================================================

# Check if a command exists in PATH
# Usage: check_command "go" || exit 1
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi
    return 0
}

# Check if Go is installed and meets minimum version
# Exits with error message if requirements not met
check_go_installed() {
    if ! check_command "go"; then
        log_error "Go is required but not installed"
        log_error ""
        log_error "Installation instructions:"
        log_error "  Homebrew: brew install go"
        log_error "  Direct:   https://golang.org/dl/"
        log_error ""
        log_error "Minimum required version: Go ${MIN_GO_VERSION}"
        return 1
    fi

    local go_version
    go_version=$(go version | awk '{print $3}' | sed 's/go//')
    log_info "Found Go ${go_version}"

    # Basic version check (simplified - just check major.minor)
    local major minor
    major=$(echo "$go_version" | cut -d. -f1)
    minor=$(echo "$go_version" | cut -d. -f2)
    local min_major min_minor
    min_major=$(echo "$MIN_GO_VERSION" | cut -d. -f1)
    min_minor=$(echo "$MIN_GO_VERSION" | cut -d. -f2)

    if [ "$major" -lt "$min_major" ] || ([ "$major" -eq "$min_major" ] && [ "$minor" -lt "$min_minor" ]); then
        log_error "Go version ${go_version} is too old"
        log_error "Minimum required version: Go ${MIN_GO_VERSION}"
        return 1
    fi

    return 0
}

# Check if Xcode and command line tools are installed
# Exits with error message if requirements not met
check_xcode_installed() {
    if ! check_command "xcodebuild"; then
        log_error "Xcode command line tools are required but not installed"
        log_error ""
        log_error "Installation instructions:"
        log_error "  xcode-select --install"
        log_error ""
        return 1
    fi

    local xcode_version
    xcode_version=$(xcodebuild -version | head -n1 | awk '{print $2}')
    log_info "Found Xcode ${xcode_version}"

    return 0
}

# Check if xcrun can find the specified SDK
# Usage: check_sdk "iphoneos"
check_sdk() {
    local sdk="$1"
    if ! xcrun --sdk "$sdk" --show-sdk-path &> /dev/null; then
        log_error "SDK '${sdk}' not found"
        log_error "Available SDKs:"
        xcodebuild -showsdks | grep "iOS"
        return 1
    fi
    return 0
}

# Check if lipo command is available (for creating fat binaries)
check_lipo_installed() {
    if ! check_command "lipo"; then
        log_error "lipo command not found (required for creating fat binaries)"
        return 1
    fi
    return 0
}

# ============================================================================
# Architecture and Binary Validation Functions
# ============================================================================

# Get architectures in a binary using lipo
# Usage: get_binary_archs "/path/to/binary"
get_binary_archs() {
    local binary="$1"
    if [ ! -f "$binary" ]; then
        log_error "Binary not found: ${binary}"
        return 1
    fi

    # lipo -info outputs: "Architectures in the fat file: /path/to/file are: x86_64 arm64"
    # or for thin files: "Non-fat file: /path/to/file is architecture: arm64"
    local info
    info=$(lipo -info "$binary" 2>&1)

    if echo "$info" | grep -q "Non-fat file"; then
        echo "$info" | awk '{print $NF}'
    else
        echo "$info" | sed 's/.*are: //'
    fi
}

# Check if a binary contains the expected architecture(s)
# Usage: check_binary_arch "/path/to/binary" "arm64" "x86_64"
check_binary_arch() {
    local binary="$1"
    shift
    local expected_archs=("$@")

    local actual_archs
    actual_archs=$(get_binary_archs "$binary")

    for expected in "${expected_archs[@]}"; do
        if ! echo "$actual_archs" | grep -q "$expected"; then
            log_error "Binary ${binary} missing expected architecture: ${expected}"
            log_error "Found architectures: ${actual_archs}"
            return 1
        fi
    done

    return 0
}

# Check if a binary contains WireGuard symbols
# Usage: check_wireguard_symbols "/path/to/libwg-go.a"
check_wireguard_symbols() {
    local binary="$1"
    if [ ! -f "$binary" ]; then
        log_error "Binary not found: ${binary}"
        return 1
    fi

    # Check for key WireGuard symbols
    # CGO exports symbols with a mangled prefix like __cgoexp_*_wgTurnOn
    local symbol_check
    symbol_check=$(nm "$binary" 2>/dev/null | grep "cgoexp" | grep "wgTurnOn" || true)

    if [ -n "$symbol_check" ]; then
        return 0
    else
        log_error "WireGuard symbols not found in ${binary}"
        log_error "Looking for: cgoexp symbols with wgTurnOn"
        # Debug: show what we found
        log_error "Debug: All symbols containing 'wg':"
        nm "$binary" 2>/dev/null | grep "wg" | head -5 >&2 || true
        return 1
    fi
}

# ============================================================================
# File and Directory Utility Functions
# ============================================================================

# Create directory if it doesn't exist
# Usage: ensure_dir "/path/to/dir"
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_info "Created directory: ${dir}"
    fi
}

# Get human-readable file size
# Usage: get_file_size "/path/to/file"
get_file_size() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "N/A"
        return
    fi

    # Use du for cross-platform compatibility
    du -h "$file" | awk '{print $1}'
}

# Check if a file exists and is not empty
# Usage: check_file_exists "/path/to/file"
check_file_exists() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_error "File not found: ${file}"
        return 1
    fi

    if [ ! -s "$file" ]; then
        log_error "File is empty: ${file}"
        return 1
    fi

    return 0
}

# ============================================================================
# Cleanup Functions
# ============================================================================

# Clean build artifacts
# Usage: clean_build_artifacts
clean_build_artifacts() {
    log_info "Cleaning build artifacts..."

    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        log_success "Removed ${BUILD_DIR}"
    fi

    if [ -d "$ARTIFACTS_DIR" ]; then
        rm -rf "$ARTIFACTS_DIR"
        log_success "Removed ${ARTIFACTS_DIR}"
    fi
}

# Clean only intermediate build files (keep artifacts)
# Usage: clean_intermediate_files
clean_intermediate_files() {
    log_info "Cleaning intermediate build files..."

    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        log_success "Removed ${BUILD_DIR}"
    fi
}

# ============================================================================
# SDK Path Functions
# ============================================================================

# Get SDK path for a given SDK name
# Usage: get_sdk_path "iphoneos"
get_sdk_path() {
    local sdk="$1"
    xcrun --sdk "$sdk" --show-sdk-path
}

# ============================================================================
# Export Functions for Use in Other Scripts
# ============================================================================

# Export all constants and functions so they're available in sourcing scripts
export -f log_info log_warn log_error log_success log_section
export -f check_command check_go_installed check_xcode_installed check_sdk check_lipo_installed
export -f get_binary_archs check_binary_arch check_wireguard_symbols
export -f ensure_dir get_file_size check_file_exists
export -f clean_build_artifacts clean_intermediate_files
export -f get_sdk_path

# ============================================================================
# Initialization Message
# ============================================================================

# Only show this if script is run directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    log_info "WireGuardKit Common Utilities"
    log_info "This script should be sourced, not executed directly"
    log_info ""
    log_info "Usage: source Scripts/common.sh"
    exit 1
fi
