//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import CoreML
import Foundation
import WhisperKit

/// Swedish speech recognition with Pianissimo, Klang AI's Swedish fine-tune of
/// Parakeet TDT 0.6B v3, from Konfer's own 120-second CoreML conversion.
///
/// Here to be measured against KB-Whisper Large, reachable only through
/// `KONFER_BACKEND=pianissimo-sv`. Stock Parakeet v3 ran at 71× real time on
/// the README's five minutes of Swedish, against KB-Whisper Large's 7.5×, and
/// was dropped for turning that Swedish into noise. Pianissimo is the same
/// architecture trained on 50,000 hours of Swedish.
///
/// The window is the reason this doesn't go through FluidAudio. FluidAudio
/// runs Parakeet in 15-second windows, fixed at compile time
/// (`ASRConstants.maxModelSamples`), and on a real meeting a 15-second window
/// dropped phrases Klang's 2-minute chunks keep. Over the 1 h 17 m Kickoff
/// meeting, markstrom's 15-second build disagreed with Klang's fp32 MLX on
/// 17.3% of words; this backend, on 2.6%.
///
/// So this backend does what Klang's `pianissimo_mlx.py` does: 120-second
/// windows overlapping by 15, each preprocessed, encoded and decoded on its
/// own, and stitched at the middle of each overlap, where both neighbours had
/// the most context. The decoding is NeMo's greedy TDT loop, step for step.
///
/// The encoder runs on the GPU: a 1501-frame attention matrix is more than
/// the Neural Engine takes, and CoreML quietly falls back to the CPU, at
/// 560 ms a window against the GPU's 133.
///
actor ParakeetBackend: TranscriptionBackend {

    // MARK: - The conversion's contract (`conversion.json`)

    private static let windowSamples = 1_920_000
    private static let overlapSeconds = 15.0
    private static let sampleRate = 16_000.0
    private static let melFrames = 12_001
    private static let secondsPerFrame = 0.08
    private static let encoderWidth = 1024
    private static let decoderWidth = 640
    private static let decoderLayers = 2
    private static let blank: Int32 = 8192
    private static let durations = [0, 1, 2, 3, 4]
    /// Klang's `decoding.greedy.max_symbols`.
    private static let maxSymbolsPerFrame = 10

    private var models: Models?

    func isPrepared(for language: MeetingLanguage) -> Bool { models != nil }

    func prepare(
        for language: MeetingLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard models == nil else { return }
        do {
            try await PianissimoModelStore.download(progress: progress)
        } catch let error as PipelineError {
            throw error
        } catch {
            throw PipelineError.modelDownloadFailed(underlying: error)
        }
        do {
            models = try Models()
        } catch {
            throw PipelineError.transcriptionFailed(underlying: error)
        }
        progress(1)
    }

    func unload() {
        models = nil
    }

    func transcribe(
        _ request: TranscriptionRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscribedAudio {

        guard let models else { throw PipelineError.modelsNotLoaded }

        let samples: [Float]
        do {
            samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: request.url.path)
        } catch {
            throw PipelineError.audioUnreadable(request.url, underlying: error)
        }

        let tokens: [Token]
        do {
            tokens = try Self.decodeWindows(of: samples, with: models, progress: progress)
        } catch {
            throw PipelineError.transcriptionFailed(underlying: error)
        }
        progress(1)

        let words = Self.words(from: tokens, vocabulary: models.vocabulary)
        let text = words.map(\.word).joined(separator: " ")
        return TranscribedAudio(text: text, words: words)
    }

    // MARK: - Windows

    /// One emitted token, timed against the whole recording.
    private struct Token {
        let id: Int32
        let start: TimeInterval
        let end: TimeInterval
    }

    private static func decodeWindows(
        of samples: [Float],
        with models: Models,
        progress: @escaping @Sendable (Double) -> Void
    ) throws -> [Token] {

        let overlap = Int(overlapSeconds * sampleRate)
        let step = windowSamples - overlap
        let starts = Array(stride(from: 0, to: max(1, samples.count - overlap), by: step))
        var tokens: [Token] = []

        for (index, start) in starts.enumerated() {
            try Task.checkCancellation()

            let end = min(start + windowSamples, samples.count)
            let windowStart = Double(start) / sampleRate
            let encoded = try models.encode(samples[start..<end], windowSamples: windowSamples)

            // Each window keeps only the tokens between the midpoints of its
            // overlaps, so every token comes from the window that heard the
            // most on both sides of it.
            let keepFrom = index == 0 ? -Double.infinity : windowStart + overlapSeconds / 2
            let keepUntil = index == starts.count - 1
                ? Double.infinity
                : windowStart + Double(windowSamples) / sampleRate - overlapSeconds / 2

            for token in try greedyDecode(encoded, with: models) {
                let start = windowStart + Double(token.frame) * secondsPerFrame
                guard start >= keepFrom, start < keepUntil else { continue }
                let frames = max(token.duration, 1)
                tokens.append(Token(
                    id: token.id,
                    start: start,
                    end: start + Double(frames) * secondsPerFrame
                ))
            }
            progress(min(Double(index + 1) / Double(starts.count), 0.99))
        }
        return tokens
    }

    // MARK: - Greedy TDT

    private struct FrameToken {
        let id: Int32
        let frame: Int
        let duration: Int
    }

    /// NeMo's `GreedyTDTInfer._greedy_decode`, one window at a time.
    ///
    /// The prediction network only changes when a token is emitted, so its
    /// output is kept rather than recomputed for every frame as NeMo does.
    /// The one shortcut: a blank that skips nothing is answered identically
    /// until `max_symbols` runs out, so it moves on a frame at once.
    private static func greedyDecode(_ encoded: Encoded, with models: Models) throws -> [FrameToken] {
        var emitted: [FrameToken] = []
        var prediction = try models.predict(after: blank, state: nil)
        var frame = 0

        while frame < encoded.frames {
            let step = try encoded.step(at: frame)
            var symbols = 0
            var stayOnFrame = true

            while stayOnFrame, symbols < maxSymbolsPerFrame {
                let decision = try models.decide(encoderStep: step, decoderStep: prediction.output)
                let skip = durations[min(decision.durationIndex, durations.count - 1)]

                if decision.token != blank {
                    emitted.append(FrameToken(id: decision.token, frame: frame, duration: skip))
                    prediction = try models.predict(after: decision.token, state: prediction.state)
                } else if skip == 0 {
                    symbols = maxSymbolsPerFrame
                    break
                }
                symbols += 1
                frame += skip
                stayOnFrame = skip == 0
            }
            if symbols == maxSymbolsPerFrame {
                frame += 1
            }
        }
        return emitted
    }

    // MARK: - Words

    /// SentencePiece pieces into words: a piece starting with `▁` begins one,
    /// anything else — the rest of a word, or punctuation — continues it.
    private static func words(from tokens: [Token], vocabulary: [String]) -> [WordSpan] {
        var words: [WordSpan] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0

        func flush() {
            let word = text.trimmingCharacters(in: .whitespaces)
            if !word.isEmpty { words.append(WordSpan(word: word, start: start, end: end)) }
            text = ""
        }

        for token in tokens {
            let index = Int(token.id)
            guard vocabulary.indices.contains(index) else { continue }
            let piece = vocabulary[index]
            if piece.hasPrefix("<"), piece.hasSuffix(">") { continue }

            if piece.hasPrefix("▁") || text.isEmpty {
                flush()
                text = String(piece.drop(while: { $0 == "▁" }))
                start = token.start
            } else {
                text += piece
            }
            end = token.end
        }
        flush()
        return words
    }
}

