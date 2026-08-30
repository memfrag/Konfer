//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// A transcript: speaker-tagged, timestamped, editable, and playable.
struct MeetingPane: View {

    let meetingID: UUID

    @Environment(MeetingStore.self) private var meetingStore
    @Environment(SpeakerStore.self) private var speakerStore

    @State private var player = PlayerController()
    @State private var waveform: Waveform?
    @State private var exportFormat: TranscriptExporter.Format?
    @State private var exportDocument: TranscriptDocument?

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
    }

    // MARK: - Content

    private func content(_ meeting: Meeting) -> some View {
        VStack(spacing: 0) {
            header(meeting)
            Divider()
            transcript(meeting)
            if player.isLoaded {
                Divider()
                PlaybackBar(
                    player: player,
                    duration: meeting.duration,
                    cuts: meeting.sliceCuts ?? [],
                    waveform: waveform,
                    speakers: speakerSpans(in: meeting)
                )
            }
        }
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

            if !meeting.audioExists {
                Banner(
                    icon: "waveform.slash",
                    tint: .secondary,
                    title: "Recording not found",
                    message: "The audio file has moved or been deleted, so playback "
                        + "is unavailable. Everything else still works."
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
        ScrollViewReader { proxy in
            List {
                ForEach(Array(meeting.utterances.enumerated()), id: \.element.id) { index, utterance in
                    UtteranceRow(
                        utterance: utterance,
                        speakerName: meeting.displayName(for: utterance.speakerId),
                        color: SpeakerPalette.color(for: utterance.speakerId, in: meeting),
                        isActive: isActive(utterance),
                        activeWordIndex: activeWordIndex(in: utterance),
                        otherSpeakers: meeting.speakers.filter { $0.id != utterance.speakerId },
                        canMergePrevious: index > 0,
                        canMergeNext: index + 1 < meeting.utterances.count,
                        onSeek: { player.seek(to: utterance.start) },
                        onSeekTo: { player.seek(to: $0) },
                        onEdit: { text in
                            meetingStore.modify(meetingID) { $0.editText(of: utterance.id, to: text) }
                        },
                        onReassign: { speakerId in
                            meetingStore.modify(meetingID) { $0.reassign(utterance.id, to: speakerId) }
                        },
                        onSplit: { split(utterance) },
                        onMerge: { direction in
                            meetingStore.modify(meetingID) {
                                $0.mergeUtterance(utterance.id, with: direction)
                            }
                        }
                    )
                    .id(utterance.id)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .onChange(of: activeUtteranceID) { _, id in
                guard player.isPlaying, let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
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
        return words.firstIndex { player.currentTime >= $0.start && player.currentTime < $0.end }
    }

    /// Who speaks when, in the same colours as the chips above the transcript.
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
        guard let meeting, meeting.audioExists else { return }
        waveform = await WaveformStore.waveform(for: meeting.id, audio: meeting.audioURL)
    }

    private func loadAudio() {
        guard let meeting, meeting.audioExists else { return }
        player.load(meeting.audioURL)
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
            Spacer()
        }
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

            if let waveform, !waveform.isEmpty {
                WaveformScrubber(
                    waveform: waveform,
                    duration: duration,
                    currentTime: player.currentTime,
                    cuts: cuts,
                    speakers: speakers,
                    onSeek: { player.seek(to: $0) }
                )
            } else {
                // The envelope is still being computed, or the audio is gone.
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
            }

            Text(Timecode.short(duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
