import HermesKit
import SwiftUI

/// Audio in a message. A voice memo (Hermes's text-to-speech) is a round play button, its
/// waveform, time and speed, and the transcript when Hermes sent the words; an audio file adds
/// its name above.
struct AudioMessage: View {
    let path: String
    let isVoice: Bool
    var transcript: String?

    @Environment(\.media) private var store
    @Environment(\.mediaProfile) private var profile
    @Environment(\.playbackScope) private var scope
    @State private var phase = PlayablePhase<AudioSummary>.loading
    @State private var showsTranscript = false
    @State private var speed: Float = 1

    private var playback: MediaPlayback { .shared }
    private var name: String { (path as NSString).lastPathComponent }
    private var key: String { MediaPlayback.key(scope: scope, profile: profile, path: path) }
    private var isCurrent: Bool { playback.isCurrent(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isVoice {
                Label(name, systemImage: "waveform")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 10) {
                playButton
                VStack(alignment: .leading, spacing: 2) {
                    Waveform(levels: summary?.levels ?? [], progress: progress, seek: seek)
                        .frame(height: 26)
                        .accessibilityElement()
                        .accessibilityLabel(Text(isVoice ? "Voice memo position" : "Position in \(name)"))
                        .accessibilityValue(Text(positionDescription))
                        .accessibilityAdjustableAction { direction in
                            guard let duration = summary?.duration, isCurrent else { return }
                            let step: TimeInterval = direction == .increment ? 5 : -5
                            playback.seek(to: min(duration, playback.elapsed + step))
                        }
                    HStack(spacing: 6) {
                        Text(timeText)
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(Theme.secondaryInk)
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        if isVoice, summary != nil { speedButton }
                        if let url = phase.url { SaveShareMenu(url: url, name: name) }
                    }
                }
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let transcript { transcriptView(transcript) }
        }
        .frame(width: 280, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(isVoice ? "Voice memo" : "Audio \(name)"))
        .task(id: key) { await load() }
    }

    // MARK: - Parts

    private var playButton: some View {
        Button {
            Task { await togglePlay() }
        } label: {
            ZStack {
                Circle().fill(Theme.primary)
                switch phase {
                case .loading:
                    ProgressView().controlSize(.small).tint(Theme.primaryInk)
                case .failed:
                    Image(systemName: "arrow.clockwise")
                case .unplayable:
                    Image(systemName: "speaker.slash.fill")
                case .ready:
                    Image(systemName: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.primaryInk)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.clickable)
        .disabled(phase == .loading || phase.isUnplayable)
        .accessibilityLabel(Text(playLabel))
        .help(playLabel)
    }

    private var playLabel: String {
        switch phase {
        case .loading:
            isVoice ? String(localized: "Preparing voice memo") : String(localized: "Getting \(name)")
        case .failed: String(localized: "Try Again")
        case .unplayable: String(localized: "Can't play \(name)")
        case .ready where isCurrent && playback.isPlaying:
            isVoice ? String(localized: "Pause voice memo") : String(localized: "Pause \(name)")
        case .ready:
            isVoice ? String(localized: "Play voice memo") : String(localized: "Play \(name)")
        }
    }

    private var speedButton: some View {
        Button {
            speed = speed == 1 ? 1.5 : speed == 1.5 ? 2 : 1
            if isCurrent { playback.setRate(speed) }
        } label: {
            Text(speedText)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondaryInk)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(Theme.selection, in: Capsule())
        }
        .buttonStyle(.clickable)
        .accessibilityLabel(Text("Playback speed \(speedText)"))
        .help("Playback speed")
    }

    private var speedText: String { speed == 1.5 ? "1.5×" : "\(Int(speed))×" }

    private func transcriptView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(showsTranscript ? "Hide transcript" : "Show transcript") {
                withAnimation(.easeOut(duration: 0.15)) { showsTranscript.toggle() }
            }
            .buttonStyle(.clickable)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.secondaryInk)
            if showsTranscript {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - State

    private var summary: AudioSummary? {
        if case .ready(_, let summary) = phase { summary } else { nil }
    }

    private var problem: String? {
        switch phase {
        case .failed(let reason): reason
        case .unplayable: PlayableText.unplayable
        case .ready, .loading: playback.failedKey == key ? PlayableText.didNotPlay : nil
        }
    }

    private var progress: Double {
        guard isCurrent, let duration = summary?.duration, duration > 0 else { return 0 }
        return min(1, playback.elapsed / duration)
    }

    /// The time played while it plays, its length otherwise.
    private var timeText: String {
        guard let duration = summary?.duration else { return "–:––" }
        return PlayableText.time(
            isCurrent && (playback.isPlaying || playback.elapsed > 0) ? playback.elapsed : duration)
    }

    private var positionDescription: String {
        guard let duration = summary?.duration else { return "" }
        let at = isCurrent ? playback.elapsed : 0
        return String(localized: "\(PlayableText.spokenTime(at)) of \(PlayableText.spokenTime(duration))")
    }

    // MARK: - Actions

    private func load() async {
        if phase.url == nil { phase = .loading }
        do {
            guard let store, let profile else { throw GatewayError.disconnected }
            let url = try await store.playableFile(at: path, profile: profile)
            if let summary = await AudioSummary.make(url) {
                phase = .ready(url, summary)
            } else {
                phase = .unplayable(url)
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(PlayableText.problem(error))
        }
    }

    private func togglePlay() async {
        switch phase {
        case .failed:
            await load()
        case .ready(let url, _):
            if isCurrent, playback.isPlaying {
                playback.pause()
            } else if isCurrent {
                playback.play(url, key: key, at: speed)
            } else {
                // The copy may have made way for newer ones since it loaded.
                let fresh = try? await store?.playableFile(at: path, profile: profile ?? "")
                playback.play(fresh ?? url, key: key, at: speed)
            }
        case .loading, .unplayable:
            break
        }
    }

    /// Jumps to `fraction` of the way through, starting it first if another file was playing.
    private func seek(_ fraction: Double) {
        guard case .ready(let url, let summary) = phase else { return }
        if !isCurrent { playback.play(url, key: key, at: speed) }
        playback.seek(to: fraction * summary.duration)
    }
}

extension PlayablePhase {
    var isUnplayable: Bool {
        if case .unplayable = self { true } else { false }
    }
}

/// Bars for how loud each part is, filled up to `progress`. Tap or drag to move through it.
struct Waveform: View {
    let levels: [Float]
    let progress: Double
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, Int((geometry.size.width + 2) / 4))
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Double(index) / Double(count) < progress ? Theme.ink : Theme.secondaryInk.opacity(0.35))
                        .frame(width: 2, height: max(3, geometry.size.height * CGFloat(level(index, of: count))))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in seek(fraction(point.x, geometry.size.width)) }
            .gesture(
                DragGesture(minimumDistance: 6).onChanged { drag in
                    seek(fraction(drag.location.x, geometry.size.width))
                })
        }
    }

    /// Without levels (a type this device can't read that way), a flat line.
    private func level(_ index: Int, of count: Int) -> Float {
        guard !levels.isEmpty else { return 0.15 }
        let position = min(levels.count - 1, index * levels.count / count)
        return max(0.12, levels[position])
    }

    private func fraction(_ x: CGFloat, _ width: CGFloat) -> Double {
        width > 0 ? min(1, max(0, Double(x / width))) : 0
    }
}
