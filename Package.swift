// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Prompter",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic: script model, phrase parsing, pacing, speech-to-script matching,
        // delivery review. No AppKit/SwiftUI so it stays fast to test.
        .target(
            name: "PrompterCore",
            path: "Sources/PrompterCore"
        ),
        // The macOS app: windows, menu bar, speech capture, persistence, UI.
        .executableTarget(
            name: "Prompter",
            dependencies: ["PrompterCore"],
            path: "Sources/Prompter"
        ),
        // Dev tool for inspecting phrase parsing and pacing from the terminal.
        .executableTarget(
            name: "prompter-cli",
            dependencies: ["PrompterCore"],
            path: "Sources/PrompterCLI"
        ),
        .testTarget(
            name: "PrompterCoreTests",
            dependencies: ["PrompterCore"],
            path: "Tests/PrompterCoreTests"
        ),
    ]
)
