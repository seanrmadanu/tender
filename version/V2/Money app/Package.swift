// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TenderCore", platforms: [.macOS(.v14)], products: [.library(name: "TenderCore", targets: ["TenderCore"])], targets: [.target(name: "TenderCore", path: "Tender/Core"), .testTarget(name: "TenderCoreTests", dependencies: ["TenderCore"], path: "Tests")])
