//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import Zipcode
@testable import Konfer

/// Installing a Pianissimo release archive: the checksum gate, unpacking into
/// place, and what is left behind when either fails.
///
/// The archives here are a few bytes of stand-in files with the real layout;
/// the release itself is 630 MB, and `PipelineIntegrationTests` with
/// `KONFER_BACKEND=pianissimo-sv` exercises it.
struct PianissimoModelStoreTests {

    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PianissimoModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private var destination: URL { folder.appendingPathComponent("pianissimo-sv-120s") }

    /// A zip holding one small file per component, plus `extra` entries.
    private func archive(extra: [String: String] = [:]) throws -> URL {
        let url = folder.appendingPathComponent("release.zip")
        var entries = Dictionary(uniqueKeysWithValues: PianissimoModelStore.components.map { component in
            (component.hasSuffix(".mlmodelc") ? "\(component)/model.mil" : component, component)
        })
        entries.merge(extra) { _, new in new }
        try ZipArchive(path: url.path).write(type: .overwrite) { writer in
            for (name, contents) in entries.sorted(by: { $0.key < $1.key }) {
                try writer.writeEntryNamed(name, data: Data(contents.utf8))
            }
        }
        return url
    }

    private func contents(_ path: String) throws -> String {
        try String(contentsOf: destination.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("A release whose checksum matches is unpacked into the model folder")
    func installsMatchingArchive() throws {
        let zip = try archive()
        try PianissimoModelStore.install(
            archive: zip, sha256: PianissimoModelStore.sha256(of: zip), into: destination
        )
        #expect(PianissimoModelStore.isInstalled(at: destination))
        #expect(try contents("Encoder.mlmodelc/model.mil") == "Encoder.mlmodelc")
        #expect(try contents("parakeet_vocab.json") == "parakeet_vocab.json")
    }

    @Test("A release whose checksum doesn't match is refused, and nothing is installed")
    func refusesMismatchedArchive() throws {
        let zip = try archive()
        #expect(throws: PipelineError.self) {
            try PianissimoModelStore.install(archive: zip, sha256: String(repeating: "0", count: 64), into: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("A refused release leaves the previous install exactly as it was")
    func keepsPreviousInstallOnFailure() throws {
        let good = try archive()
        try PianissimoModelStore.install(archive: good, sha256: PianissimoModelStore.sha256(of: good), into: destination)

        let bad = try archive(extra: ["../escaped.txt": "outside"])
        #expect(throws: PipelineError.self) {
            try PianissimoModelStore.install(archive: bad, sha256: PianissimoModelStore.sha256(of: bad), into: destination)
        }
        #expect(PianissimoModelStore.isInstalled(at: destination))
        #expect(try contents("Encoder.mlmodelc/model.mil") == "Encoder.mlmodelc")
    }

    @Test("An entry that climbs out of the model folder is refused before it is written")
    func refusesEscapingEntry() throws {
        let zip = try archive(extra: ["../escaped.txt": "outside"])
        #expect(throws: PipelineError.self) {
            try PianissimoModelStore.install(archive: zip, sha256: PianissimoModelStore.sha256(of: zip), into: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("escaped.txt").path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("An archive missing a component is refused rather than half-installed")
    func refusesIncompleteArchive() throws {
        let url = folder.appendingPathComponent("partial.zip")
        try ZipArchive(path: url.path).write(type: .overwrite) { writer in
            try writer.writeEntryNamed("Encoder.mlmodelc/model.mil", data: Data("Encoder".utf8))
        }
        #expect(throws: PipelineError.self) {
            try PianissimoModelStore.install(archive: url, sha256: PianissimoModelStore.sha256(of: url), into: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("Nothing is left beside the model folder after an install, failed or not")
    func leavesNoStagingBehind() throws {
        let good = try archive()
        try PianissimoModelStore.install(archive: good, sha256: PianissimoModelStore.sha256(of: good), into: destination)
        let bad = try archive(extra: ["../escaped.txt": "outside"])
        _ = try? PianissimoModelStore.install(archive: bad, sha256: PianissimoModelStore.sha256(of: bad), into: destination)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(".pianissimo-sv-120s-") }
        #expect(leftovers.isEmpty)
    }
}
