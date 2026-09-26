//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import SwiftUI

/// Asks for what actually helps before a run starts, and shows the recording
/// while it asks.
///
/// The speaker count measurably improves clustering when the user knows it.
/// The language is load-bearing: it routes English to Apple's transcriber and
/// everything else to KB-Whisper, and it stops Whisper detecting a language
/// per chunk — which on a Swedish meeting full of English loanwords makes it
/// flip mid-recording.
///
/// The waveform is here because the alternative is transcribing twenty minutes
/// of people joining a call. Trimming is optional and costs nothing to ignore:
/// the handles start at the two ends, and a range covering everything is sent
/// as no range at all.
///
/// Also serves a re-run of a meeting that already exists — see `replacing` at
/// the call site — which is why the language and the range can be seeded.
struct ImportSheet: View {

    let url: URL

    /// Set when this exact file has been transcribed before.
    var alreadyTranscribed: Meeting?

    var heading = "Transcribe Recording"
    var confirmTitle = "Transcribe"

    /// Seeded when re-running a meeting: its language, and the trim that
    /// prompted the re-run.
    var initialLanguage: MeetingLanguage = .english
    var initialRange: KeptRange?

    /// Whether this file keeps the microphone and the call on separate
    /// channels, which is the only case where the speakers question below
    /// means anything. Only the recorder knows — see `Meeting/hasSeparateSources`.
    var separatesSources = false

    /// Seeded on a re-run with what the first run was told.
    var initialSuppressBleed = false

    /// Whether to ask where the meeting goes. Not on a re-run, which replaces
    /// a meeting where it already is.
    var choosesFolder = true

    /// The folder the recording was dropped on, which wins over the usual
    /// starting folder — dropping it there was the choice.
    var initialFolder: MeetingFolder?

    /// Seeded on a re-run with the model the meeting was made with, so
    /// transcribing it again with the other one is a deliberate switch.
    var initialModel: ASRBackendKind?

