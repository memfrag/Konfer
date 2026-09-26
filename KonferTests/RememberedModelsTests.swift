//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
@testable import Konfer

/// The Transcribe sheet opens on the model last used for a language. What it
/// remembers is kept as a string in user defaults, so it has to survive being
/// written and read back — and never hand a language a model it can't use.
struct RememberedModelsTests {

    @Test("With nothing remembered, a language starts on its default")
    func startsOnTheDefault() {
        let memory = RememberedModels("")

        #expect(memory.model(for: .english) == .appleSpeech)
        #expect(memory.model(for: .swedish) == .kbWhisperLarge)
    }

    @Test("The model last used for English is the one it starts on next time, across a save")
    func remembersAcrossASave() {
        var memory = RememberedModels("")
        memory.remember(.whisperLargeV3, for: .english)

        #expect(RememberedModels(memory.stored).model(for: .english) == .whisperLargeV3)
    }

    @Test("A model a language doesn't offer is never remembered for it")
    func refusesModelsTheLanguageLacks() {
        var memory = RememberedModels("")
        memory.remember(.roestWhisper, for: .dutch)

        #expect(memory.model(for: .dutch) == .whisperLargeV3)
        #expect(memory.stored.isEmpty)
    }

    @Test("Anything unreadable in what was saved is ignored, not trusted")
    func ignoresWhatItCantRead() {
        let memory = RememberedModels("english=whisper-large-v3;klingon=roest-whisper;dutch=roest-whisper;garbage")

        #expect(memory.model(for: .english) == .whisperLargeV3)
        #expect(memory.model(for: .dutch) == .whisperLargeV3)
        #expect(memory.stored == "english=whisper-large-v3")
    }

    @Test("Røst remembered for Danish by 1.4 is forgotten, and Danish starts on large-v3")
    func forgetsRoest() {
        let memory = RememberedModels("danish=roest-whisper")

        #expect(memory.model(for: .danish) == .whisperLargeV3)
        #expect(memory.stored.isEmpty)
    }
}
