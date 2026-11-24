import SwiftUI

/// The mic in the message box: tap to dictate, tap again to stop. While the gateway transcribes,
/// a ring turns around it; in gateway dictation's last 15 seconds a second ring runs down.
struct MicButton: View {
    let dictation: Dictation
    /// Gateway dictation is chosen: said in the label, not drawn.
    var throughGateway = false
    let start: () -> Void
    @Environment(\.composerButtonSize) private var size

    var body: some View {
        Button {
            if dictation.isListening { dictation.stop() } else { start() }
        } label: {
            ComposerGlyph(
                systemImage: dictation.isActive ? "stop.fill" : "mic.fill", scale: dictation.isActive ? 11 : 13)
        }
        .composerGlass()
        // The ✕ beside the waveform cancels, so tapping Stop twice can't throw the recording away.
        .disabled(dictation.state == .transcribing)
        .overlay {
            if dictation.state == .transcribing { TranscribingRing(size: size) }
            if let secondsLeft = dictation.secondsLeft {
                Circle()
                    .trim(from: 0, to: secondsLeft / Dictation.countdown)
                    .stroke(Theme.ink.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 6, height: size + 6)
                    .animation(.linear(duration: 0.25), value: secondsLeft)
                    .allowsHitTesting(false)
            }
        }
        .help(label)
        .accessibilityLabel(Text(label))
    }

    private var label: String {
        if dictation.state == .transcribing { return String(localized: "Transcribing") }
        if dictation.isListening { return String(localized: "Stop dictation") }
        return throughGateway ? String(localized: "Dictate through your gateway") : String(localized: "Dictate")
    }
}

/// Around the mic while the recording turns into words.
private struct TranscribingRing: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ink.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Theme.ink.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(turned ? 270 : -90))
        }
        .frame(width: size + 6, height: size + 6)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { turned = true }
        }
    }
}

/// The ✕ that starts the row under the words while you dictate: the recording goes, and so do
/// the words it put in the box.
struct DictationCancelButton: View {
    let dictation: Dictation

    var body: some View {
        Button {
            dictation.cancel()
        } label: {
            ComposerGlyph(systemImage: "xmark", scale: 12)
        }
        .composerGlass()
        .help(label)
        .accessibilityLabel(Text(label))
    }

    private var label: String {
        dictation.state == .transcribing
            ? String(localized: "Cancel transcription") : String(localized: "Cancel dictation")
    }
}

/// How loud you are, as bars between the ✕ and Stop while you dictate: the newest on the right,
/// and quiet as a row of dots. It holds still and fades while the recording turns into words.
struct DictationWaveform: View {
    let levels: [Double]
    var transcribing = false
    @Environment(\.composerButtonSize) private var size

    static let bar: CGFloat = 3
    static let gap: CGFloat = 2.5

    var body: some View {
        Canvas { context, canvas in
            let step = Self.bar + Self.gap
            let bars = Self.bars(levels, count: Int((canvas.width + Self.gap) / step))
            var x = canvas.width - CGFloat(bars.count) * step + Self.gap
            for level in bars {
                let height = max(Self.bar, canvas.height * level)
                let rect = CGRect(x: x, y: (canvas.height - height) / 2, width: Self.bar, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: Self.bar / 2), with: .color(Theme.ink))
                x += step
            }
        }
        .frame(height: size * 0.7)
        .opacity(transcribing ? 0.3 : 0.8)
        .animation(.easeOut(duration: 0.2), value: transcribing)
        .accessibilityElement()
        .accessibilityLabel(Text(transcribing ? "Transcribing" : "Listening"))
    }

    /// The newest `count` levels, oldest first, after silence while fewer have come.
    nonisolated static func bars(_ levels: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let heard = levels.suffix(count)
        return Array(repeating: 0, count: count - heard.count) + heard
    }
}
