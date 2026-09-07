//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// A waveform with two handles, for choosing the stretch that counts.
///
/// Deliberately not ``WaveformScrubber`` with a mode flag. That view answers
/// "what happened, and where am I in it" — speaker colours, slice cuts,
/// progress. This one answers "which part of this do I want", and the two
/// share only the shape of the bars. A single view doing both would spend most
/// of its body deciding which it was being.
///
/// Handles behave like QuickTime's: drag either end, and the audio outside
/// dims rather than disappearing, so the thing you are cutting away stays
/// visible while you decide.
struct TrimmableWaveform: View {

    let waveform: Waveform
    let duration: TimeInterval
    let currentTime: TimeInterval

    @Binding var range: KeptRange

    let onSeek: (TimeInterval) -> Void

    /// Which handle a drag has taken hold of, so it keeps it until let go —
    /// without this, dragging one handle past the other hands the gesture to
    /// its neighbour halfway through.
    @State private var dragging: Handle?

    private enum Handle { case start, end }

    private let barWidth: CGFloat = 2
    private let barGap: CGFloat = 1
    private let handleWidth: CGFloat = 10
    private let edgeThickness: CGFloat = 2
    private let height: CGFloat = 72

    /// A trim narrower than this is almost certainly a slip, and one of zero
    /// length would give the pipeline nothing to transcribe.
    private static let minimumDuration: TimeInterval = 1

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startX = x(for: range.start, in: width)
            let endX = x(for: range.end, in: width)

            ZStack(alignment: .leading) {
                Canvas { context, size in
                    draw(in: &context, size: size, startX: startX, endX: endX)
                }

                // The playhead, drawn over the dimming so it stays findable
                // when it wanders outside the selection.
                Rectangle()
                    .fill(.primary)
                    .frame(width: 1.5)
                    .offset(x: x(for: currentTime, in: width))
                    .shadow(radius: 1)

                selectionFrame(from: startX, to: endX, height: geometry.size.height)
                handle(at: startX)
                handle(at: endX)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        drag(to: value.location.x, width: width, startX: startX, endX: endX)
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
        .frame(height: height)
    }

    // MARK: - Handles

    /// The rules joining the two handles along the top and bottom edges.
    ///
    /// QuickTime's shape, and worth copying rather than inventing something:
    /// with only the uprights the eye reads two independent markers that
    /// happen to be nearby, and with the frame closed it reads one stretch
    /// lifted out of the whole. It also makes a very narrow selection legible,
    /// where two handles alone would just look like one thick handle.
    private func selectionFrame(from startX: CGFloat, to endX: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(.tint).frame(height: edgeThickness)
            Spacer(minLength: 0)
            Rectangle().fill(.tint).frame(height: edgeThickness)
        }
        .frame(width: max(0, endX - startX), height: height)
        .offset(x: startX)
    }

    private func handle(at x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.tint)
            .frame(width: handleWidth, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: height * 0.35)
            }
            .offset(x: x - handleWidth / 2)
    }

    // MARK: - Dragging

    /// Grabs whichever handle is nearer on the first event of a drag, then
    /// keeps it. A click in the middle seeks instead, so the waveform is still
    /// the way you listen to what you are about to cut.
    private func drag(to x: CGFloat, width: CGFloat, startX: CGFloat, endX: CGFloat) {
        guard width > 0 else { return }

        if dragging == nil {
            let grabRadius = handleWidth * 2
            let toStart = abs(x - startX)
            let toEnd = abs(x - endX)
            if min(toStart, toEnd) <= grabRadius {
                dragging = toStart <= toEnd ? .start : .end
            } else {
                onSeek(time(for: x, in: width))
                return
            }
        }

        let moment = time(for: x, in: width)
        switch dragging {
        case .start:
            range = KeptRange(
                start: min(moment, range.end - Self.minimumDuration),
                end: range.end
            )
        case .end:
            range = KeptRange(
                start: range.start,
                end: max(moment, range.start + Self.minimumDuration)
            )
        case nil:
            break
        }
    }

    private func time(for x: CGFloat, in width: CGFloat) -> TimeInterval {
        duration * min(max(x / width, 0), 1)
    }

    private func x(for time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return width * min(max(time / duration, 0), 1)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, startX: CGFloat, endX: CGFloat) {
        guard !waveform.isEmpty, size.width > 0 else { return }

        let step = barWidth + barGap
        let barCount = max(1, Int(size.width / step))
        let midY = size.height / 2

        for index in 0..<barCount {
            // Each bar summarises the peaks that fall inside it, so the shape
            // stays honest at any width rather than sampling every nth value.
            let lower = index * waveform.peaks.count / barCount
            let upper = max(lower + 1, (index + 1) * waveform.peaks.count / barCount)
            let peak = waveform.peaks[lower..<min(upper, waveform.peaks.count)].max() ?? 0

            let x = CGFloat(index) * step
            let isKept = x >= startX && x <= endX
            let barHeight = max(1.5, CGFloat(peak) * size.height)

            context.fill(
                Path(roundedRect: CGRect(
                    x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight
                ), cornerRadius: barWidth / 2),
                with: .color(isKept ? .accentColor : .secondary.opacity(0.25))
            )
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var range = KeptRange(start: 20, end: 80)

    TrimmableWaveform(
        waveform: Waveform(peaks: (0..<400).map { index in
            Float(abs(sin(Double(index) / 9)) * 0.8 + 0.05)
        }),
        duration: 100,
        currentTime: 35,
        range: $range,
        onSeek: { _ in }
    )
    .padding()
}
#endif
