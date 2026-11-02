import Foundation

enum TestPaths {
    /// Repository root derived from this test file:
    /// <root>/Packages/TapeekCore/Tests/TapeekCoreTests/TestPaths.swift
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TapeekCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TapeekCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root

    static let samples = repositoryRoot.appendingPathComponent("Samples", isDirectory: true)
    static let markdown = samples.appendingPathComponent("markdown", isDirectory: true)
    static let zip = samples.appendingPathComponent("zip", isDirectory: true)
    static let buildFixtures = repositoryRoot.appendingPathComponent(".build/fixtures", isDirectory: true)
    static let largeManifest = buildFixtures.appendingPathComponent("manifest.json")
}
