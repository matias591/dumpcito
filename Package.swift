// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Buddy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Dumpcito", targets: ["BuddyApp"])],
    targets: [
        .target(name: "BuddyCore", path: "Sources/BuddyCore"),
        .target(name: "BuddyUI", dependencies: ["BuddyCore"], path: "Sources/BuddyUI"),
        .target(name: "BuddySessions", dependencies: ["BuddyCore"], path: "Sources/BuddySessions"),
        .target(name: "BuddyCalendar", dependencies: ["BuddyCore"], path: "Sources/BuddyCalendar"),
        .target(name: "BuddyCapture", dependencies: ["BuddyCore"], path: "Sources/BuddyCapture"),
        .target(name: "BuddyProgress", dependencies: ["BuddyCore"], path: "Sources/BuddyProgress"),
        .executableTarget(
            name: "BuddyApp",
            dependencies: ["BuddyCore", "BuddyUI", "BuddySessions", "BuddyCalendar", "BuddyCapture", "BuddyProgress"],
            path: "Sources/BuddyApp"
        ),
        // Design review window for every BuddyUI state. Not shipped.
        .executableTarget(name: "BuddyUIGallery", dependencies: ["BuddyCore", "BuddyUI"], path: "Sources/BuddyUIGallery"),
        .testTarget(name: "SessionsTests", dependencies: ["BuddyCore", "BuddySessions"], path: "Tests/SessionsTests"),
        .testTarget(name: "CalendarTests", dependencies: ["BuddyCore", "BuddyCalendar"], path: "Tests/CalendarTests"),
        .testTarget(name: "ProgressTests", dependencies: ["BuddyCore", "BuddyProgress"], path: "Tests/ProgressTests"),
        .testTarget(name: "CaptureTests", dependencies: ["BuddyCore", "BuddyCapture"], path: "Tests/CaptureTests"),
    ],
    swiftLanguageModes: [.v5]
)