// MARK: - Models

/// The four CoreML models and the vocabulary, plus the arrays they reuse.
///
/// Not `Sendable`: CoreML models are made, used and released inside the
/// backend actor.
private nonisolated final class Models {

    let vocabulary: [String]

    private let preprocessor: MLModel
    private let encoder: MLModel
    private let decoder: MLModel
    private let joint: MLModel

    private let audio: MLMultiArray
    private let encoderStep: MLMultiArray
    private let targets: MLMultiArray
    private let targetLength: MLMultiArray
    private let zeroState: MLMultiArray

    init() throws {
        func load(_ name: String, _ units: MLComputeUnits) throws -> MLModel {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = units
            return try MLModel(contentsOf: PianissimoModelStore.url(for: name), configuration: configuration)
        }
        preprocessor = try load("Preprocessor.mlmodelc", .cpuOnly)
        encoder = try load("Encoder.mlmodelc", .cpuAndGPU)
        decoder = try load("Decoder.mlmodelc", .cpuOnly)
        joint = try load("JointDecisionv3.mlmodelc", .cpuOnly)

        let pieces = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: PianissimoModelStore.url(for: "parakeet_vocab.json"))
        )
        var vocabulary = [String](repeating: "", count: pieces.count)
        for (key, piece) in pieces {
            if let id = Int(key), vocabulary.indices.contains(id) { vocabulary[id] = piece }
        }
        self.vocabulary = vocabulary

        audio = try MLMultiArray(shape: [1, 1_920_000], dataType: .float32)
        encoderStep = try MLMultiArray(shape: [1, 1024, 1], dataType: .float32)
        targets = try MLMultiArray(shape: [1, 1], dataType: .int32)
        targetLength = try MLMultiArray(shape: [1], dataType: .int32)
        targetLength[0] = 1
        zeroState = try MLMultiArray(shape: [2, 1, 640], dataType: .float32)
        zeroState.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            buffer.initialize(repeating: 0)
        }
    }

    /// Mel spectrogram and encoder over one window, zero-padded to its fixed
    /// length. The real length goes in beside it, so the padding is masked out
    /// of the spectrogram's normalisation and of attention.
    func encode(_ window: ArraySlice<Float>, windowSamples: Int) throws -> Encoded {
        audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            buffer.initialize(repeating: 0)
            _ = buffer.update(fromContentsOf: window)
        }
        let length = try MLMultiArray(shape: [1], dataType: .int32)
        length[0] = NSNumber(value: window.count)

        let mel = try preprocessor.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "audio_signal": audio, "audio_length": length,
        ]))
        guard let features = mel.featureValue(for: "mel")?.multiArrayValue,
              let featureLength = mel.featureValue(for: "mel_length")?.multiArrayValue
        else { throw CocoaError(.coderValueNotFound) }

        let encoded = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "mel": features, "mel_length": featureLength,
        ]))
        guard let output = encoded.featureValue(for: "encoder")?.multiArrayValue,
              let frames = encoded.featureValue(for: "encoder_length")?.multiArrayValue
        else { throw CocoaError(.coderValueNotFound) }
        return Encoded(output: output, frames: frames[0].intValue, buffer: encoderStep)
    }

    struct Prediction {
        let output: MLMultiArray
        let state: (h: MLMultiArray, c: MLMultiArray)
    }

    /// The prediction network after `token`, from `state` (zeros to begin).
    func predict(after token: Int32, state: (h: MLMultiArray, c: MLMultiArray)?) throws -> Prediction {
        targets[0] = NSNumber(value: token)
        let result = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "targets": targets,
            "target_length": targetLength,
            "h_in": state?.h ?? zeroState,
            "c_in": state?.c ?? zeroState,
        ]))
        guard let output = result.featureValue(for: "decoder")?.multiArrayValue,
              let h = result.featureValue(for: "h_out")?.multiArrayValue,
              let c = result.featureValue(for: "c_out")?.multiArrayValue
        else { throw CocoaError(.coderValueNotFound) }
        return Prediction(output: output, state: (h, c))
    }

    struct Decision {
        let token: Int32
        let durationIndex: Int
    }

    func decide(encoderStep: MLMultiArray, decoderStep: MLMultiArray) throws -> Decision {
        let result = try joint.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "encoder_step": encoderStep, "decoder_step": decoderStep,
        ]))
        guard let token = result.featureValue(for: "token_id")?.multiArrayValue,
              let duration = result.featureValue(for: "duration")?.multiArrayValue
        else { throw CocoaError(.coderValueNotFound) }
        return Decision(token: token[0].int32Value, durationIndex: duration[0].intValue)
    }
}

/// One window's encoder output, `[1, 1024, frames]`, read a frame at a time.
private nonisolated struct Encoded {
    let output: MLMultiArray
    let frames: Int
    /// Shared and overwritten by every ``step(at:)``.
    let buffer: MLMultiArray

    /// Column `frame` copied into the joint's `[1, 1024, 1]` input. Strided,
    /// since the encoder's frames are its innermost axis.
    func step(at frame: Int) throws -> MLMultiArray {
        let width = output.shape[1].intValue
        let stride = output.strides[1].intValue
        let offset = frame * output.strides[2].intValue
        buffer.withUnsafeMutableBufferPointer(ofType: Float.self) { destination, _ in
            switch output.dataType {
            case .float16:
                output.withUnsafeBufferPointer(ofType: Float16.self) { source in
                    for i in 0..<width { destination[i] = Float(source[offset + i * stride]) }
                }
            default:
                output.withUnsafeBufferPointer(ofType: Float.self) { source in
                    for i in 0..<width { destination[i] = source[offset + i * stride] }
                }
            }
        }
        return buffer
    }
}
