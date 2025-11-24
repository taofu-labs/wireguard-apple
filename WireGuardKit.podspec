Pod::Spec.new do |s|
  # ============================================================================
  # Metadata
  # ============================================================================

  s.name                  = 'WireGuardKit'
  s.version               = '0.0.2'
  s.summary               = 'Production-ready WireGuard implementation for iOS'
  s.description           = <<-DESC
    WireGuardKit provides a complete WireGuard VPN implementation for iOS,
    built from source and packaged as an XCFramework. Supports iOS 12.0+
    and works seamlessly in Network Extension/Packet Tunnel Provider contexts.

    Features:
    - Built from official WireGuard source code
    - Full support for iOS devices and simulators (Intel + Apple Silicon)
    - Application Extension API compatible
    - Zero pre-built binaries (builds from source during pod install)
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
  # This builds WireGuard from source and creates the XCFramework
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

    # Make scripts executable
    chmod +x Scripts/*.sh

    # Run build phases
    echo "Phase 1/3: Building WireGuard Go libraries..."
    ./Scripts/build-wireguard-go.sh

    echo ""
    echo "Phase 2/3: Creating XCFramework..."
    ./Scripts/build-xcframework.sh

    echo ""
    echo "Phase 3/3: Verifying build..."
    ./Scripts/verify-build.sh

    echo ""
    echo "========================================"
    echo "✓ WireGuardKit build completed!"
    echo "========================================"
    echo ""
    echo "Build time: Approximately 60-90 seconds"
    echo "Note: This only runs once. Subsequent pod installs use cached build."
    echo ""
  CMD

  # ============================================================================
  # Source Files
  # ============================================================================

  # XCFramework (built by prepare_command)
  s.vendored_frameworks = 'Artifacts/WireGuardKit.xcframework'

  # Swift sources from WireGuardKit
  s.source_files = [
    'Sources/WireGuardKit/**/*.swift',
    'Sources/Shared/**/*.{swift,h,m,c}',
  ]

  s.exclude_files = "Sources/Shared/**/test_*.c"

  # C headers from WireGuardKitC
  s.public_header_files = [
    'Sources/WireGuardKitC/**/*.h',
    'Sources/WireGuardKitGo/wireguard.h'
  ]

  # Preserve build scripts and Go sources (needed for prepare_command)
  s.preserve_paths = [
    'Scripts/*',
    'Sources/WireGuardKitGo/**/*'
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

  # ============================================================================
  # Module Configuration
  # ============================================================================

  s.module_name = 'WireGuardKit'
  s.requires_arc = true

  # ============================================================================
  # Subspecs (optional, for more granular control)
  # ============================================================================

  # Main subspec includes everything
  s.subspec 'Core' do |core|
    core.source_files = 'Sources/WireGuardKit/**/*.swift'
    core.vendored_frameworks = 'Artifacts/WireGuardKit.xcframework'
  end

  # Shared utilities subspec
  s.subspec 'Shared' do |shared|
    shared.source_files = 'Sources/Shared/**/*.{swift,h,m,c}'
    shared.exclude_files = 'Sources/Shared/**/test_*.c'
  end

  # C interface subspec
  s.subspec 'C' do |c|
    c.source_files = 'Sources/WireGuardKitC/**/*.{h,c}'
    c.public_header_files = 'Sources/WireGuardKitC/**/*.h'
  end

  # ============================================================================
  # Frameworks and Libraries
  # ============================================================================

  s.frameworks = [
    'Foundation',
    'Network',
    'NetworkExtension',
    'SystemConfiguration'
  ]

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