    let onTranscribe: (TranscribeChoices) -> Void
    var onOpenExisting: ((Meeting) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(ModelDownloadQueue.self) private var downloads
    @Environment(AppSettings.self) private var appSettings
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(LibrarySelection.self) private var librarySelection

    @State private var language: MeetingLanguage
    @State private var knowsSpeakerCount = false
    @State private var speakerCount = 4
    @State private var suppressBleed: Bool
    @State private var folder: MeetingFolder = .root
    @State private var model: ASRBackendKind

    /// The model last used for each language with a choice — see
    /// ``RememberedModels``.
    @AppStorage("rememberedTranscriptionModels") private var rememberedModels = ""

    @State private var player = PlayerController()
    @State private var waveform: Waveform?
    @State private var duration: TimeInterval = 0
    @State private var range: KeptRange?
    @State private var isReadingWaveform = true

    init(
        url: URL,
        alreadyTranscribed: Meeting? = nil,
        heading: String = "Transcribe Recording",
        confirmTitle: String = "Transcribe",
        initialLanguage: MeetingLanguage = .english,
        initialRange: KeptRange? = nil,
        separatesSources: Bool = false,
        initialSuppressBleed: Bool = false,
        choosesFolder: Bool = true,
        initialFolder: MeetingFolder? = nil,
        initialModel: ASRBackendKind? = nil,
        onTranscribe: @escaping (TranscribeChoices) -> Void,
        onOpenExisting: ((Meeting) -> Void)? = nil
    ) {
        self.url = url
        self.alreadyTranscribed = alreadyTranscribed
        self.heading = heading
        self.confirmTitle = confirmTitle
        self.initialLanguage = initialLanguage
        self.initialRange = initialRange
        self.separatesSources = separatesSources
        self.initialSuppressBleed = initialSuppressBleed
        self.choosesFolder = choosesFolder
        self.initialFolder = initialFolder
        self.initialModel = initialModel
        self.onTranscribe = onTranscribe
        self.onOpenExisting = onOpenExisting
        _language = State(initialValue: initialLanguage)
        _range = State(initialValue: initialRange)
        _suppressBleed = State(initialValue: initialSuppressBleed)
        // Replaced on appear by the remembered model when there's no initial
        // one: `@AppStorage` can't be read before the view exists.
        _model = State(initialValue: initialModel.flatMap {
            ASRBackendKind.choices(for: initialLanguage).contains($0) ? $0 : nil
        } ?? ASRBackendKind(transcribing: initialLanguage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.headline)
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let alreadyTranscribed {
                duplicateNotice(alreadyTranscribed)
            }

            recording

            Form {
                Picker("Language:", selection: $language) {
                    ForEach(MeetingLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .help(
                    "The language decides which model transcribes: Apple's "
                    + "built-in recognition where it has the language, "
                    + "KB-Whisper for Swedish, Røst for Danish (or OpenAI's "
                    + "Whisper, if you choose it), and OpenAI's Whisper for "
                    + "Dutch and Polish."
                )

                // Only where there is something to choose — today, Danish.
                // Everywhere else the language has settled it.
                if modelChoices.count > 1 {
                    Picker("Model:", selection: $model) {
                        ForEach(modelChoices, id: \.self) { choice in
                            Text(ManagedModel(for: choice)?.displayName ?? choice.displayName)
                                .tag(choice)
                        }
                    }
                    Text(modelCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let missing = missingModel {
                    modelNotice(missing)
                }

                if choosesFolder {
                    FolderPicker(folder: $folder)
                }

                Toggle("I know how many people spoke", isOn: $knowsSpeakerCount)

                if knowsSpeakerCount {
                    Stepper(
                        "Speakers: \(speakerCount)",
                        value: $speakerCount,
                        in: 1...20
                    )
                    Text("Telling Konfer the number of speakers usually improves the result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Asked rather than measured. The bleed is measurable — see
                // `BleedSuppression` — but acting on it means ignoring parts of
                // the microphone, and whether the call came out of the speakers
                // is something the user simply knows.
                if separatesSources {
                    Toggle("The call came out of the speakers", isOn: $suppressBleed)
                    Text(
                        suppressBleed
                        ? "Konfer will ignore the microphone wherever only the call "
                          + "is audible on it, so the people on the call aren't also "
                          + "listed as being in the room."
                        : "Turn this on if you weren't wearing headphones. The "
                          + "microphone hears the call too, and the far end can end "
                          + "up listed as someone in the room."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    var memory = RememberedModels(rememberedModels)
                    memory.remember(model, for: language)
                    rememberedModels = memory.stored
                    onTranscribe(TranscribeChoices(
                        language: language,
                        expectedSpeakers: knowsSpeakerCount ? speakerCount : nil,
                        trim: trim,
                        suppressesBleed: separatesSources && suppressBleed,
                        folder: folder,
                        model: model
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(missingModel != nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await load() }
        // Read once, when the sheet opens: the sidebar may change behind it,
        // and the picker shouldn't move while someone is looking at it.
        // A different language offers different models; start each on the one
        // last used for it.
        .onChange(of: language) { _, language in
            model = RememberedModels(rememberedModels).model(for: language)
        }
        .onAppear {
            if initialModel == nil {
                model = RememberedModels(rememberedModels).model(for: language)
            }
            folder = initialFolder
                ?? librarySelection.folderForNewMeeting(settings: appSettings, in: meetingStore)
        }
        .onDisappear { player.unload() }
        // Playback stops at the right-hand handle, so listening to the edge of
        // the selection tells you where it is rather than running past it.
        .onChange(of: player.currentTime) { _, time in
            if let range, player.isPlaying, time >= range.end { player.pause() }
        }
    }

    // MARK: - The recording

    @ViewBuilder private var recording: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isReadingWaveform {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the recording…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 72, alignment: .center)
            } else if let waveform, let bound = range, duration > 0 {
                TrimmableWaveform(
                    waveform: waveform,
                    duration: duration,
                    currentTime: player.currentTime,
                    range: Binding(get: { bound }, set: { range = $0 }),
                    onSeek: { player.seek(to: $0) }
                )
                transport
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .foregroundStyle(.secondary)
                    Text("Couldn't read a waveform from this file — it will be "
                         + "transcribed whole.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: 72, alignment: .center)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button {
                startPlaying()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)
            .disabled(!player.isLoaded)
            .help("Listen, to find where to trim")

            Text("\(Timecode.short(player.currentTime)) / \(Timecode.short(duration))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            if let range, isTrimmed {
                Text("Keeping \(Timecode.short(range.start))–\(Timecode.short(range.end))")
                    .font(.caption)
                    .monospacedDigit()
            } else {
                Text("Whole recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Laid out in both states and merely disabled, because a small
            // button is taller than the caption beside it: letting Reset appear
            // with the first drag grew the sheet — its height is free, only the
            // width is fixed — and shifted everything above it.
            Button("Reset") { range = KeptRange(start: 0, end: duration) }
                .controlSize(.small)
                .disabled(!isTrimmed)
        }
    }

    /// Starts inside the selection rather than wherever the playhead was left,
    /// since the point of playing here is to hear what is being kept.
    private func startPlaying() {
        if let range, !player.isPlaying,
           player.currentTime < range.start || player.currentTime >= range.end {
            player.seek(to: range.start)
        }
        player.playPause()
    }

    // MARK: - Loading

    private func load() async {
        let asset = AVURLAsset(url: url)
        let length = (try? await asset.load(.duration).seconds) ?? 0
        duration = length.isFinite ? length : 0

        if duration > 0 {
            player.load(url)
            if range == nil { range = KeptRange(start: 0, end: duration) }
        }

        waveform = await WaveformStore.waveform(at: url)
        isReadingWaveform = false
    }

    // MARK: - Derived

    /// The trim to hand the pipeline, or nil when the handles are at the ends.
    /// "Everything" and "no trim" should reach the pipeline as the same thing.
    private var trim: KeptRange? {
        guard isTrimmed, let range else { return nil }
        return range
    }

    private var isTrimmed: Bool {
        guard let range, duration > 0 else { return false }
        return range.start > 0.05 || range.end < duration - 0.05
    }

    /// The model this language needs and doesn't have yet.
    ///
    /// Nil for the languages Apple covers, whatever is on disk: macOS installs
    /// those itself on first use, so there is nothing to wait for.
    private var missingModel: ManagedModel? {
        guard let required = ManagedModel(for: model) else { return nil }
        return downloads.state(of: required) == .installed ? nil : required
    }

    private var modelChoices: [ASRBackendKind] {
        ASRBackendKind.choices(for: language)
    }

    /// Why one might pick either, in a line — the numbers are the model
    /// authors', and say so.
    private var modelCaption: String {
        switch model {
        case .roestWhisper:
            // A non-breaking hyphen, so "large-v3" isn't split across lines.
            "Fine-tuned for Danish by the CoRal project, which measures it at "
            + "less than half Whisper large\u{2011}v3's errors on conversational Danish."
        case .whisperLargeV3:
            "OpenAI's multilingual Whisper, which transcribed Danish before Røst. "
            + "Worth trying on the same recording to compare."
        default:
            model.summary
        }
    }

    /// Says which model is missing and how big it is, rather than letting the
    /// user commit to a transcription that would stop to fetch three gigabytes.
    private func modelNotice(_ model: ManagedModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(language.displayName) needs \(model.displayName), "
                 + "\(ModelStorage.formattedSize(model.estimatedBytes)), "
                 + "which hasn't been downloaded yet.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Button(downloads.state(of: model).isBusy ? "Downloading…" : "Download\u{2026}") {
                downloads.enqueue(model)
                openWindow(id: ModelDownloadsWindow.windowID)
            }
            .controlSize(.small)
            .disabled(downloads.state(of: model).isBusy)
        }
        .padding(.vertical, 2)
    }

    private func duplicateNotice(_ meeting: Meeting) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text("You've transcribed this recording before.")
                    .font(.callout)
                if let onOpenExisting {
                    Button("Open the existing transcript") {
                        onOpenExisting(meeting)
                        dismiss()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Choices

/// What the Transcribe sheet was told, handed to whoever starts the run.
///
/// One value rather than a closure of six arguments, three of them `Bool`s and
/// optionals, that every caller had to pass in the right order.
struct TranscribeChoices {
    let language: MeetingLanguage
    let expectedSpeakers: Int?
    let trim: KeptRange?
    let suppressesBleed: Bool
    let folder: MeetingFolder
    let model: ASRBackendKind
}

#if DEBUG
#Preview {
    ImportSheet(
        url: URL(fileURLWithPath: "/tmp/Standup.m4a"),
        separatesSources: true,
        onTranscribe: { _ in }
    )
    .previewEnvironment()
}
#endif
