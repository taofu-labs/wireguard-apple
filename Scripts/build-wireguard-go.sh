#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2024 WireGuardKit. All Rights Reserved.
#
# build-wireguard-go.sh - Phase 1: Build WireGuard Go Implementation
#
# This script cross-compiles the WireGuard Go implementation for iOS targets:
#   - ios-device-arm64: Physical devices (iPhone/iPad)
#   - ios-simulator-x86_64: Intel Mac simulators
#   - ios-simulator-arm64: Apple Silicon Mac simulators
#
# The script also creates a patched Go runtime for iOS and generates a fat
# binary for simulators (x86_64 + arm64).
#
# Output:
#   .build/libraries/ios-device-arm64/libwg-go.a
#   .build/libraries/ios-simulator/libwg-go.a (fat binary)

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Configuration
# ============================================================================

# Compiler flags for iOS
readonly CFLAGS="-fembed-bitcode -Wno-unused-command-line-argument"

# Go build configuration
readonly GO_BUILD_MODE="c-archive"
readonly GO_LDFLAGS="-w -s"  # Strip debug symbols
readonly GO_TAGS="ios"

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
    log_section "Checking Prerequisites"

    # Check Go installation
    if ! check_go_installed; then
        exit 1
    fi

    # Check Xcode installation
    if ! check_xcode_installed; then
        exit 1
    fi

    # Check required SDKs
    if ! check_sdk "$SDK_IPHONEOS"; then
        exit 1
    fi

    if ! check_sdk "$SDK_IPHONESIMULATOR"; then
        exit 1
    fi

    # Check lipo command
    if ! check_lipo_installed; then
        exit 1
    fi

    # Check if WireGuardKitGo directory exists
    if [ ! -d "$WIREGUARD_GO_DIR" ]; then
        log_error "WireGuardKitGo directory not found: ${WIREGUARD_GO_DIR}"
        exit 1
    fi

    # Check if go.mod exists
    if [ ! -f "${WIREGUARD_GO_DIR}/go.mod" ]; then
        log_error "go.mod not found in ${WIREGUARD_GO_DIR}"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# ============================================================================
# Go Runtime Patching
# ============================================================================

# Create a patched Go runtime for iOS cross-compilation
# This applies iOS-specific patches to the Go runtime to support proper
# time handling on mobile devices (using continuous time instead of absolute time)
patch_go_runtime() {
    log_section "Preparing Go Runtime for iOS"

    local real_goroot
    real_goroot=$(go env GOROOT 2>/dev/null)

    if [ -z "$real_goroot" ]; then
        log_error "Could not determine GOROOT"
        exit 1
    fi

    log_info "Using system Go runtime: ${real_goroot}"

    # Create patched GOROOT directory
    ensure_dir "$GOROOT_DIR"

    # Check if already patched
    if [ -f "${GOROOT_DIR}/.prepared" ]; then
        log_warn "Go runtime already patched, skipping..."
        return 0
    fi

    log_info "Copying Go runtime to build directory..."
    # Copy Go runtime, excluding build cache
    rsync -a --delete --exclude='pkg/obj/go-build' "${real_goroot}/" "${GOROOT_DIR}/"

    # Apply iOS patches
    log_info "Applying iOS patches to Go runtime..."

    local patch_count=0
    for patch_file in "${WIREGUARD_GO_DIR}"/goruntime-*.diff; do
        if [ -f "$patch_file" ]; then
            log_info "Applying patch: $(basename "$patch_file")"

            # Apply patch, ignoring errors for already-applied patches
            if patch -p1 -f -N -r- -d "${GOROOT_DIR}" < "$patch_file" 2>&1 | grep -v "Reversed (or previously applied) patch detected"; then
                ((patch_count++)) || true
            else
                log_warn "Patch may have already been applied: $(basename "$patch_file")"
            fi
        fi
    done

    if [ $patch_count -eq 0 ]; then
        log_warn "No patches were applied"
    else
        log_success "Applied ${patch_count} patch(es)"
    fi

    # Mark as prepared
    touch "${GOROOT_DIR}/.prepared"
    log_success "Go runtime prepared for iOS"
}

# ============================================================================
# Cross-Compilation Functions
# ============================================================================

