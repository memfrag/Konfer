//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The pair table is a recorded measurement, so what is worth testing is that
/// it still says what was measured — and that the four pairs macOS refuses are
/// refused rather than quietly routed through English.
struct TranslationSupportTests {

    @Test("Swedish and Polish are refused as a pair, in both directions")
    func swedishAndPolish() {
        #expect(TranslationSupport.isKnownUnavailable(from: .swedish, to: .polish))
        #expect(TranslationSupport.isKnownUnavailable(from: .polish, to: .swedish))
    }

    @Test("Danish and Polish are refused as a pair, in both directions")
    func danishAndPolish() {
        #expect(TranslationSupport.isKnownUnavailable(from: .danish, to: .polish))
        #expect(TranslationSupport.isKnownUnavailable(from: .polish, to: .danish))
    }

    @Test("Exactly four of the ordered pairs are refused")
    func onlyFourRefused() {
        let refused = MeetingLanguage.allCases.flatMap { source in
            MeetingLanguage.allCases.filter { $0 != source }
                .filter { TranslationSupport.isKnownUnavailable(from: source, to: $0) }
        }
        #expect(refused.count == 4)
    }

    @Test("Every other pair of Konfer's languages is offered")
    func everythingElseIsOffered() {
        #expect(!TranslationSupport.isKnownUnavailable(from: .swedish, to: .english))
        #expect(!TranslationSupport.isKnownUnavailable(from: .polish, to: .english))
        #expect(!TranslationSupport.isKnownUnavailable(from: .danish, to: .dutch))
        #expect(!TranslationSupport.isKnownUnavailable(from: .german, to: .italian))
    }

    @Test("A language is never offered as a translation of itself")
    func neverItself() {
        for language in MeetingLanguage.allCases {
            #expect(!TranslationSupport.targets(for: language).contains(language))
        }
    }

    @Test("Every other language is offered as a target, in the picker's order")
    func targetsKeepPickerOrder() {
        let targets = TranslationSupport.targets(for: .swedish)

        #expect(targets.count == MeetingLanguage.allCases.count - 1)
        #expect(targets == MeetingLanguage.allCases.filter { $0 != .swedish })
    }
}
