// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DropConvert",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DropConvert",
            path: "Sources",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
