import Foundation

/// Joins 16-bit audio that arrives in pieces cut anywhere. Hermes forwards the provider's HTTP
/// chunks as they come, and they're often an odd number of bytes; read one on its own and its
/// last half-sample is lost, and every sample after it plays a byte out, as full-scale noise.
struct PCMJoiner {
    private var leftover: UInt8?

    /// The whole samples so far; a trailing half-sample waits for the next piece.
    mutating func add(_ data: Data) -> Data {
        var bytes = Data()
        bytes.reserveCapacity(data.count + 1)
        if let leftover { bytes.append(leftover) }
        bytes.append(data)
        if bytes.count.isMultiple(of: 2) {
            leftover = nil
        } else {
            leftover = bytes.removeLast()
        }
        return bytes
    }

    /// A new utterance: nothing carries over.
    mutating func reset() { leftover = nil }
}

/// Whether 16-bit audio sounds like a voice: a guard so a stream that's garbled anyway can't
/// play loud noise into someone's ear. A voice changes little from one sample to the next; noise
/// doesn't, so neighbouring samples barely correlate.
public enum PCMCheck {
    public enum Verdict: Sendable, Equatable {
        case speech
        case noise
        /// Too quiet to tell, and too quiet to hurt.
        case quiet
    }

    /// About −20 dB: quieter than this can't hurt, so it isn't judged.
    static let loud = 0.1
    /// Speech correlates at about 0.9 and noise near 0.
    static let voice = 0.5

    public static func judge(pcm16 data: Data) -> Verdict {
        judge(
            stride(from: data.startIndex, to: data.endIndex - 1, by: 2).map {
                Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)
            })
    }

    static func judge(_ samples: [Int16]) -> Verdict {
        guard samples.count > 1 else { return .quiet }
        var power = 0.0
        var neighbours = 0.0
        var previous = Double(samples[0]) / 32_768
        power += previous * previous
        for sample in samples.dropFirst() {
            let value = Double(sample) / 32_768
            power += value * value
            neighbours += value * previous
            previous = value
        }
        guard (power / Double(samples.count)).squareRoot() >= loud else { return .quiet }
        return neighbours / power >= voice ? .speech : .noise
    }
}
