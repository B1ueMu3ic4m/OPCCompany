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
    targets: [
        .target(
            name: "OPCCompanyCore",
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