# Build WireGuard Go for a specific target
# Usage: build_target <target-name> <sdk> <arch> <go-arch> <go-os>
build_target() {
    local target_name="$1"
    local sdk="$2"
    local arch="$3"
    local go_arch="$4"
    local go_os="$5"

    log_info "Building for ${target_name} (${arch} on ${sdk})..."

    # Create output directory
    local output_dir="${LIBRARIES_DIR}/${target_name}"
    ensure_dir "$output_dir"

    local output_file="${output_dir}/libwg-go.a"

    # Get SDK path and version
    local sdk_path
    sdk_path=$(get_sdk_path "$sdk")

    local deployment_target_flag=""
    if [ "$sdk" = "$SDK_IPHONEOS" ]; then
        deployment_target_flag="-miphoneos-version-min=${MIN_IOS_VERSION}"
    else
        deployment_target_flag="-mios-simulator-version-min=${MIN_IOS_VERSION}"
    fi

    # Set up environment for cross-compilation
    local arch_cflags="${CFLAGS} ${deployment_target_flag} -isysroot ${sdk_path} -arch ${arch}"

    # Build with Go
    (
        cd "$WIREGUARD_GO_DIR"

        # Export CGO and Go environment variables
        export GOROOT="${GOROOT_DIR}"
        export CGO_ENABLED=1
        export CGO_CFLAGS="${arch_cflags}"
        export CGO_LDFLAGS="${arch_cflags}"
        export GOOS="${go_os}"
        export GOARCH="${go_arch}"
        export CC="clang"

        # Run go build
        go build \
            -ldflags="${GO_LDFLAGS}" \
            -trimpath \
            -v \
            -tags="${GO_TAGS}" \
            -buildmode="${GO_BUILD_MODE}" \
            -o "$output_file"
    )

    # Remove the .h file generated by go build (we have our own header)
    local header_file="${output_dir}/libwg-go.h"
    if [ -f "$header_file" ]; then
        rm -f "$header_file"
    fi

    # Validate the build
    if ! check_file_exists "$output_file"; then
        log_error "Failed to build ${target_name}"
        exit 1
    fi

    # Verify architecture
    if ! check_binary_arch "$output_file" "$arch"; then
        log_error "Architecture mismatch for ${target_name}"
        exit 1
    fi

    # Verify WireGuard symbols
    if ! check_wireguard_symbols "$output_file"; then
        log_error "WireGuard symbols not found in ${target_name}"
        exit 1
    fi

    local file_size
    file_size=$(get_file_size "$output_file")
    log_success "Built ${target_name}: ${file_size}"
}

# Create fat binary for iOS Simulator (x86_64 + arm64)
create_simulator_fat_binary() {
    log_section "Creating Simulator Fat Binary"

    local x86_64_lib="${LIBRARIES_DIR}/${TARGET_SIMULATOR_X86_64}/libwg-go.a"
    local arm64_lib="${LIBRARIES_DIR}/${TARGET_SIMULATOR_ARM64}/libwg-go.a"
    local output_dir="${LIBRARIES_DIR}/${TARGET_SIMULATOR_FAT}"
    local output_file="${output_dir}/libwg-go.a"

    # Verify input files exist
    if ! check_file_exists "$x86_64_lib"; then
        log_error "Simulator x86_64 library not found"
        exit 1
    fi

    if ! check_file_exists "$arm64_lib"; then
        log_error "Simulator arm64 library not found"
        exit 1
    fi

    # Create output directory
    ensure_dir "$output_dir"

    # Create fat binary using lipo
    log_info "Combining x86_64 and arm64 into fat binary..."
    lipo -create -output "$output_file" "$x86_64_lib" "$arm64_lib"

    # Verify the fat binary
    if ! check_file_exists "$output_file"; then
        log_error "Failed to create simulator fat binary"
        exit 1
    fi

    # Verify both architectures are present
    if ! check_binary_arch "$output_file" "x86_64" "arm64"; then
        log_error "Simulator fat binary missing required architectures"
        exit 1
    fi

    local file_size
    file_size=$(get_file_size "$output_file")
    log_success "Created simulator fat binary: ${file_size}"
}

# ============================================================================
# Main Build Flow
# ============================================================================

main() {
    log_section "WireGuard Go Build - Phase 1"

    # Step 1: Check prerequisites
    check_prerequisites

    # Step 2: Prepare patched Go runtime
    patch_go_runtime

    # Step 3: Build for all targets
    log_section "Cross-Compiling WireGuard Go"

    # Build for iOS device (arm64)
    build_target \
        "$TARGET_DEVICE_ARM64" \
        "$SDK_IPHONEOS" \
        "arm64" \
        "$GO_ARCH_arm64" \
        "$GO_OS_iphoneos"

    # Build for iOS simulator (x86_64 - Intel Macs)
    build_target \
        "$TARGET_SIMULATOR_X86_64" \
        "$SDK_IPHONESIMULATOR" \
        "x86_64" \
        "$GO_ARCH_x86_64" \
        "$GO_OS_iphonesimulator"

    # Build for iOS simulator (arm64 - Apple Silicon Macs)
    build_target \
        "$TARGET_SIMULATOR_ARM64" \
        "$SDK_IPHONESIMULATOR" \
        "arm64" \
        "$GO_ARCH_arm64" \
        "$GO_OS_iphonesimulator"

    # Step 4: Create simulator fat binary
    create_simulator_fat_binary

    # Step 5: Summary
    log_section "Build Summary"
    log_success "WireGuard Go libraries built successfully"
    echo ""
    log_info "Output files:"
    log_info "  Device (arm64):      ${LIBRARIES_DIR}/${TARGET_DEVICE_ARM64}/libwg-go.a"
    log_info "  Simulator (fat):     ${LIBRARIES_DIR}/${TARGET_SIMULATOR_FAT}/libwg-go.a"
    echo ""
}

# Run main function
main "$@"
