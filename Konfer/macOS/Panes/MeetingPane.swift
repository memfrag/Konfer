//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// A transcript: speaker-tagged, timestamped, editable, and playable.
struct MeetingPane: View {

    let meetingID: UUID

    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpeakerStore.self) private var speakerStore
    @Environment(TranscriptionPipeline.self) private var pipeline

    @State private var player = PlayerController()
    @State private var waveform: Waveform?
    @State private var exportFormat: TranscriptExporter.Format?
    @State private var exportDocument: TranscriptDocument?
    @State private var find = TranscriptFindController()
    @State private var isChoosingAudio = false
    @State private var isRetranscribing = false

    /// The range being dragged, while the trim handles are up. Held apart from
    /// the meeting so that abandoning a trim costs nothing and the transcript
    /// doesn't collapse and reappear under the handles as they move.
    @State private var draftRange: KeptRange?

    /// Whether the collapsed rows are open. Trimmed text is hidden, never
    /// gone — this is how you look at it.
    @State private var isShowingTrimmed = false

    private var meeting: Meeting? { meetingStore.meeting(meetingID) }

    var body: some View {
        Pane {
            if let meeting {
                content(meeting)
            } else {
                EmptyPane()
            }
        }
        .navigationTitle(meeting?.title ?? "Transcript")
        .navigationSubtitle(meeting.map { Timecode.short($0.duration) } ?? "")
        .onAppear { loadAudio() }
        .task(id: meetingID) { await loadWaveform() }
        .onDisappear { player.unload() }
        .focusedSceneValue(\.exportableMeeting, exportable)
        // Lets Edit ▸ Find drive this transcript's find bar.
        .focusedSceneValue(\.transcriptFind, find)
        // `initial` matters: without it the controller holds no transcript
        // until one changes, and the first search of an untouched meeting
        // finds nothing.
        // Kept turns only, so the find bar can't march the playhead to a line
        // the trim is hiding — and so replace-all can't rewrite text that no
        // export would contain.
        .onChange(of: meeting?.keptUtterances, initial: true) { _, utterances in
            find.update(with: utterances ?? [])
        }
        .onChange(of: meetingID) { _, _ in find.dismiss() }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: exportDocument?.contentType ?? .plainText,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .sheet(isPresented: $isRetranscribing) {
            if let meeting {
                ImportSheet(
                    url: meeting.audioURL,
                    heading: "Transcribe Again",
                    initialLanguage: meeting.language,
                    // Seeded with the trim, which is the point: a run that
                    // failed or came back as noise is worth retrying on the
                    // stretch that is actually speech.
                    initialRange: meeting.keptRange
                ) { language, speakers, trim in
                    pipeline.enqueue(
                        meeting.audioURL,
                        language: language,
                        expectedSpeakers: speakers,
                        trim: trim,
                        replacing: meeting.id,
                        title: meeting.title
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $isChoosingAudio,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await attachAudio(at: url) }
        }
    }

    // MARK: - Content

    private func content(_ meeting: Meeting) -> some View {
        VStack(spacing: 0) {
            header(meeting)
            Divider()
            if find.isPresented {
                TranscriptFindBar(
                    controller: find,
                    onReplace: { replaceCurrentMatch() },
                    onReplaceAll: { replaceAllMatches() }
                )
            }
            transcript(meeting)
            if !meeting.audioExists {
                Divider()
                missingAudioNotice
            } else if let draftRange, let waveform, player.isLoaded {
                Divider()
                trimBar(meeting, waveform: waveform, range: draftRange)
            } else if player.isLoaded {
                Divider()
                PlaybackBar(
                    player: player,
                    duration: meeting.duration,
                    cuts: meeting.sliceCuts ?? [],
                    waveform: waveform,
                    speakers: speakerSpans(in: meeting),
                    canTrim: waveform != nil,
                    onTrim: { beginTrimming(meeting) },
                    onRetranscribe: { isRetranscribing = true }
                )
            }
        }
    }

    /// Shown where the player would be, because a missing recording is a
    /// playback problem: everything else on this screen still works.
    ///
    /// The button is the way out of it, for the two meetings that land here —
    /// a transcript imported without a recording, and one whose file has since
    /// moved. Both are a wrong path and nothing else, so neither is worth
    /// re-transcribing an hour to repair.
    private var missingAudioNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .foregroundStyle(.secondary)
            Text("Recording not found — playback unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Choose Recording…") { isChoosingAudio = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Trimming

    /// The handles, and the two ways out of them.
    ///
    /// Replaces the playback bar rather than sitting beside it: while you are
    /// choosing a range, the waveform is for choosing a range, and two
    /// waveforms stacked in a transcript window is one too many.
    private func trimBar(
        _ meeting: Meeting,
        waveform: Waveform,
        range: KeptRange
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TrimmableWaveform(
                waveform: waveform,
                duration: meeting.duration,
                currentTime: player.currentTime,
                range: Binding(get: { range }, set: { draftRange = $0 }),
                onSeek: { player.seek(to: $0) }
            )

            HStack(spacing: 10) {
                Button {
                    player.playPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 12)
                }
                .buttonStyle(.borderless)
                .help("Listen, to find where to trim")

                Text("Keeping \(Timecode.short(range.start))–\(Timecode.short(range.end))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                if meeting.keptRange != nil {
                    Button("Keep Everything") {
                        meetingStore.modify(meetingID) { $0.keepEverything() }
                        draftRange = nil
                    }
                    .controlSize(.small)
                }

                Button("Cancel") { draftRange = nil }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)

                Button("Trim") {
                    meetingStore.modify(meetingID) { $0.keep(range) }
                    draftRange = nil
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func beginTrimming(_ meeting: Meeting) {
        draftRange = meeting.keptRange ?? KeptRange(start: 0, end: meeting.duration)
    }

    // MARK: - Header

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            if meeting.degraded == .diarization {
                Banner(
                    icon: "person.crop.circle.badge.exclamationmark",
                    tint: .orange,
                    title: "Speakers weren't identified",
                    message: "The transcript and its timestamps are complete, but "
                        + "every line is attributed to a single unknown speaker."
                )
            }

            if meeting.wasFastTranscribed == true {
                Banner(
                    icon: "hare",
                    tint: .orange,
                    title: "Transcribed in fast mode",
                    message: "This transcript was produced with chunked "
                        + "transcription, which drops some speech. Turn off "
                        + "\"Faster, less complete\" in Settings and transcribe "
                        + "again for a complete version."
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(meeting.speakers.enumerated()), id: \.element.id) { index, speaker in
                        SpeakerChip(
                            speaker: speaker,
                            color: SpeakerPalette.color(at: index)
                        ) { name in
                            rename(speaker, to: name)
                        } onAcceptSuggestion: {
                            acceptSuggestion(for: speaker)
                        }
                        .contextMenu {
                            mergeMenu(for: speaker, in: meeting)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func mergeMenu(for speaker: SpeakerLabel, in meeting: Meeting) -> some View {
        let others = meeting.speakers.filter { $0.id != speaker.id }
        if !others.isEmpty {
            Menu("Same Person As") {
                ForEach(others) { other in
                    Button(other.name) {
                        meetingStore.modify(meetingID) {
                            $0.mergeSpeaker(speaker.id, into: other.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transcript

    private func transcript(_ meeting: Meeting) -> some View {
        let trimmed = meeting.trimmedUtterances
        // Expanding shows the whole transcript again with the trimmed turns
        // dimmed in place, rather than in some separate list: where a line
        // falls relative to the rest is most of what tells you whether it
        // belongs in the meeting.
        let visible = isShowingTrimmed ? meeting.utterances : meeting.keptUtterances

        return ScrollViewReader { proxy in
            List {
                if !trimmed.before.isEmpty {
                    trimmedMarker(count: trimmed.before.count, edge: "before")
                }

                ForEach(Array(visible.enumerated()), id: \.element.id) { index, utterance in
                    UtteranceRow(
                        utterance: utterance,
                        speakerName: meeting.displayName(for: utterance.speakerId),
                        color: SpeakerPalette.color(for: utterance.speakerId, in: meeting),
                        isActive: isActive(utterance),
                        activeWordIndex: activeWordIndex(in: utterance),
                        searchMatches: find.matches.filter { $0.utteranceID == utterance.id },
                        currentSearchMatch: find.current?.utteranceID == utterance.id
                            ? find.current
                            : nil,
                        offersWordActions: !player.isPlaying,
                        otherSpeakers: meeting.speakers.filter { $0.id != utterance.speakerId },
                        canMergePrevious: index > 0,
                        canMergeNext: index + 1 < visible.count,
                        onSeek: { player.seek(to: utterance.start) },
                        onSeekTo: { player.seek(to: $0) },
                        onEdit: { text in
                            meetingStore.modify(meetingID) { $0.editText(of: utterance.id, to: text) }
                        },
                        onReassign: { speakerId in
                            meetingStore.modify(meetingID) { $0.reassign(utterance.id, to: speakerId) }
                        },
                        onSplit: { split(utterance) },
                        onSplitBefore: { wordIndex in
                            meetingStore.modify(meetingID) {
                                $0.splitUtterance(utterance.id, atWordIndex: wordIndex)
                            }
                        },
                        onMerge: { direction in
                            meetingStore.modify(meetingID) {
                                $0.mergeUtterance(utterance.id, with: direction)
                            }
                        },
                        onDelete: {
                            meetingStore.modify(meetingID) {
                                $0.removeUtterance(utterance.id)
                            }
                        }
                    )
                    .id(utterance.id)
                    .listRowSeparator(.hidden)
                    .opacity(meeting.keptRange?.keeps(utterance) == false ? 0.45 : 1)
                }

                if !trimmed.after.isEmpty {
                    trimmedMarker(count: trimmed.after.count, edge: "after")
                }
            }
            .listStyle(.plain)
            .onChange(of: find.current) { _, match in
                // Finding a match you then have to scroll to isn't finding it.
                guard let match else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(match.utteranceID, anchor: .center)
                }
            }
            .onChange(of: activeUtteranceID) { _, id in
                // Follows the playhead however it moved — playing, scrubbing
                // the waveform, or clicking a timestamp. Scrubbing to a moment
                // and not being shown what was said there is the whole point of
                // having the two side by side.
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    /// The row standing in for the turns a trim is hiding.
    ///
    /// It says how many, because "some lines are hidden" invites the question
    /// this is meant to answer, and a trim that swallowed forty lines is worth
    /// noticing before exporting.
    private func trimmedMarker(count: Int, edge: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isShowingTrimmed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isShowingTrimmed ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                Text("\(count) line\(count == 1 ? "" : "s") \(edge) the trim")
                Spacer()
                Text(isShowingTrimmed ? "Hide" : "Show")
                    .foregroundStyle(.tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    // MARK: - Playback state

    private var activeUtteranceID: UUID? {
        meeting?.utterances.first { isActive($0) }?.id
    }

    private func isActive(_ utterance: Utterance) -> Bool {
        player.isLoaded
            && player.currentTime >= utterance.start
            && player.currentTime < utterance.end
    }

    /// The word being spoken, where word timings survived the editing.
    private func activeWordIndex(in utterance: Utterance) -> Int? {
        guard let words = utterance.words else { return nil }
        return WordToken.activeIndex(in: words, at: player.currentTime)
    }

    /// Who speaks when, in the same colours as the chips above the transcript.
    // MARK: - Search and replace

    /// Replaces the match the find bar is sitting on.
    private func replaceCurrentMatch() {
        guard let match = find.current else { return }
        meetingStore.modify(meetingID) { $0.replace(match, with: find.replacement) }
    }

    private func replaceAllMatches() {
        let query = find.query
        let replacement = find.replacement
        meetingStore.modify(meetingID) { $0.replaceAll(query, with: replacement) }
    }

    private func speakerSpans(in meeting: Meeting) -> [SpeakerSpan] {
        meeting.utterances.map {
            SpeakerSpan(
                start: $0.start,
                end: $0.end,
                color: SpeakerPalette.color(for: $0.speakerId, in: meeting)
            )
        }
    }

    /// Computing the envelope reads the whole file, so it happens off the main
    /// actor and is cached; the scrubber simply appears when it is ready.
    private func loadWaveform() async {
        // Clear first: showing the previous meeting's envelope for a frame is
        // worse than showing none.
        waveform = nil
        guard let meeting, meeting.audioExists else { return }

        let loaded = await WaveformStore.waveform(for: meeting.id, audio: meeting.audioURL)
        // It arrives whenever the file has been read, which is abrupt if it
        // just snaps into place.
        withAnimation(.easeOut(duration: 0.35)) {
            waveform = loaded
        }
    }

    private func loadAudio() {
        guard let meeting, meeting.audioExists else { return }
        player.load(meeting.audioURL)
    }

    /// Points the meeting at a recording, then plays and draws it.
    ///
    /// The duration is read here rather than in the model because only this
    /// side can await it, and `AVURLAsset` rather than ``AudioSourcePreparer``
    /// because nothing is being transcribed: a video's audio track doesn't
    /// need extracting to a temporary file for `AVPlayer` to play it.
    private func attachAudio(at url: URL) async {
        let duration = try? await AVURLAsset(url: url).load(.duration).seconds

        meetingStore.modify(meetingID) { $0.attachAudio(at: url, duration: duration) }

        // The envelope is cached under the meeting's id, so a meeting being
        // pointed at a different file has to lose the one it had.
        WaveformStore.removeCache(for: meetingID)
        loadAudio()
        await loadWaveform()
    }

    // MARK: - Editing

    private func rename(_ speaker: SpeakerLabel, to name: String) {
        meetingStore.modify(meetingID) { $0.renameSpeaker(speaker.id, to: name) }
        speakerStore.enroll(name: name, embedding: speaker.embedding)
    }

    private func acceptSuggestion(for speaker: SpeakerLabel) {
        guard let suggestion = speaker.suggestion else { return }
        meetingStore.modify(meetingID) { $0.renameSpeaker(speaker.id, to: suggestion.name) }
        speakerStore.accept(suggestion, embedding: speaker.embedding)
    }

    /// Splits a turn at the word the playhead is on.
    ///
    /// Using the playhead avoids inventing a word-picking interaction: you hear
    /// where the turn actually changed, pause, and split there.
    private func split(_ utterance: Utterance) {
        guard let words = utterance.words,
              let index = words.firstIndex(where: { player.currentTime < $0.end }),
              index > 0
        else { return }
        meetingStore.modify(meetingID) { $0.splitUtterance(utterance.id, atWordIndex: index) }
    }

    // MARK: - Export

    private var exportable: ExportableMeeting? {
        guard meeting != nil else { return nil }
        return ExportableMeeting(id: meetingID) { format in
            export(format)
        }
    }

    private var exportFilename: String {
        guard let meeting, let exportFormat else { return "Transcript" }
        return "\(meeting.title).\(exportFormat.fileExtension)"
    }

    private func export(_ format: TranscriptExporter.Format) {
        guard let meeting else { return }
        exportFormat = format
        exportDocument = try? TranscriptDocument(meeting: meeting, format: format)
    }
}

// MARK: - Banner

private struct Banner: View {

    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The minimum is what matters. `fixedSize(vertical:)` above asks the
        // message for its full height at whatever width it is offered, and this
        // banner is offered a near-zero width during layout, at which the
        // sentence wraps to one word per line and reports a height of roughly
        // two thousand points. The split view then grows past the window and
        // takes the sidebar and the transcript out of view with it. Clamping
        // the proposal from below means the text is never measured at a width
        // it could not be drawn at.
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Playback bar

private struct PlaybackBar: View {

    let player: PlayerController
    let duration: TimeInterval

    /// Where the recording was cut for parallel transcription.
    let cuts: [TimeInterval]

    let waveform: Waveform?
    let speakers: [SpeakerSpan]

    /// False until the envelope has been read: there is nothing to drag
    /// handles across yet.
    let canTrim: Bool
    let onTrim: () -> Void
    let onRetranscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.playPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])

            Text(Timecode.short(player.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            ZStack {
                // A flat line holds the space while the envelope is computed,
                // so the controls don't jump when the waveform arrives. It has
                // to go once the bars are there, or it draws a stray rule
                // straight through them.
                if waveform?.isEmpty ?? true {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }

                if let waveform, !waveform.isEmpty {
                    WaveformScrubber(
                        waveform: waveform,
                        duration: duration,
                        currentTime: player.currentTime,
                        cuts: cuts,
                        speakers: speakers,
                        onSeek: { player.seek(to: $0) }
                    )
                    .transition(
                        .move(edge: .bottom).combined(with: .opacity)
                    )
                }
            }
            .frame(height: 40)
            .clipped()

            Text(Timecode.short(duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            // The two things you can do to the recording itself, as opposed to
            // the transcript of it.
            Menu {
                Button("Trim…", action: onTrim)
                    .disabled(!canTrim)
                Divider()
                Button("Transcribe Again…", action: onRetranscribe)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Trim or transcribe again")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
