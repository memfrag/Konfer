#!/usr/bin/env swift
//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//
//  Lists the locales Apple's on-device `SpeechTranscriber` can transcribe, and
//  which of them already have their models installed on this Mac.
//
//  Usage: swift scripts/supported-locales.swift
//

import Foundation
import Speech

func describe(_ locale: Locale) -> String {
    let tag = locale.identifier(.bcp47)
    let name = Locale(identifier: "en_US").localizedString(forIdentifier: locale.identifier)
    return name.map { "\(tag.padding(toLength: 10, withPad: " ", startingAt: 0)) \($0)" } ?? tag
}

print("SpeechTranscriber.isAvailable: \(SpeechTranscriber.isAvailable)")

let supported = await SpeechTranscriber.supportedLocales
let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })

print("\nSupported locales (\(supported.count)) — ✓ = models installed:\n")
for locale in supported.sorted(by: { $0.identifier(.bcp47) < $1.identifier(.bcp47) }) {
    let mark = installed.contains(locale.identifier(.bcp47)) ? "✓" : " "
    print(" \(mark) \(describe(locale))")
}

// What Snoopy actually asks for: the user's own locale if it is supported.
let current = Locale.current
let match = await SpeechTranscriber.supportedLocale(equivalentTo: current)
print("\nCurrent locale \(current.identifier(.bcp47)): "
      + (match.map { "supported as \($0.identifier(.bcp47))" } ?? "NOT supported"))

let swedish = supported.contains { $0.language.languageCode?.identifier == "sv" }
print("Swedish supported: \(swedish)")
