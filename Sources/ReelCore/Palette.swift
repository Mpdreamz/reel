import CoreGraphics
import Foundation

/// A GIF's colours cut down to a few (`Set GifColors`): one palette for every frame, so a colour does not shift from
/// frame to frame, made by median cut over the frames' colours, and each pixel drawn in its nearest palette colour.
/// Fewer colours compress better; ImageIO would otherwise pick up to 256 for every frame.
struct Palette {
    struct Color: Equatable {
        var r: UInt8, g: UInt8, b: UInt8
    }

    let colors: [Color]

    /// At most `count` colours for `images`, from a histogram of their colours at 5 bits a channel.
    init(for images: [CGImage], count: Int) {
        var histogram = [Int](repeating: 0, count: 1 << 15)
        // The colours themselves, summed in each bin, so a palette colour is the real average and not the bin's middle.
        var sums = [(r: Int, g: Int, b: Int)](repeating: (0, 0, 0), count: 1 << 15)
        for image in images {
            guard let pixels = Pixels(image) else { continue }
            // About 100 000 pixels an image is plenty to know its colours.
            let step = max(1, pixels.count / 100_000)
            for index in stride(from: 0, to: pixels.count, by: step) {
                let color = pixels[index], key = Self.key(color)
                histogram[key] += 1
                sums[key].r += Int(color.r)
                sums[key].g += Int(color.g)
                sums[key].b += Int(color.b)
            }
        }
        let present = histogram.indices.filter { histogram[$0] > 0 }
        var boxes = [Box(keys: present, histogram: histogram)]
        while boxes.count < count, let widest = boxes.indices.filter({ boxes[$0].keys.count > 1 })
            .max(by: { boxes[$0].spread < boxes[$1].spread })
        {
            let (low, high) = boxes[widest].split(histogram)
            boxes[widest] = low
            boxes.append(high)
        }
        colors = boxes.filter { !$0.keys.isEmpty }.map { $0.average(histogram, sums) }
    }

    /// `image` drawn in the palette's colours alone.
    func apply(to image: CGImage) -> CGImage? {
        guard var pixels = Pixels(image) else { return nil }
        // The nearest colour of each 5-bit key, worked out the first time it is needed.
        var nearest = [Int32](repeating: -1, count: 1 << 15)
        for index in 0 ..< pixels.count {
            let key = Self.key(pixels[index])
            if nearest[key] < 0 { nearest[key] = Int32(closest(to: Self.center(of: key))) }
            pixels[index] = colors[Int(nearest[key])]
        }
        return pixels.image()
    }

    private func closest(to color: Color) -> Int {
        var best = 0, bestDistance = Int.max
        for (index, candidate) in colors.enumerated() {
            let dr = Int(candidate.r) - Int(color.r), dg = Int(candidate.g) - Int(color.g)
            let db = Int(candidate.b) - Int(color.b)
            // Weighted the way the eye weighs the channels.
            let distance = 3 * dr * dr + 4 * dg * dg + 2 * db * db
            if distance < bestDistance { (best, bestDistance) = (index, distance) }
        }
        return best
    }

    static func key(_ color: Color) -> Int {
        Int(color.r >> 3) << 10 | Int(color.g >> 3) << 5 | Int(color.b >> 3)
    }

    static func center(of key: Int) -> Color {
        func channel(_ shift: Int) -> UInt8 {
            UInt8((key >> shift) & 31) << 3 | 4
        }
        return Color(r: channel(10), g: channel(5), b: channel(0))
    }

    /// Keys of the histogram, cut in two along the channel they spread most in, at the median by pixel count.
    private struct Box {
        var keys: [Int]
        var spread: Int
        var channel: Int

        init(keys: [Int], histogram: [Int]) {
            self.keys = keys
            var spread = 0, channel = 0
            for shift in [10, 5, 0] {
                let values = keys.map { ($0 >> shift) & 31 }
                let range = (values.max() ?? 0) - (values.min() ?? 0)
                if range > spread { (spread, channel) = (range, shift) }
            }
            // Wide boxes with many pixels first: they show the most.
            let weight = keys.reduce(0) { $0 + histogram[$1] }
            self.spread = spread * Int(Double(weight).squareRoot())
            self.channel = channel
        }

        func split(_ histogram: [Int]) -> (Box, Box) {
            let sorted = keys.sorted { ($0 >> channel) & 31 < ($1 >> channel) & 31 }
            let total = sorted.reduce(0) { $0 + histogram[$1] }
            var running = 0, cut = 1
            for (index, key) in sorted.enumerated() {
                running += histogram[key]
                if running * 2 >= total {
                    cut = min(max(1, index + 1), sorted.count - 1)
                    break
                }
            }
            return (
                Box(keys: Array(sorted[..<cut]), histogram: histogram),
                Box(keys: Array(sorted[cut...]), histogram: histogram)
            )
        }

        func average(_ histogram: [Int], _ sums: [(r: Int, g: Int, b: Int)]) -> Color {
            var r = 0, g = 0, b = 0, total = 0
            for key in keys {
                r += sums[key].r
                g += sums[key].g
                b += sums[key].b
                total += histogram[key]
            }
            guard total > 0 else { return Color(r: 0, g: 0, b: 0) }
            return Color(r: UInt8(r / total), g: UInt8(g / total), b: UInt8(b / total))
        }
    }
}

/// An image's pixels as opaque RGBA, 8 bits a channel.
private struct Pixels {
    let width: Int, height: Int
    private var bytes: [UInt8]

    var count: Int {
        width * height
    }

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
    }

    subscript(index: Int) -> Palette.Color {
        get { Palette.Color(r: bytes[index * 4], g: bytes[index * 4 + 1], b: bytes[index * 4 + 2]) }
        set {
            bytes[index * 4] = newValue.r
            bytes[index * 4 + 1] = newValue.g
            bytes[index * 4 + 2] = newValue.b
        }
    }

    func image() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
