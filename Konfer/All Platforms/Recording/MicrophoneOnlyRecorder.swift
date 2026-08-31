//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import CoreAudio
import Foundation

/// Records the microphone alone, for when there is no call to capture.
///
/// The system side of the file is left silent rather than absent, so every
/// recording Konfer makes has the same shape: microphone on channel 0, whatever
/// the Mac was playing on channel 1.
nonisolated final class MicrophoneOnlyRecorder: RecordingSource, @unchecked Sendable {

    private let engine = AVAudioEngine()
    private var writer: TwoChannelWriter?

    func prepare(_ configuration: RecordingConfiguration) async throws {
        if !AudioInputDevices.isAuthorized {
            guard await AudioInputDevices.requestAccess() else {
                throw RecordingError.microphoneAccessDenied
            }
        }
        guard let uniqueID = configuration.microphoneID else { return }
        guard let deviceID = Self.deviceID(forUID: uniqueID),
              let unit = engine.inputNode.audioUnit else {
            throw RecordingError.noAudioDevice
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else { throw RecordingError.noAudioDevice }
    }

    func start(writingTo writer: TwoChannelWriter) async throws {
        self.writer = writer
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        // `@Sendable` is load-bearing. `AVAudioNodeTapBlock` is not declared
        // Sendable, so under this app's default-MainActor isolation Swift
        // assumes the closure belongs to the enclosing actor and inserts an
        // isolation check. AVFAudio then calls it on its realtime messenger
        // queue, the check fails, and the process takes a SIGTRAP.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable [weak self] buffer, _ in
            guard let self, let writer = self.writer,
                  let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            writer.appendMicrophone(Array(UnsafeBufferPointer(start: channels[0], count: frames)))
        }

        do {
            try engine.start()
        } catch {
            throw RecordingError.writeFailed(underlying: error)
        }
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writer = nil
    }

    /// Core Audio device for an `AVCaptureDevice.uniqueID`, which on macOS is
    /// the same string as the device's Core Audio UID.
    private static func deviceID(forUID uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        // The qualifier is a CFStringRef, so what Core Audio wants is a pointer
        // to the reference itself. Taking `&someCFString` instead bridges, and
        // hands it a pointer into a temporary that may not be the object.
        let cfUID = uid as CFString
        var qualifier = Unmanaged.passUnretained(cfUID).toOpaque()
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<UnsafeMutableRawPointer>.size),
            &qualifier,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }
}
