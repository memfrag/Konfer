//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// A stretch of the recording attributed to one speaker, for colouring.
struct SpeakerSpan: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let color: Color
}

/// A scrubbable amplitude view of the whole recording.
///
/// The only playback control: click or drag anywhere to seek.
///
/// Bars are coloured by who is speaking, in the same colours as the chips above
/// the transcript, so the shape of the meeting reads at a glance — who talks
/// most, where the long stretches are, who only chips in. Yellow lines mark
/// where the recording was cut for parallel transcription; a cut sitting on a
/// loud passage rather than in a gap is the thing this makes visible.
struct WaveformScrubber: View {

    let waveform: Waveform
    let duration: TimeInterval
    let currentTime: TimeInterval

    /// Where the recording was cut for transcription.
    let cuts: [TimeInterval]

    /// Who is speaking when, so the shape of the meeting is legible at a
    /// glance: who talks most, who interrupts, where the long monologues are.
    /// Colours match the speaker chips above the transcript.
    let speakers: [SpeakerSpan]

    let onSeek: (TimeInterval) -> Void

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let progress = duration > 0 ? min(currentTime / duration, 1) : 0

            ZStack(alignment: .leading) {
                Canvas { context, canvasSize in
                    draw(in: &context, size: canvasSize, progress: progress)
                }

                ForEach(cuts, id: \.self) { cut in
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 1)
                        .offset(x: size.width * cut / max(duration, 1))
                        .help("Transcribed in separate parts, split here at \(Timecode.short(cut))")
                }

                // The playhead. With no slider beneath it any more, this is the
                // only thing showing exactly where playback is.
                Rectangle()
                    .fill(.primary)
                    .frame(width: 1.5)
                    .offset(x: size.width * progress)
                    .shadow(radius: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seek(to: value.location.x, width: size.width)
                    }
            )
        }
        .frame(height: 40)
    }

    private func seek(to x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = min(max(x / width, 0), 1)
        onSeek(duration * fraction)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, progress: Double) {
        guard !waveform.isEmpty, size.width > 0 else { return }

        let step = barWidth + barGap
        let barCount = max(1, Int(size.width / step))
        let midY = size.height / 2
        let playedX = size.width * progress

        // Speakers are in transcript order, and bars are drawn left to right,
        // so a cursor walks them together instead of searching per bar.
        var speakerIndex = 0

        for index in 0..<barCount {
            // Each bar summarises the peaks that fall inside it, so the shape
            // stays honest at any width rather than sampling every nth value.
            let lower = index * waveform.peaks.count / barCount
            let upper = max(lower + 1, (index + 1) * waveform.peaks.count / barCount)
            let peak = waveform.peaks[lower..<min(upper, waveform.peaks.count)].max() ?? 0

            let x = CGFloat(index) * step
            let time = duration * Double(index) / Double(barCount)
            let color = speakerColor(at: time, cursor: &speakerIndex)

            let height = max(1.5, CGFloat(peak) * size.height)
            let bar = CGRect(
                x: x,
                y: midY - height / 2,
                width: barWidth,
                height: height
            )
            // Colour carries the speaker; opacity carries progress, so neither
            // signal has to give way to the other.
            context.fill(
                Path(roundedRect: bar, cornerRadius: barWidth / 2),
                with: .color(color.opacity(x <= playedX ? 1 : 0.4))
            )
        }
    }

    /// The colour of whoever is speaking at `time`, or grey in the gaps.
    private func speakerColor(at time: TimeInterval, cursor: inout Int) -> Color {
        while cursor < speakers.count, speakers[cursor].end < time {
            cursor += 1
        }
        guard cursor < speakers.count else { return .secondary }
        let span = speakers[cursor]
        return time >= span.start ? span.color : .secondary
    }
}
