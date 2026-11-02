#if DEBUG
    import Foundation

    /// A made-up Linux desktop for the demo's computer: a panel, a browser and a terminal.
    enum DemoDesktop {
        static func framebuffer(width: Int = 1440, height: Int = 900) -> Framebuffer {
            var fb = Framebuffer(width: width, height: height)
            // Wallpaper: dusk blue fading down.
            for row in 0..<height {
                let t = Double(row) / Double(height)
                fb.fill(
                    x: 0, y: row, width: width, height: 1,
                    bgr: (UInt8(150 - 60 * t), UInt8(90 - 40 * t), UInt8(40 - 20 * t)))
            }
            fb.fill(x: 0, y: 0, width: width, height: 28, bgr: (32, 30, 28))
            for (index, x) in [12, 44, 76].enumerated() {
                fb.fill(x: x, y: 6, width: 22, height: 16, bgr: index == 0 ? (230, 170, 80) : (120, 120, 120))
            }
            fb.fill(x: width - 92, y: 9, width: 80, height: 10, bgr: (200, 200, 200))
            window(&fb, x: 120, y: 80, width: 860, height: 600, title: (238, 238, 238), body: (255, 255, 255))
            // A page: address bar, heading, lines of text and a button.
            fb.fill(x: 140, y: 122, width: 820, height: 26, bgr: (245, 243, 241))
            fb.fill(x: 180, y: 190, width: 360, height: 22, bgr: (40, 40, 40))
            for line in 0..<9 {
                fb.fill(x: 180, y: 240 + line * 26, width: line % 3 == 2 ? 420 : 680, height: 10, bgr: (190, 190, 190))
            }
            fb.fill(x: 180, y: 500, width: 150, height: 40, bgr: (255, 123, 110))
            window(&fb, x: 760, y: 420, width: 600, height: 380, title: (60, 58, 56), body: (34, 30, 28))
            for line in 0..<10 {
                fb.fill(
                    x: 784, y: 470 + line * 28, width: [220, 380, 300, 460, 180][line % 5], height: 10,
                    bgr: line % 4 == 0 ? (140, 220, 120) : (210, 210, 210))
            }
            return fb
        }

        private static func window(
            _ fb: inout Framebuffer, x: Int, y: Int, width: Int, height: Int, title: (UInt8, UInt8, UInt8),
            body: (UInt8, UInt8, UInt8)
        ) {
            fb.fill(x: x + 6, y: y + 8, width: width, height: height, bgr: (20, 15, 10))
            fb.fill(x: x, y: y, width: width, height: height, bgr: body)
            fb.fill(x: x, y: y, width: width, height: 32, bgr: title)
            for dot in 0..<3 {
                fb.fill(x: x + width - 84 + dot * 26, y: y + 10, width: 12, height: 12, bgr: (150, 150, 150))
            }
        }
    }
#endif
