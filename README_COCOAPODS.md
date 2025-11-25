# WireGuardKit for iOS - CocoaPods Package

[![Platform](https://img.shields.io/badge/platform-iOS-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.7-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](COPYING)

Production-ready WireGuard implementation for iOS, packaged as a CocoaPods library. Built from source and distributed as an XCFramework with full support for iOS devices and simulators.

## Features

- ✅ **Built from Source**: No pre-built binaries - compiles WireGuard during pod install
- ✅ **XCFramework**: Modern distribution format supporting multiple architectures
- ✅ **Universal Support**: Works on iOS devices (arm64) and simulators (Intel x86_64 + Apple Silicon arm64)
- ✅ **Extension Compatible**: Fully supports Network Extension/Packet Tunnel Provider contexts
- ✅ **iOS 12.0+**: Minimum deployment target iOS 12.0
- ✅ **Production Ready**: Comprehensive error handling, validation, and testing
- ✅ **Developer Friendly**: Clear logging, helpful error messages, excellent documentation

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Architecture](#architecture)
- [Build Process](#build-process)
- [Manual Building](#manual-building)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Requirements

### Runtime Requirements
- iOS 12.0 or later
- Xcode 14.0 or later
- Swift 5.7 or later

### Build-Time Requirements
- **Go 1.20 or later** (required to build WireGuard Go implementation)
- Xcode Command Line Tools
- CocoaPods 1.10 or later

### Installing Go

If you don't have Go installed, you can install it using Homebrew:

```bash
brew install go
```

Or download directly from [golang.org/dl](https://golang.org/dl/)

Verify installation:
```bash
go version
# Should output: go version go1.20+ ...
```

## Installation

### Using CocoaPods (Recommended)

1. Add WireGuardKit to your `Podfile`:

```ruby
# For local development
pod 'WireGuardKit', :path => '../wireguard-apple'

# Or from a Git repository
pod 'WireGuardKit', :git => 'https://github.com/taofu-labs/wireguard-apple.git', :tag => '1.0.0'
```

2. Install the pod:

```bash
pod install
```

**First-time build**: The initial `pod install` will take 60-90 seconds as it builds WireGuard from source. Subsequent installs use the cached build.

3. Open your `.xcworkspace` file and start using WireGuardKit!

### Build Output

During `pod install`, you'll see:

```
Building WireGuard Go libraries...
  ✓ Built ios-device-arm64
  ✓ Built ios-simulator-x86_64
  ✓ Built ios-simulator-arm64
  ✓ Created simulator fat binary
  ✓ Copied libraries to Libraries/
```

## Usage

### Basic Example

```swift
import WireGuardKit
import NetworkExtension

class VPNManager {
    func setupWireGuard() {
        // Create tunnel configuration
        var config = TunnelConfiguration(name: "MyVPN")

        // Configure interface
        let privateKey = PrivateKey()
        config.interface = InterfaceConfiguration(
            privateKey: privateKey,
            addresses: [IPAddressRange(from: "10.0.0.2/24")!],
            dns: [DNSServer(from: "1.1.1.1")!]
        )

        // Configure peer
        let peer = PeerConfiguration(
            publicKey: peerPublicKey,
            endpoint: Endpoint(from: "vpn.example.com:51820")!,
            allowedIPs: [IPAddressRange(from: "0.0.0.0/0")!]
        )
        config.peers = [peer]

        // Start tunnel
        let adapter = WireGuardAdapter(with: tunnelProvider)
        adapter.start(tunnelConfiguration: config) { error in
            if let error = error {
                print("Error starting WireGuard: \(error)")
            } else {
                print("WireGuard started successfully!")
            }
        }
    }
}
```

### Network Extension Setup

For Packet Tunnel Provider extensions, configure your `Info.plist`:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.networkextension.packet-tunnel</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
</dict>
```

And implement your provider:

```swift
import NetworkExtension
import WireGuardKit

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var adapter: WireGuardAdapter!

    override init() {
        super.init()
        adapter = WireGuardAdapter(with: self)
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Load configuration and start WireGuard
        let tunnelConfiguration = // ... load your config
        adapter.start(tunnelConfiguration: tunnelConfiguration, completionHandler: completionHandler)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { error in
            completionHandler()
        }
    }
}
```

## Architecture

### Project Structure

```
wireguard-apple/
├── Scripts/                          # Build automation scripts
│   ├── common.sh                     # Shared utilities and functions
│   ├── build-wireguard-go.sh         # Phase 1: Compile Go implementation
│   ├── build-xcframework.sh          # Phase 2: Create XCFramework
│   └── verify-build.sh               # Phase 3: Validate build
│
├── .build/                           # Intermediate build files (gitignored)
│   ├── goroot/                       # Patched Go runtime for iOS
│   └── libraries/                    # Compiled static libraries
│       ├── ios-device-arm64/
│       ├── ios-simulator-x86_64/
│       ├── ios-simulator-arm64/
│       └── ios-simulator/            # Fat binary (x86_64 + arm64)
│
├── Libraries/                        # CocoaPods library output (gitignored)
│   ├── ios-arm64/                    # Device library
│   └── ios-arm64_x86_64-simulator/   # Simulator library
│
├── Sources/                          # Original WireGuard source code
│   ├── WireGuardKit/                 # Swift implementation
│   ├── WireGuardKitC/                # C wrapper
│   ├── WireGuardKitGo/               # Go implementation + Makefile
│   └── Shared/                       # Shared utilities
│
├── WireGuardKit.podspec              # CocoaPods specification
└── README_COCOAPODS.md               # This file
```

### Build Flow

```
pod install
    ↓
WireGuardKit.podspec prepare_command runs
    ↓
┌─────────────────────────────────────────┐
│ build-wireguard-go.sh                   │
├─────────────────────────────────────────┤
│ 1. Check Go & Xcode prerequisites       │
│ 2. Patch Go runtime for iOS             │
│ 3. Cross-compile for 3 targets:         │
│    - ios-device-arm64                   │
│    - ios-simulator-x86_64               │
│    - ios-simulator-arm64                │
│ 4. Create fat simulator binary          │
│ 5. Copy libraries to Libraries/         │
└─────────────────────────────────────────┘
    ↓
✅ Static libraries ready in Libraries/
    ↓
CocoaPods compiles Swift sources and links against libwg-go.a
```

## Build Process

### Automated Build (via CocoaPods)

The build happens automatically when you run `pod install`. The CocoaPods `prepare_command` executes all three build scripts in sequence.

### Manual Build

For development or debugging, you can build manually:

1. **Clean previous builds** (optional):
   ```bash
   rm -rf .build Artifacts
   ```

2. **Run build scripts**:
   ```bash
   # Phase 1: Build Go libraries
   ./Scripts/build-wireguard-go.sh

   # Phase 2: Create XCFramework
   ./Scripts/build-xcframework.sh

   # Phase 3: Verify build
   ./Scripts/verify-build.sh
   ```

3. **Check output**:
   ```bash
   ls -lh Artifacts/WireGuardKit.xcframework
   ```

### Build Configuration

Key build parameters (defined in `Scripts/common.sh`):

```bash
MIN_IOS_VERSION="12.0"
MIN_GO_VERSION="1.20"
CFLAGS="-fembed-bitcode -Wno-unused-command-line-argument"
GO_LDFLAGS="-w -s"  # Strip debug symbols
GO_TAGS="ios"
```

## Troubleshooting

### Go Not Installed

**Error:**
```
❌ Error: Go is required but not installed
```

**Solution:**
```bash
brew install go
# or download from https://golang.org/dl/
```

### Xcode Command Line Tools Missing

**Error:**
```
❌ Error: Xcode command line tools are required but not installed
```

**Solution:**
```bash
xcode-select --install
```

### Old Go Version

**Error:**
```
❌ Error: Go version 1.19 is too old
Minimum required version: Go 1.20
```

**Solution:**
```bash
brew upgrade go
```

### Build Fails with "SDK not found"

**Error:**
```
❌ Error: SDK 'iphoneos' not found
```

**Solution:**
Ensure Xcode is properly installed and selected:
```bash
sudo xcode-select --switch /Applications/Xcode.app
xcodebuild -showsdks
```

### Architecture Mismatch

**Error:**
```
❌ Error: Binary missing expected architecture: arm64
```

**Solution:**
This usually indicates a build failure. Clean and rebuild:
```bash
rm -rf .build Libraries
./Scripts/build-wireguard-go.sh
```

### "Already Prepared" Warning

**Warning:**
```
⚠️  Go runtime already patched, skipping...
```

**Explanation:**
This is normal. The Go runtime is patched once and reused. To force a clean build:
```bash
rm -rf .build
```

### Build Takes Too Long

**Expected:** First build takes 60-90 seconds. Subsequent builds are cached.

**If it takes longer:**
- Check your internet connection (Go downloads dependencies)
- Check available disk space (needs ~500MB during build)
- Check CPU usage (build is CPU-intensive)

### Module Not Found at Runtime

**Error:**
```
Module 'WireGuardKit' not found
```

**Solution:**
1. Clean build folder: Product → Clean Build Folder (⇧⌘K)
2. Delete DerivedData:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
3. Reinstall pods:
   ```bash
   pod deintegrate && pod install
   ```

### Bitcode Errors (Xcode 14+)

**Error:**
```
Bitcode is no longer supported
```

**Solution:**
Bitcode is automatically disabled in the podspec. If you still see this error, check your app target build settings and set `ENABLE_BITCODE = NO`.

## Advanced Usage

### Customizing Build

You can customize the build by modifying `Scripts/common.sh`:

```bash
# Change minimum iOS version
readonly MIN_IOS_VERSION="13.0"

# Change build flags
readonly CFLAGS="-fembed-bitcode -Wno-unused-command-line-argument -O3"
```

### Debugging Build Issues

Enable verbose logging in build scripts:

```bash
# Add to the top of any script
set -x  # Print commands as they execute
```


## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly (see [Manual Build](#manual-build))
5. Submit a pull request

### Development Workflow

```bash
# 1. Make changes to scripts or code
vim Scripts/build-wireguard-go.sh

# 2. Test with clean build
rm -rf .build Artifacts
./Scripts/build-wireguard-go.sh && \
./Scripts/build-xcframework.sh && \
./Scripts/verify-build.sh

# 3. Test with CocoaPods
cd ../test-app
pod deintegrate && pod install

# 4. Verify in Xcode
open TestApp.xcworkspace
```

## License

This project is licensed under the MIT License. See the [COPYING](COPYING) file for details.

```
Copyright (C) 2024 WireGuard LLC. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```

## Related Projects

- [WireGuard](https://www.wireguard.com/) - Official WireGuard website
- [wireguard-go](https://git.zx2c4.com/wireguard-go/) - Go implementation of WireGuard
- [wireguard-apple](https://git.zx2c4.com/wireguard-apple) - Official WireGuard iOS/macOS app

## Acknowledgments

This CocoaPods package is built on top of the official WireGuard implementation:
- WireGuard by Jason A. Donenfeld and the WireGuard team
- Swift implementation from wireguard-apple repository

## Support

- **Issues**: [GitHub Issues](https://github.com/taofu-labs/wireguard-apple/issues)
- **Documentation**: [WireGuard Docs](https://www.wireguard.com/xplatform/)
- **Community**: [WireGuard Mailing List](https://lists.zx2c4.com/mailman/listinfo/wireguard)

---

**Made with ❤️ for the iOS development community**
