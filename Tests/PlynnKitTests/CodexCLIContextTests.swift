import XCTest
@testable import PlynnKit

final class CodexCLIContextTests: XCTestCase {
    func testReadsFreshWorkspaceMarker() throws {
        let (root, workspace) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("codex-workspace")
        try workspace.path.write(to: marker, atomically: true, encoding: .utf8)

        let context = CodexCLIContextReader.read(path: marker, now: .now, maxAge: 60)

        XCTAssertEqual(context?.workspaceRoot, workspace.standardizedFileURL.path)
    }

    func testIgnoresStaleWorkspaceMarker() throws {
        let (root, workspace) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("codex-workspace")
        try workspace.path.write(to: marker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: marker.path)

        XCTAssertNil(CodexCLIContextReader.read(path: marker, now: .now, maxAge: 60))
    }

    func testIndexesUniqueFilenamesAndSkipsBuildDirectories() throws {
        let (root, workspace) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = workspace.appendingPathComponent("Sources", isDirectory: true)
        let testsDirectory = workspace.appendingPathComponent("Tests", isDirectory: true)
        let ignoredDirectory = workspace.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try Data().write(to: sourceDirectory.appendingPathComponent("Package.swift"))
        try Data().write(to: sourceDirectory.appendingPathComponent("main.swift"))
        try Data().write(to: testsDirectory.appendingPathComponent("main.swift"))
        try Data().write(to: ignoredDirectory.appendingPathComponent("ignored.ts"))

        let candidates = WorkspaceFileIndex.candidates(at: workspace.path)

        XCTAssertTrue(candidates.contains("Package.swift"))
        XCTAssertFalse(candidates.contains("main.swift"))
        XCTAssertFalse(candidates.contains("ignored.ts"))
    }

    private func makeWorkspace() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plynn-codex-context-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return (root, workspace)
    }
}
