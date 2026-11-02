import Compression
import CoreGraphics
import Foundation

/// The agent's screen as this app last heard it: 32-bit pixels, blue, green, red then an unused
/// byte, which is the pixel format `RFBClient` asks the server for.
public struct Framebuffer: Sendable, Equatable {
    public private(set) var width: Int
    public private(set) var height: Int
    var pixels: [UInt8]

    public init(width: Int, height: Int) {
        self.width = max(width, 0)
        self.height = max(height, 0)
        pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
    }

    /// The pixel at (`x`, `y`) as blue, green, red.
    public func pixel(x: Int, y: Int) -> [UInt8] {
        let at = (y * width + x) * 4
        return Array(pixels[at..<at + 3])
    }

    /// A copy of the screen to draw. `nil` while it has no size.
    public func image() -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The server changed the screen's size (DesktopSize): everything is sent again after it.
    mutating func resize(width: Int, height: Int) {
        self = Framebuffer(width: width, height: height)
    }

    /// Fills the part of the rectangle that's on screen with a blue, green, red colour.
    mutating func fill(x: Int, y: Int, width w: Int, height h: Int, bgr: (UInt8, UInt8, UInt8)) {
        let x0 = max(x, 0)
        let y0 = max(y, 0)
        let x1 = min(x + w, width)
        let y1 = min(y + h, height)
        guard x0 < x1, y0 < y1 else { return }
        for row in y0..<y1 {
            var at = (row * width + x0) * 4
            for _ in x0..<x1 {
                pixels[at] = bgr.0
                pixels[at + 1] = bgr.1
                pixels[at + 2] = bgr.2
                pixels[at + 3] = 255
                at += 4
            }
        }
    }

    @inline(__always) mutating func set(x: Int, y: Int, bgr: (UInt8, UInt8, UInt8)) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let at = (y * width + x) * 4
        pixels[at] = bgr.0
        pixels[at + 1] = bgr.1
        pixels[at + 2] = bgr.2
        pixels[at + 3] = 255
    }

    /// Raw encoding: `w`×`h` pixels of 4 bytes each, row by row.
    mutating func putRaw(x: Int, y: Int, width w: Int, height h: Int, bytes: ArraySlice<UInt8>) {
        var source = bytes.startIndex
        for row in 0..<h {
            for column in 0..<w {
                let px = x + column
                let py = y + row
                if px >= 0, px < width, py >= 0, py < height {
                    let at = (py * width + px) * 4
                    pixels[at] = bytes[source]
                    pixels[at + 1] = bytes[source + 1]
                    pixels[at + 2] = bytes[source + 2]
                    pixels[at + 3] = 255
                }
                source += 4
            }
        }
    }

    /// CopyRect: moves a rectangle already on screen.
    mutating func copy(fromX sx: Int, fromY sy: Int, toX x: Int, toY y: Int, width w: Int, height h: Int) {
        guard sx >= 0, sy >= 0, x >= 0, y >= 0, sx + w <= width, sy + h <= height, x + w <= width, y + h <= height
        else { return }
        let source = pixels
        // Rows are copied from a snapshot, so overlapping moves read what was there before.
        for row in 0..<h {
            let from = ((sy + row) * width + sx) * 4
            let to = ((y + row) * width + x) * 4
            pixels.replaceSubrange(to..<to + w * 4, with: source[from..<from + w * 4])
        }
    }
}

// MARK: - ZRLE

/// ZRLE (RFC 6143 §7.7.6): 64×64 tiles inside one zlib stream that lasts the whole connection.
/// Pixels are "CPIXELs", 3 bytes for this app's pixel format: blue, green, red.
struct ZRLEDecoder {
    enum Failure: Error { case truncated, unknownSubencoding(UInt8), inflate }

    private let inflater = Inflater()

    /// Decodes one rectangle's compressed bytes onto `framebuffer`.
    mutating func decode(
        _ compressed: [UInt8], x: Int, y: Int, width: Int, height: Int, into framebuffer: inout Framebuffer
    ) throws {
        var data = Cursor(bytes: try inflater.inflate(compressed))
        var tileY = 0
        while tileY < height {
            let th = min(64, height - tileY)
            var tileX = 0
            while tileX < width {
                let tw = min(64, width - tileX)
                try decodeTile(&data, x: x + tileX, y: y + tileY, width: tw, height: th, into: &framebuffer)
                tileX += 64
            }
            tileY += 64
        }
    }

