import AVFoundation
import HermesKit
import SwiftUI
import UniformTypeIdentifiers

/// Where a voice memo, audio file or video stands.
enum PlayablePhase<Summary: Equatable>: Equatable {
    case loading
    /// Downloaded, with what the player shows before it plays.
    case ready(URL, Summary)
    /// On this device, but not in a form this device plays.
    case unplayable(URL)
    case failed(String)

    var url: URL? {
        switch self {
        case .ready(let url, _), .unplayable(let url): url
        case .loading, .failed: nil
        }
    }
}

enum PlayableText {
    /// What went wrong getting a file, and what to do.
    @MainActor static func problem(_ error: any Error) -> String {
        switch error as? GatewayError {
        case .disconnected, .unreachable, .timedOut:
            String(localized: "Not downloaded yet. Connect to your gateway to play it.")
        default:
            AppModel.describe(error)
        }
    }

    static let unplayable = String(
        localized: "Usual Bot can't play this type of file. Share it to open it in another app.")
    static let didNotPlay = String(localized: "Couldn't play this file. Share it to open it in another app.")

    /// `0:07`, `12:30`, `1:02:03`.
    static func time(_ seconds: TimeInterval) -> String {
        let duration = Duration.seconds(max(0, seconds.rounded(.down)))
        return seconds >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }

    /// "7 seconds", "2 minutes, 5 seconds", for VoiceOver.
    static func spokenTime(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds.rounded())).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

/// Share, and Save on the Mac, for a downloaded file.
struct SaveShareMenu: View {
    let url: URL
    let name: String

    #if os(macOS)
        @State private var saving: Data?
    #endif

    var body: some View {
        Menu {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            #if os(macOS)
                Button("Save…", systemImage: "square.and.arrow.down") { saving = try? Data(contentsOf: url) }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        #if os(macOS)
            // `.button` draws a bezel on the Mac.
            .menuStyle(.borderlessButton)
        #else
            .menuStyle(.button)
            .buttonStyle(.clickable)
        #endif
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Share or save \(name)")
        .accessibilityLabel(Text("Share or save \(name)"))
        #if os(macOS)
            .fileExporter(
                isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), item: saving ?? Data(),
                contentTypes: [UTType(filenameExtension: (name as NSString).pathExtension) ?? .data],
                defaultFilename: name
            ) { _ in }
        #endif
    }
}

/// How loud a stretch of audio is, for drawing a waveform; and how long it lasts.
struct AudioSummary: Equatable, Sendable {
    let duration: TimeInterval
    /// Loudness from 0 to 1 across the file, or none when the file can't be read that way.
    let levels: [Float]

    /// `nil` when this device can't play the file.
    static func make(_ url: URL) async -> AudioSummary? {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true, let time = try? await asset.load(.duration),
            time.isNumeric, time.seconds > 0
        else { return nil }
        let levels = await Task.detached(priority: .utility) { Self.levels(of: url, count: 64) }.value
        return AudioSummary(duration: time.seconds, levels: levels)
    }

    /// The loudest sample in each of `count` stretches, scaled so the loudest is 1.
    nonisolated static func levels(of url: URL, count: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return [] }
        let stretch = AVAudioFrameCount(max(1, file.length / AVAudioFramePosition(count)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: stretch) else { return [] }
        var levels: [Float] = []
        while levels.count < count, (try? file.read(into: buffer, frameCount: stretch)) != nil, buffer.frameLength > 0 {
            guard let samples = buffer.floatChannelData?[0] else { return [] }
            var loudest: Float = 0
            for index in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(samples[index])) }
            levels.append(loudest)
        }
        let top = levels.max() ?? 0
        return top > 0 ? levels.map { $0 / top } : []
    }
}
