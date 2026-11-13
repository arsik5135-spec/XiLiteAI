// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XiLiteTerminalRuntime",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "XiLiteTerminalRuntime", targets: ["ios_system", "awk", "curl_ios", "files", "libssh2", "network_ios", "openssl", "python3_ios", "shell", "ssh_cmd", "tar", "text"])
    ],
    targets: [
        .binaryTarget(
            name: "ios_system",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/ios_system.xcframework.zip",
            checksum: "d2deb9f77dff839e069f21efdb11f16864a8173e33956cd1b4d174a76f1b0e99"
        ),
        .binaryTarget(
            name: "awk",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/awk.xcframework.zip",
            checksum: "560f786c77d487a482de7fcd1caa4736a95979783483685d53a8503a7514e53f"
        ),
        .binaryTarget(
            name: "curl_ios",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/curl_ios.xcframework.zip",
            checksum: "62b153f4536987f9fd50852b29400dd083f07fb7e3155a44e8d181a25a44dcf4"
        ),
        .binaryTarget(
            name: "files",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/files.xcframework.zip",
            checksum: "4e36aeb7242592a848a7ee3b74109dc45f63e16fa9fa4d07bc80026ec30897e3"
        ),
        .binaryTarget(
            name: "libssh2",
            url: "https://github.com/holzschu/libssh2-apple/releases/download/v1.11.0/libssh2-dynamic.xcframework.zip",
            checksum: "cacfe1789b197b727119f7e32f561eaf9acc27bf38cd19975b74fce107f868a6"
        ),
        .binaryTarget(
            name: "network_ios",
            url: "https://github.com/holzschu/network_ios/releases/download/v0.2/network_ios.xcframework.zip",
            checksum: "18e96112ae86ec39390487d850e7732d88e446f9f233b2792d633933d4606d46"
        ),
        .binaryTarget(
            name: "openssl",
            url: "https://github.com/holzschu/openssl-apple/releases/download/v1.1.1w/openssl-dynamic.xcframework.zip",
            checksum: "329e8317cf9bee8e138da5d032330a7a1bd2473cf44c9c083cb2f0636abb8b80"
        ),
        .binaryTarget(
            name: "python3_ios",
            path: "Frameworks/python3_ios.xcframework"
        ),
        .binaryTarget(
            name: "shell",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/shell.xcframework.zip",
            checksum: "bdace8281617602f1f0da7c90d933388085e31de9f31964467671f212966f76a"
        ),
        .binaryTarget(
            name: "ssh_cmd",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/ssh_cmd.xcframework.zip",
            checksum: "fbc3ed1e2e0b62e9631f660b42a8739aee90b2643812987bb2e66c10032825fb"
        ),
        .binaryTarget(
            name: "tar",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/tar.xcframework.zip",
            checksum: "a44176ba8a016630fcf75dc9e2a961a17b5433196fff19d0a270a8b23d550f93"
        ),
        .binaryTarget(
            name: "text",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.6/text.xcframework.zip",
            checksum: "93ed6410a972b3dd9dfa2ff93e4260f2b5401168c52c78ae1bb08f16d6b74533"
        )
    ]
)
