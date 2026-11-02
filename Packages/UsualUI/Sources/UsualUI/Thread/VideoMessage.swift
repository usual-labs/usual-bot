import AVFoundation
import AVKit
import HermesKit
import SwiftUI

/// A video in a message: its first frame with its length, playing in place with the system's
/// controls (full screen among them) once you press play.
struct VideoMessage: View {
    let path: String

    @Environment(\.media) private var store
    @Environment(\.mediaProfile) private var profile
    @Environment(\.playbackScope) private var scope
    @State private var phase = PlayablePhase<VideoSummary>.loading

    private var playback: MediaPlayback { .shared }
    private var name: String { (path as NSString).lastPathComponent }
    private var key: String { MediaPlayback.key(scope: scope, profile: profile, path: path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch phase {
            case .loading:
                placeholder { ProgressView().controlSize(.small) }
                    .accessibilityLabel(Text("Getting video \(name)"))
            case .ready(let url, let video):
                let size = MediaLoading.displaySize(pixels: video.pixels, limit: CGSize(width: 420, height: 360))
                Group {
                    if playback.isCurrent(key) {
                        NativePlayer(player: playback.player)
                            #if os(macOS)
                                // AVPlayerView showed VoiceOver nothing (macOS 27), so the video
                                // speaks for itself. iPhone's AVKit controls are accessible.
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("Video \(name)"))
                                .accessibilityValue(Text(playback.isPlaying ? "Playing" : "Paused"))
                                .accessibilityAction { togglePlaying(url) }
                                .accessibilityAction(named: Text(playback.isPlaying ? "Pause" : "Play")) {
                                    togglePlaying(url)
                                }
                                .accessibilityAction(named: Text("Play from the start")) {
                                    playback.seek(to: 0)
                                    playback.play(url, key: key)
                                }
                            #endif
                    } else {
                        poster(url: url, video: video)
                    }
                }
                .aspectRatio(size, contentMode: .fit)
                .frame(maxWidth: size.width)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
            case .unplayable, .failed:
                placeholder {
                    Image(systemName: "video.slash").font(.system(size: 22)).foregroundStyle(Theme.secondaryInk)
                }
                .accessibilityLabel(Text("Video \(name)"))
            }
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let url = phase.url { SaveShareMenu(url: url, name: name) }
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .task(id: key) { await load() }
    }

    private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Theme.selection)
            .frame(width: 280, height: 158)
            .overlay(content: content)
    }

    private func poster(url: URL, video: VideoSummary) -> some View {
        Button {
            Task { await play(url) }
        } label: {
            ZStack {
                Color.black
                video.poster?.resizable().scaledToFit()
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .overlay(alignment: .bottomTrailing) {
                Text(PlayableText.time(video.duration))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
        }
        .buttonStyle(.clickable)
        .accessibilityLabel(Text("Play video"))
        .accessibilityValue(Text("\(name), \(PlayableText.spokenTime(video.duration))"))
        .help("Play \(name)")
    }

    private var problem: String? {
        switch phase {
        case .failed(let reason): reason
        case .unplayable: PlayableText.unplayable
        case .ready, .loading: playback.failedKey == key ? PlayableText.didNotPlay : nil
        }
    }

    private func load() async {
        if phase.url == nil { phase = .loading }
        do {
            guard let store, let profile else { throw GatewayError.disconnected }
            let url = try await store.playableFile(at: path, profile: profile)
            if let video = await VideoSummary.make(url) {
                phase = .ready(url, video)
            } else {
                phase = .unplayable(url)
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(PlayableText.problem(error))
        }
    }

    private func togglePlaying(_ url: URL) {
        if playback.isPlaying { playback.pause() } else { playback.play(url, key: key) }
    }

    private func play(_ url: URL) async {
        // The copy may have made way for newer ones since it loaded.
        let fresh = try? await store?.playableFile(at: path, profile: profile ?? "")
        playback.play(fresh ?? url, key: key)
    }
}

/// What shows before a video plays: a frame, its length and its shape.
struct VideoSummary: Equatable {
    let duration: TimeInterval
    let pixels: CGSize
    let posterImage: CGImage?

    var poster: Image? { posterImage.map { Image(decorative: $0, scale: 1) } }

    /// `nil` when this device can't play the file.
    static func make(_ url: URL) async -> VideoSummary? {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true, let time = try? await asset.load(.duration),
            time.isNumeric, time.seconds > 0
        else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 840, height: 720)
        let frame = try? await generator.image(at: CMTime(seconds: min(0.5, time.seconds / 2), preferredTimescale: 600))
        let pixels =
            frame.map { CGSize(width: $0.image.width, height: $0.image.height) } ?? CGSize(width: 16, height: 9)
        return VideoSummary(duration: time.seconds, pixels: pixels, posterImage: frame?.image)
    }
}

/// The system's own video player and controls, full screen included.
#if os(macOS)
    struct NativePlayer: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.controlsStyle = .inline
            view.showsFullScreenToggleButton = true
            view.player = player
            return view
        }

        func updateNSView(_ view: AVPlayerView, context: Context) {
            if view.player !== player { view.player = player }
        }
    }
#else
    struct NativePlayer: UIViewControllerRepresentable {
        let player: AVPlayer

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.exitsFullScreenWhenPlaybackEnds = true
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player { controller.player = player }
        }
    }
#endif
