// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HyperMovie",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HyperMovieModels", targets: ["HyperMovieModels"]),
        .library(name: "HyperMovieCore", targets: ["HyperMovieCore"]),
        .library(name: "HyperMovieServices", targets: ["HyperMovieServices"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0")
    ],
    targets: [
        // Models Module (Data structures only)
        .target(
            name: "HyperMovieModels",
            dependencies: [
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "Models",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        
        // Core Module (Protocols and interfaces)
        .target(
            name: "HyperMovieCore",
            dependencies: [
                "HyperMovieModels",
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Core",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        
        // Services Module (Concrete implementations)
        .target(
            name: "HyperMovieServices",
            dependencies: [
                "HyperMovieCore",
                "HyperMovieModels",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            path: "Services",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        
        // Test Targets
        .testTarget(
            name: "HyperMovieModelsTests",
            dependencies: ["HyperMovieModels"],
            path: "Tests/Models"
        ),
        .testTarget(
            name: "HyperMovieCoreTests",
            dependencies: ["HyperMovieCore"],
            path: "Tests/Core"
        ),
        .testTarget(
            name: "HyperMovieServicesTests",
            dependencies: ["HyperMovieServices"],
            path: "Tests/Services"
        )
    ]
) 
