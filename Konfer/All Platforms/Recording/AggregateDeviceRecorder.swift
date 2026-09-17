//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import CoreAudio
import Foundation

/// Records the microphone together with one application's audio.
///
/// A Core Audio process tap captures just that app's output — a Slack ping or
/// music playing in another window never reaches the file.
///
/// It is not permission-free, which this said for too long. A tap is gated
/// behind *System Audio Recording* (`kTCCServiceAudioCapture`): a different
/// permission from screen recording, granted in the same Settings pane, asked
/// for by `AudioDeviceStart` rather than by creating the tap — and **denied
/// silently**. Every call still returns `noErr`, every buffer is zeros, and the
/// recording comes out with a silent right channel. That is why
/// ``RecorderController`` watches the level rather than a status code, and why
/// `NSAudioCaptureUsageDescription` has to be in `Info.plist`: without it TCC
/// refuses without ever asking the user.
///
/// Mic and tap are combined into a single *private* aggregate device rather
/// than captured separately. That is the whole trick: one device means one
/// clock, so the two channels cannot drift apart over an hour, and no
/// resampling or timestamp reconciliation is needed.
nonisolated final class AggregateDeviceRecorder: RecordingSource, @unchecked Sendable {

    /// An AUHAL, not `AVAudioEngine`. The aggregate device presents the
    /// microphone and the tap as two separate single-channel *streams*, and
    /// `AVAudioEngine`'s input node only ever reads stream 0 — so the tap is
    /// structurally invisible to it, and the recording comes out with a silent
    /// right channel. AUHAL reads every stream as one multi-channel bus.
    private var unit: AudioUnit?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var writer: TwoChannelWriter?

    /// Whether the microphone is part of the aggregate at all.
    ///
    /// When it is not, the device is built around the default *output* device
    /// instead — see `prepare`. Nothing then opens an input device, so macOS
    /// never asks for the microphone permission for a recording that was only
    /// ever going to hold the other side.
    private var recordsMicrophone = true

    /// Channels the aggregate device gives us. The microphone's come first and
    /// the mono tap is last.
    private var channelCount = 2

    private var bufferList: UnsafeMutableAudioBufferListPointer?
    /// Stable, manually managed storage for the render callback.
    ///
    /// Not `[[Float]]`: taking `withUnsafeMutableBytes { $0.baseAddress }` and
    /// storing the result hands Core Audio a pointer that is only valid inside
    /// that closure. It happens to work often enough to look fine, which is the
    /// worst way for undefined behaviour to present itself.
    private var channelBuffers: [UnsafeMutablePointer<Float>] = []
    private let framesPerBuffer = 4096

    deinit {
        // A leaked aggregate device outlives the process and shows up in the
        // user's Audio MIDI Setup, so this is not merely tidy.
        teardown()
    }

    // MARK: - RecordingSource

    func prepare(_ configuration: RecordingConfiguration) async throws {
        guard case .app(let application) = configuration.systemAudio else {
            throw RecordingError.noAudioDevice
        }
        recordsMicrophone = configuration.recordsMicrophone
        if recordsMicrophone, !AudioInputDevices.isAuthorized {
            guard await AudioInputDevices.requestAccess() else {
                throw RecordingError.microphoneAccessDenied
            }
        }
        guard let processID = AudioApplications.processObjectID(for: application.id) else {
            throw RecordingError.applicationNotPlayingAudio(application.name)
        }

        let tapDescription = CATapDescription(monoMixdownOfProcesses: [processID])
        tapDescription.name = "Konfer \(application.name)"
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        // Muting the app while recording it would make the call unusable.
        tapDescription.muteBehavior = .unmuted

        var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr else { throw RecordingError.tapCreationFailed(status) }

        // Ask the tap what its UID actually is rather than assuming it matches
        // the description's UUID. The aggregate device silently ignores a tap
        // entry it can't resolve, and the only symptom is a missing channel.
        guard let tapUID = Self.tapUID(of: tapID) else {
            teardown()
            throw RecordingError.tapCreationFailed(status)
        }

        // An aggregate device needs a main sub-device to own its clock, and a
        // tap is not one. With the microphone in the recording that is the
        // microphone; without it, the default output device stands in — it
        // contributes no *input* channels, so the aggregate's only input
        // channel is the mono tap, and no input device is ever opened.
        let clockUID = recordsMicrophone
            ? configuration.microphoneID ?? Self.defaultInputUID()
            : Self.defaultDeviceUID(kAudioHardwarePropertyDefaultOutputDevice)
        guard let clockUID else { throw RecordingError.noAudioDevice }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Konfer Recording",
            kAudioAggregateDeviceUIDKey: "pizza.martin.Konfer.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: clockUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: clockUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else {
            teardown()
            throw RecordingError.aggregateDeviceFailed(status)
        }

        // Floor of one without the microphone: a tap-only aggregate is
        // expected to expose exactly the mono tap.
        channelCount = max(recordsMicrophone ? 2 : 1, Self.inputChannelCount(of: aggregateID))
        try setUpAudioUnit()
    }

    func start(writingTo writer: TwoChannelWriter) async throws {
        guard let unit else { throw RecordingError.noAudioDevice }
        self.writer = writer

        let status = AudioOutputUnitStart(unit)
        guard status == noErr else { throw RecordingError.aggregateDeviceFailed(status) }
    }

    func stop() async {
        if let unit { AudioOutputUnitStop(unit) }
        writer = nil
        teardown()
    }

    // MARK: - AUHAL

    private func setUpAudioUnit() throws {
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw RecordingError.noAudioDevice
        }
        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let unit else { throw RecordingError.aggregateDeviceFailed(status) }
        self.unit = unit

        // AUHAL is an output unit; capturing means enabling its input bus and
        // disabling its output one.
        var enable: UInt32 = 1
        var disable: UInt32 = 0
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                             &enable, UInt32(MemoryLayout<UInt32>.size))
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                             &disable, UInt32(MemoryLayout<UInt32>.size))

        var device = aggregateID
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                      kAudioUnitScope_Global, 0,
                                      &device, UInt32(MemoryLayout<AudioObjectID>.size))
        guard status == noErr else { throw RecordingError.aggregateDeviceFailed(status) }

        // Non-interleaved float, one buffer per channel: the microphone and the
        // tap arrive as separate buffers, which is exactly how they are wanted.
        var format = AudioStreamBasicDescription(
            mSampleRate: TwoChannelWriter.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, 1,
                                      &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw RecordingError.aggregateDeviceFailed(status) }

        var callback = AURenderCallbackStruct(
            inputProc: { context, flags, timestamp, bus, frames, _ in
                let recorder = Unmanaged<AggregateDeviceRecorder>
                    .fromOpaque(context).takeUnretainedValue()
                return recorder.render(flags: flags, timestamp: timestamp, frames: frames, bus: bus)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Global, 0,
                                      &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw RecordingError.aggregateDeviceFailed(status) }

        status = AudioUnitInitialize(unit)
        guard status == noErr else { throw RecordingError.aggregateDeviceFailed(status) }

        allocateBuffers()

        if Self.isDiagnostic {
            print("TAP: AUHAL on aggregate \(aggregateID), \(channelCount) channels")
        }
    }

    private func allocateBuffers() {
        channelBuffers = (0..<channelCount).map { _ in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: framesPerBuffer)
            pointer.initialize(repeating: 0, count: framesPerBuffer)
            return pointer
        }

        let list = AudioBufferList.allocate(maximumBuffers: channelCount)
        for channel in 0..<channelCount {
            list[channel] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(framesPerBuffer * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(channelBuffers[channel])
            )
        }
        bufferList = list
    }

    /// Called on Core Audio's realtime thread.
    private func render(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frames: UInt32,
        bus: UInt32
    ) -> OSStatus {
        guard let unit, let bufferList else { return noErr }

        let count = min(Int(frames), framesPerBuffer)
        for channel in 0..<channelCount {
            bufferList[channel].mNumberChannels = 1
            bufferList[channel].mDataByteSize = UInt32(count * MemoryLayout<Float>.size)
            bufferList[channel].mData = UnsafeMutableRawPointer(channelBuffers[channel])
        }

        let status = AudioUnitRender(
            unit, flags, timestamp, bus, UInt32(count), bufferList.unsafeMutablePointer
        )
        guard status == noErr else { return status }
        guard let writer else { return noErr }

        if recordsMicrophone {
            writer.appendMicrophone(
                Array(UnsafeBufferPointer(start: channelBuffers[0], count: count))
            )
        }
        // The tap is the last channel: after the microphone's when there is
        // one, and the only channel when there is not. With the microphone on,
        // a single-channel aggregate means the tap never made it in — sending
        // channel 0 as system audio would then copy the microphone onto both
        // sides of the file.
        let tapChannel = channelCount - 1
        if !recordsMicrophone || tapChannel > 0 {
            writer.appendSystemAudio(
                Array(UnsafeBufferPointer(start: channelBuffers[tapChannel], count: count))
            )
        }
        return noErr
    }

    private func teardown() {
        if let unit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            self.unit = nil
        }
        if let bufferList {
            free(bufferList.unsafeMutablePointer)
            self.bufferList = nil
        }
        for pointer in channelBuffers {
            pointer.deinitialize(count: framesPerBuffer)
            pointer.deallocate()
        }
        channelBuffers = []
        teardownCoreAudioObjects()
    }

    /// `KONFER_RECORD_DIAGNOSTICS=1` reports what the aggregate device actually
    /// produced, which is the only way to tell "captured silence" apart from
    /// "captured nothing".
    nonisolated static var isDiagnostic: Bool {
        ProcessInfo.processInfo.environment["KONFER_RECORD_DIAGNOSTICS"] == "1"
    }

    // MARK: - Core Audio plumbing

    private func teardownCoreAudioObjects() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// The tap object's own UID, which is what an aggregate device's tap list
    /// refers to.
    private static func tapUID(of tapID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var reference: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &reference) == noErr,
              let reference else { return nil }
        return reference.takeRetainedValue() as String
    }

    /// Total input channels a device exposes, for diagnostics.
    private static func inputChannelCount(of deviceID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr
        else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        if isDiagnostic {
            print("TAP: aggregate input has \(list.count) stream(s): "
                  + "\(list.map { Int($0.mNumberChannels) })")
        }
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// UID of the system's default input, used when no microphone was chosen.
    private static func defaultInputUID() -> String? {
        defaultDeviceUID(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// UID of one of the system's default devices.
    ///
    /// - Parameter selector: `kAudioHardwarePropertyDefaultInputDevice` for the
    ///   microphone side, `…DefaultOutputDevice` for the device that owns the
    ///   clock of a tap-only aggregate.
    private static func defaultDeviceUID(_ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }

        // Core Audio returns a retained CFStringRef here, so it has to be
        // received as an Unmanaged reference and consumed, not bridged.
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &uidSize, &uid) == noErr,
              let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}
