// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OPCCompany",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OPCCompany", targets: ["OPCCompany"]),
        .executable(name: "opc", targets: ["OPC"]),
        // M3: the portable core + C-ABI bridge as a dynamic library for
        // non-Swift hosts (Flutter/dart:ffi via OPCBridge). Purely additive
        // — macOS CI still builds/test the same way; `swift build` here
        // produces the dylib so the bridge can never rot unnoticed.
        .library(name: "OPCCompanyBridge", type: .dynamic, targets: ["OPCCompanyCore"])
    ],
    dependencies: [
        // Windows port (RFC: docs/WINDOWS_PORT_RFC.md): swift-crypto replaces
        // CryptoKit there. Conditional so the macOS build graph is unchanged.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        // Vendored SQLite amalgamation (public domain, see
        // Sources/CSQLite/VENDORED.txt). Only reachable on Windows: the
        // system `SQLite3` module does not exist there, so the logic files
        // fall back to this C target (per-file #if canImport(SQLite3)).
        // macOS/iOS keep the OS libsqlite3 and never build this target
        // (conditional dependency below keeps macOS CI time unchanged).
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            publicHeadersPath: "include"
        ),
        // Header shim exposing DPAPI (CryptProtectData/CryptUnprotectData)
        // to Swift on Windows; the platform's crypt32 is linked below.
        // macOS never builds it (#if canImport(CWinDPAPI) guards the call
        // sites, Windows-only conditional dependency below keeps the macOS
        // graph untouched).
        .target(
            name: "CWinDPAPI",
            path: "Sources/CWinDPAPI",
            publicHeadersPath: "include"
        ),
        .target(
            name: "OPCCompanyCore",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.windows])),
                .target(name: "CWinDPAPI", condition: .when(platforms: [.windows])),
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.windows]))
            ],
            path: "Sources/OPCCompanyCore",
            linkerSettings: [
                // Apple: the OS ships libsqlite3. Windows: the vendored CSQLite
                // target compiles the amalgamation into the build itself — a
                // `-lsqlite3` there would look for a non-existent sqlite3.lib
                // (new windows.yml CI caught this; the spike package builds a
                // separate manifest so it never saw it).
                .linkedLibrary("sqlite3", .when(platforms: [.macOS, .iOS, .tvOS, .watchOS])),
                .linkedLibrary("crypt32", .when(platforms: [.windows]))
            ]
        ),
        .executableTarget(
            name: "OPCCompany",
            dependencies: ["OPCCompanyCore"],
            path: "Sources/OPCCompany"
        ),
        .executableTarget(
            name: "OPC",
            dependencies: ["OPCCompanyCore"],
            path: "Sources/OPC"
        ),
        .testTarget(
            name: "OPCCompanyTests",
            dependencies: ["OPCCompanyCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
