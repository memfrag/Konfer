//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Foundation
import ScreenCaptureKit

/// Records the microphone together with everything the Mac plays.
///
/// ScreenCaptureKit hands both sides over from a single stream — system audio
/// as `.audio` buffers and the microphone as `.microphone` ones — so they share
/// a clock without any work on our part.
///
/// The cost is that macOS treats system audio as screen recording, so this
/// route asks for a permission whose wording is alarming for an audio recorder,
/// and it picks up every other sound the machine makes. Recording a single app
/// avoids both; neither is strictly better, which is why both exist.
nonisolated final class ScreenCaptureRecorder: NSObject, RecordingSource, @unchecked Sendable {

    private var stream: SCStream?
    private var writer: TwoChannelWriter?
    private var configuration: RecordingConfiguration?

    // MARK: - RecordingSource

    func prepare(_ configuration: RecordingConfiguration) async throws {
        if !AudioInputDevices.isAuthorized {
            guard await AudioInputDevices.requestAccess() else {
                throw RecordingError.microphoneAccessDenied
            }
        }
        // Asking for shareable content is what triggers, and tests, the screen
        // recording permission — better here than halfway into a meeting.
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw RecordingError.screenRecordingAccessDenied
        }
        self.configuration = configuration
    }

    func start(writingTo writer: TwoChannelWriter) async throws {
        guard let configuration else { throw RecordingError.noAudioDevice }
        self.writer = writer

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw RecordingError.screenRecordingAccessDenied
        }

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.capturesAudio = true
        streamConfiguration.captureMicrophone = true
        streamConfiguration.microphoneCaptureDeviceID = configuration.microphoneID
        // Without this, Konfer playing back a transcript would record itself.
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = Int(TwoChannelWriter.sampleRate)
        streamConfiguration.channelCount = 1
        // Audio-only still needs a content filter, so ask for the smallest
        // legal frame and never look at it.
        streamConfiguration.width = 2
        streamConfiguration.height = 2
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        writer = nil
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureRecorder: SCStreamOutput {

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard let writer, sampleBuffer.isValid else { return }
        guard let samples = Self.monoSamples(from: sampleBuffer) else { return }

        switch type {
        case .microphone: writer.appendMicrophone(samples)
        case .audio: writer.appendSystemAudio(samples)
        default: break
        }
    }

    /// Flattens a sample buffer to one channel of floats.
    ///
    /// Both sides are recorded mono: each occupies one channel of the output
    /// file, so a stereo source is summed rather than kept as a stereo image.
    private static func monoSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription
        else { return nil }

        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&list)
        guard let first = buffers.first, let data = first.mData else { return nil }

        let frames = Int(sampleBuffer.numSamples)
        guard frames > 0 else { return nil }

        let channels = Int(description.mChannelsPerFrame)
        let pointer = data.assumingMemoryBound(to: Float.self)

        // Non-interleaved: one buffer per channel, so buffer 0 is already mono.
        if buffers.count > 1 || channels == 1 {
            return Array(UnsafeBufferPointer(start: pointer, count: frames))
        }

        // Interleaved stereo: take the left channel rather than summing, so a
        // channel can't clip when both carry the same signal.
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            mono[frame] = pointer[frame * channels]
        }
        return mono
    }
}
