//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import AppKit
import CoreAudio
import Foundation

/// The microphones a recording can be made from.
nonisolated enum AudioInputDevices {

    struct Device: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    static func available() -> [Device] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// The applications currently producing audio, which is what can be tapped.
///
/// Core Audio keeps its own list of processes with audio, separate from the
/// list of running applications — an app only appears here once it actually has
/// an output stream.
///
/// That is a stricter condition than a tap needs: `prepare` only requires a
/// process object, which a process keeps after it falls silent. The list is
/// narrowed to what is *playing* because the alternative is unusable — every
/// process that has ever touched audio, `loginwindow` and `PowerChime`
/// included. ``AudioApplicationsMonitor`` carries the cost of that choice: the
/// playing/not-playing property is not one Core Audio notifies on.
nonisolated enum AudioApplications {

    static func playingAudio() -> [AudioApplication] {
        processObjectIDs()
            .filter { isRunningOutput($0) }
            .compactMap { application(for: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The Core Audio process object for a pid, which is what a tap targets.
    static func processObjectID(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &objectID
        )
        guard status == noErr, objectID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return objectID
    }

    // MARK: - Private

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objectIDs
        ) == noErr else { return [] }
        return objectIDs
    }

    private static func isRunningOutput(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    /// Browsers play audio from a helper process, not from the browser itself:
    /// a Google Meet call in Safari comes out of `com.apple.WebKit.GPU`, whose
    /// name is "Safari Graphics and Media". Tapping the helper is correct — but
    /// nobody scanning a list recognises it, so it is presented as the browser.
    private static func friendlyName(bundleIdentifier: String?, fallback: String) -> String {
        guard let bundleIdentifier else { return fallback }
        return switch bundleIdentifier {
        case "com.apple.WebKit.GPU": "Safari"
        case let id where id.hasPrefix("com.google.Chrome"): "Google Chrome"
        case let id where id.hasPrefix("com.microsoft.edgemac"): "Microsoft Edge"
        case let id where id.hasPrefix("org.mozilla.firefox"): "Firefox"
        default: fallback
        }
    }

    /// The bundle identifier Core Audio knows this process by.
    private static func bundleIdentifier(of objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var reference: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &reference) == noErr,
              let reference else { return nil }
        let identifier = reference.takeRetainedValue() as String
        return identifier.isEmpty ? nil : identifier
    }

    private static func application(for objectID: AudioObjectID) -> AudioApplication? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &pid) == noErr
        else { return nil }

        let bundleIdentifier = bundleIdentifier(of: objectID)
        let application = NSRunningApplication(processIdentifier: pid)
        let fallback = application?.localizedName
            ?? bundleIdentifier
            ?? "Process \(pid)"

        return AudioApplication(
            id: pid,
            name: friendlyName(bundleIdentifier: bundleIdentifier, fallback: fallback),
            bundleIdentifier: bundleIdentifier ?? application?.bundleIdentifier
        )
    }
}
