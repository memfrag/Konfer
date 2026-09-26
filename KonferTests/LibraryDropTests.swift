//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Konfer

/// What a drop becomes depends on the order of `LibraryDrop`'s
/// representations, and getting it wrong fails quietly: a recording dragged
/// from Finder would be copied instead of transcribed where it is. These hand
/// it each kind of drag as an item provider, the way a drop arrives.
struct LibraryDropTests {

    /// A drop as the app receives it. The provider only offers a callback
    /// here, with no async form.
    private func load(_ provider: NSItemProvider) async throws -> LibraryDrop {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: LibraryDrop.self) { continuation.resume(with: $0) }
        }
    }

    private func audioFile(named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data("not really audio".utf8).write(to: url)
        return url
    }

    @Test("A file from Finder is taken where it is, never copied")
    func finderFilesAreNotCopied() async throws {
        let recording = try audioFile(named: "Standup.m4a")
        let provider = try #require(NSItemProvider(contentsOf: recording))

        let drop = try await load(provider)

        guard case .file(let url) = drop else {
            Issue.record("Expected the file itself, got \(drop)")
            return
        }
        #expect(url.standardizedFileURL == recording.standardizedFileURL)
    }

    @Test("Audio offered only as a file to copy — a Voice Memo — is copied, named after the memo")
    func promisedAudioIsCopied() async throws {
        let memo = try audioFile(named: "Kickoff with Anna.m4a")
        let provider = NSItemProvider()
        provider.suggestedName = "Kickoff with Anna"
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.mpeg4Audio.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(memo, false, nil)
            return nil
        }

        let drop = try await load(provider)

        guard case .copy(let staged) = drop else {
            Issue.record("Expected a copy, got \(drop)")
            return
        }
        #expect(staged.standardizedFileURL != memo.standardizedFileURL)
        #expect(try Data(contentsOf: staged) == Data(contentsOf: memo))
        // Named after the memo. The extension is the system's, taken from the
        // type the sender declared, so the test asks only that it names
        // something Konfer can transcribe.
        #expect(staged.deletingPathExtension().lastPathComponent == "Kickoff with Anna")
        #expect(UTType(filenameExtension: staged.pathExtension)?.conforms(to: .audiovisualContent) == true)
    }

    @Test("A meeting dragged within the sidebar stays a meeting")
    func sidebarItemsStayItems() async throws {
        let id = UUID()
        let provider = NSItemProvider()
        provider.register(SidebarItem.meeting(id))

        let drop = try await load(provider)

        guard case .item(.meeting(let dropped)) = drop else {
            Issue.record("Expected the meeting, got \(drop)")
            return
        }
        #expect(dropped == id)
    }
}
