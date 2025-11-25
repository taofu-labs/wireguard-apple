# [WireGuard](https://www.wireguard.com/) for iOS and macOS

This project contains an application for iOS and for macOS, as well as many components shared between the two of them. You may toggle between the two platforms by selecting the target from within Xcode.

## Building

- Clone this repo:

```
$ git clone https://git.zx2c4.com/wireguard-apple
$ cd wireguard-apple
```

- Rename and populate developer team ID file:

```
$ cp Sources/WireGuardApp/Config/Developer.xcconfig.template Sources/WireGuardApp/Config/Developer.xcconfig
$ vim Sources/WireGuardApp/Config/Developer.xcconfig
```

- Install swiftlint and go 1.19:

```
$ brew install swiftlint go
```

- Open project in Xcode:

```
$ open WireGuard.xcodeproj
```

- Flip switches, press buttons, and make whirling noises until Xcode builds it.

## WireGuardKit integration

WireGuardKit is distributed via CocoaPods for easy integration into your iOS VPN application.

### Installation

Add WireGuardKit to your `Podfile`:

```ruby
# For local development
pod 'WireGuardKit', :path => '../wireguard-apple'

# Or from a Git repository
pod 'WireGuardKit', :git => 'https://github.com/taofu-labs/wireguard-apple.git', :tag => '0.0.3'
```

Then install:

```bash
pod install
```

**Note:** First installation takes 60-90 seconds to build WireGuard from source. Requires Go 1.20+ installed.

### Usage

```swift
import NetworkExtension
import WireGuardKit

class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var adapter: WireGuardAdapter = {
        return WireGuardAdapter(with: self) { logLevel, message in
            // Your logging
        }
    }()

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let config = try! TunnelConfiguration(fromWgQuickConfig: configString, called: "MyVPN")
        adapter.start(tunnelConfiguration: config, completionHandler: completionHandler)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { _ in completionHandler() }
    }
}
```

See [README_COCOAPODS.md](README_COCOAPODS.md) for detailed integration guide.

## MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
