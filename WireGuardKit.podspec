Pod::Spec.new do |s|
  # ============================================================================
  # Metadata
  # ============================================================================

  s.name                  = 'WireGuardKit'
  s.version               = '0.0.3'
  s.summary               = 'Production-ready WireGuard implementation for iOS'
  s.description           = <<-DESC
    WireGuardKit provides a complete WireGuard VPN implementation for iOS,
    built from source with vendored static libraries. Supports iOS 12.0+
    and works seamlessly in Network Extension/Packet Tunnel Provider contexts.

    Features:
    - Built from official WireGuard source code
    - Full support for iOS devices and simulators (Intel + Apple Silicon)
    - Application Extension API compatible
    - Zero pre-built binaries (builds from source during pod install)
    - Swift extensions fully accessible in app extension targets (v0.0.3 fix)
  DESC

  s.homepage              = 'https://github.com/taofu-labs/wireguard-apple'
  s.license               = { :type => 'MIT', :file => 'COPYING' }
  s.author                = { 'WireGuard' => 'team@wireguard.com' }
  s.source                = { :git => 'https://github.com/WireGuard/wireguard-apple.git', :tag => s.version.to_s }

  # ============================================================================
  # Platform Requirements
  # ============================================================================

  s.platform              = :ios
  s.ios.deployment_target = '12.0'
  s.swift_version         = '5.7'

  # ============================================================================
  # Build Configuration
  # ============================================================================

  # Prepare command runs before pod install
  # This builds WireGuard Go library from source
  s.prepare_command = <<-CMD
    set -e

    echo ""
    echo "========================================"
    echo "Building WireGuardKit from source"
    echo "========================================"
    echo ""

    # Check prerequisites
    if ! command -v go &> /dev/null; then
      echo "❌ Error: Go is required but not installed"
      echo ""
      echo "Installation options:"
      echo "  Homebrew: brew install go"
      echo "  Direct:   https://golang.org/dl/"
      echo ""
      echo "Minimum required version: Go 1.20+"
      exit 1
    fi

    echo "✓ Go found: $(go version)"
    echo "✓ Xcode found: $(xcodebuild -version | head -n1)"
    echo ""

    # Make build script executable
    chmod +x Scripts/build-wireguard-go.sh Scripts/common.sh

    # Build Go static library
    echo "Building WireGuard Go libraries..."
    ./Scripts/build-wireguard-go.sh

    # Create library directories for CocoaPods
    mkdir -p Libraries/ios-arm64
    mkdir -p Libraries/ios-arm64_x86_64-simulator

    # Copy built libraries to Libraries directory
    if [ -f ".build/libraries/ios-device-arm64/libwg-go.a" ]; then
      cp .build/libraries/ios-device-arm64/libwg-go.a Libraries/ios-arm64/
      echo "✓ Copied arm64 library"
    fi

    if [ -f ".build/libraries/ios-simulator/libwg-go.a" ]; then
      cp .build/libraries/ios-simulator/libwg-go.a Libraries/ios-arm64_x86_64-simulator/
      echo "✓ Copied simulator library"
    fi

    echo ""
    echo "========================================"
    echo "✓ WireGuardKit build completed!"
    echo "========================================"
    echo ""
  CMD

  # ============================================================================
  # Source Files
  # ============================================================================

  # All Swift and C sources compiled together in one module
  s.source_files = [
    'Sources/WireGuardKit/**/*.{swift,h,m}',
    'Sources/Shared/**/*.{swift,h,m,c}',
    'Sources/WireGuardKitC/**/*.{h,c}'
  ]

  s.exclude_files = "Sources/Shared/**/test_*.c"

  # C headers from WireGuardKitC
  s.public_header_files = [
    'Sources/WireGuardKitC/**/*.h',
    'Sources/WireGuardKitGo/wireguard.h',
    'Sources/Shared/Logging/ringlogger.h'
  ]

  # Preserve build scripts, Go sources, and libraries (needed for prepare_command)
  s.preserve_paths = [
    'Scripts/*',
    'Sources/WireGuardKitGo/**/*',
    'Libraries/**/*.a'
  ]

  # ============================================================================
  # Compiler Configuration
  # ============================================================================

  s.pod_target_xcconfig = {
    # Critical: Allow use in app extensions (Network Extension/Packet Tunnel Provider)
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',

    # Enable module support
    'DEFINES_MODULE' => 'YES',

    # Swift include paths for WireGuardKitC
    'SWIFT_INCLUDE_PATHS' => '$(PODS_TARGET_SRCROOT)/Sources/WireGuardKitC',

    # Header search paths
    'HEADER_SEARCH_PATHS' => [
      '$(PODS_TARGET_SRCROOT)/Sources/WireGuardKitC',
      '$(PODS_TARGET_SRCROOT)/Sources/WireGuardKitGo'
    ].join(' '),

    # Disable bitcode (deprecated in Xcode 14+)
    'ENABLE_BITCODE' => 'NO',
  }

  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) $(PODS_ROOT)/WireGuardKit/Libraries/ios-arm64',
    'LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]' => '$(inherited) $(PODS_ROOT)/WireGuardKit/Libraries/ios-arm64_x86_64-simulator',
  }

  # ============================================================================
  # Module Configuration
  # ============================================================================

  s.module_name = 'WireGuardKit'
  s.requires_arc = true

  # ============================================================================
  # Frameworks and Libraries
  # ============================================================================

  s.frameworks = [
    'Foundation',
    'Network',
    'NetworkExtension',
    'SystemConfiguration'
  ]
  s.libraries = 'wg-go'

  # ============================================================================
  # Additional Configuration
  # ============================================================================

  # Resource bundles (if any - currently none needed)
  # s.resource_bundles = {
  #   'WireGuardKit' => ['Sources/WireGuardKit/**/*.{xib,storyboard,xcassets}']
  # }

  # Dependencies (currently none - WireGuard is self-contained)
  # s.dependency 'SomeOtherPod', '~> 1.0'

  # ============================================================================
  # Documentation
  # ============================================================================

  # s.documentation_url = 'https://www.wireguard.com/xplatform/'

end
