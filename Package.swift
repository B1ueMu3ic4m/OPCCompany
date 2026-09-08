// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OPCCompany",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OPCCompany", targets: ["OPCCompany"])
    ],
    dependencies: [
        // Windows port (RFC: docs/WINDOWS_PORT_RFC.md): swift-crypto replaces
        // CryptoKit there. Conditional so the macOS build graph is unchanged.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "OPCCompanyCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.windows]))
            ],
            path: "Sources/OPCCompanyCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "OPCCompany",
            dependencies: ["OPCCompanyCore"],
            path: "Sources/OPCCompany"
        ),
        .testTarget(
            name: "OPCCompanyTests",
            dependencies: ["OPCCompanyCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