    private func decodeTile(
        _ data: inout Cursor, x: Int, y: Int, width w: Int, height h: Int, into fb: inout Framebuffer
    ) throws {
        let kind = try data.byte()
        func put(_ index: Int, _ color: (UInt8, UInt8, UInt8)) {
            fb.set(x: x + index % w, y: y + index / w, bgr: color)
        }
        switch kind {
        case 0:
            for index in 0..<w * h { put(index, try data.cpixel()) }
        case 1:
            fb.fill(x: x, y: y, width: w, height: h, bgr: try data.cpixel())
        case 2...16:
            let palette = try (0..<Int(kind)).map { _ in try data.cpixel() }
            let bits = kind == 2 ? 1 : kind <= 4 ? 2 : 4
            for row in 0..<h {
                var byte: UInt8 = 0
                var left = 0
                for column in 0..<w {
                    if left == 0 {
                        byte = try data.byte()
                        left = 8
                    }
                    left -= bits
                    let index = Int(byte >> UInt8(left)) & ((1 << bits) - 1)
                    guard index < palette.count else { throw Failure.truncated }
                    put(row * w + column, palette[index])
                }
            }
        case 128:
            var index = 0
            while index < w * h {
                let color = try data.cpixel()
                let run = try data.runLength()
                for _ in 0..<min(run, w * h - index) {
                    put(index, color)
                    index += 1
                }
            }
        case 130...255:
            let palette = try (0..<Int(kind - 128)).map { _ in try data.cpixel() }
            var index = 0
            while index < w * h {
                let entry = try data.byte()
                let color = Int(entry & 0x7F)
                guard color < palette.count else { throw Failure.truncated }
                let run = entry & 0x80 == 0 ? 1 : try data.runLength()
                for _ in 0..<min(run, w * h - index) {
                    put(index, palette[color])
                    index += 1
                }
            }
        default:
            throw Failure.unknownSubencoding(kind)
        }
    }

    private struct Cursor {
        let bytes: [UInt8]
        var at = 0

        mutating func byte() throws -> UInt8 {
            guard at < bytes.count else { throw Failure.truncated }
            defer { at += 1 }
            return bytes[at]
        }

        mutating func cpixel() throws -> (UInt8, UInt8, UInt8) {
            guard at + 3 <= bytes.count else { throw Failure.truncated }
            defer { at += 3 }
            return (bytes[at], bytes[at + 1], bytes[at + 2])
        }

        /// 1 plus the sum of bytes, each 255 meaning another follows.
        mutating func runLength() throws -> Int {
            var run = 1
            while true {
                let next = try byte()
                run += Int(next)
                if next != 255 { return run }
            }
        }
    }
}

/// One zlib stream fed in pieces. Compression's `COMPRESSION_ZLIB` is raw deflate, so the two
/// zlib header bytes at the stream's start are skipped; the stream never ends, so there's no
/// checksum to read either.
final class Inflater: @unchecked Sendable {
    // @unchecked: only the screen's one reading task uses it.
    private let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    private var headerLeft = 2
    private var ready = false

    deinit {
        if ready { compression_stream_destroy(stream) }
        stream.deallocate()
    }

    func inflate(_ input: [UInt8]) throws -> [UInt8] {
        if !ready {
            guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
            else { throw ZRLEDecoder.Failure.inflate }
            ready = true
        }
        let skip = min(headerLeft, input.count)
        headerLeft -= skip
        let body = input.dropFirst(skip)
        guard !body.isEmpty else { return [] }
        var output: [UInt8] = []
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        try body.withUnsafeBufferPointer { source in
            stream.pointee.src_ptr = source.baseAddress!
            stream.pointee.src_size = source.count
            while true {
                let status = buffer.withUnsafeMutableBufferPointer { destination in
                    stream.pointee.dst_ptr = destination.baseAddress!
                    stream.pointee.dst_size = chunk
                    return compression_stream_process(stream, 0)
                }
                guard status != COMPRESSION_STATUS_ERROR else { throw ZRLEDecoder.Failure.inflate }
                let produced = chunk - stream.pointee.dst_size
                output.append(contentsOf: buffer[0..<produced])
                // Done once the input is used up and the last pass didn't fill the buffer.
                if status == COMPRESSION_STATUS_END || (stream.pointee.src_size == 0 && produced < chunk) { break }
            }
        }
        return output
    }
}
