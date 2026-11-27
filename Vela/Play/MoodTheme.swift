import AppKit
import SwiftUI

/// Colors pulled from album art: an accent plus the two glows behind the glass.
struct MoodPalette: Equatable {
    let accent: UInt32
    let glowTop: UInt32
    let glowBottom: UInt32

    /// Turns a hue (0 to 1) into a palette: a bright accent and two deep glows.
    static func fromHue(_ hue: Double, second: Double? = nil, saturation: Double = 0.7) -> MoodPalette {
        let other = second ?? (hue + 0.12).truncatingRemainder(dividingBy: 1)
        return MoodPalette(
            accent: hsv(hue, max(saturation, 0.5), 0.95),
            glowTop: hsv(hue, 0.75, 0.38),
            glowBottom: hsv(other, 0.7, 0.3)
        )
    }

    /// Finds the album's strongest color.
    ///
    /// The art is shrunk to 24×24 pixels, and each colorful pixel votes for
    /// one of 12 hue buckets (grey, very dark and very pale pixels don't
    /// vote). The winning bucket's average hue becomes the accent; the
    /// runner-up colors the second glow. Black-and-white art returns nil,
    /// so the theme's own colors stay.
    static func from(_ image: NSImage) -> MoodPalette? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        var weight = [Double](repeating: 0, count: 12)
        var hueSum = [Double](repeating: 0, count: 12)
        var satSum = [Double](repeating: 0, count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let (h, s, v) = toHSV(Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
            guard s > 0.25, v > 0.2 else { continue }
            let vote = s * v
            let bucket = min(Int(h * 12), 11)
            weight[bucket] += vote
            hueSum[bucket] += h * vote
            satSum[bucket] += s * vote
        }
        let ranked = weight.indices.sorted { weight[$0] > weight[$1] }
        guard let best = ranked.first, weight[best] > 4 else { return nil }
        let hue = hueSum[best] / weight[best]
        let saturation = satSum[best] / weight[best]
        let runnerUp = ranked.dropFirst().first { weight[$0] > weight[best] * 0.25 }
        return fromHue(hue, second: runnerUp.map { hueSum[$0] / weight[$0] }, saturation: saturation)
    }

    static func toHSV(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> UInt32 {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let rgb: (Double, Double, Double)
        switch i {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        let (r, g, b) = rgb
        return (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
    }
}

/// Watches Spotify and tints Vela with the album art's colors while music
/// plays (Play ▸ Themes ▸ "Color Vela with the album…"). When the music
/// stops, Vela fades back to your theme. Lives invisibly in the window.
struct MoodThemeWatcher: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: watchKey) { await update() }
    }

    /// Changes whenever the song, play/pause or the switch changes.
    private var watchKey: String {
        let play = Play.shared
        return "\(play.isOn && play.settings.moodTheming)|\(store.spotify.isPlaying)|\(store.spotify.track?.artURL?.absoluteString ?? "")"
    }

    private func update() async {
        let play = Play.shared
        // A short pause, so skipping through songs doesn't flicker.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        guard play.isOn, play.settings.moodTheming, store.spotify.isPlaying,
              let url = store.spotify.track?.artURL else {
            Appearance.shared.mood = nil
            return
        }
        if let cached = MoodArtCache.shared.palettes[url] {
            Appearance.shared.mood = cached
            return
        }
        guard let download = try? await URLSession.shared.data(from: url), !Task.isCancelled,
              let image = NSImage(data: download.0) else { return }
        let palette = MoodPalette.from(image)
        MoodArtCache.shared.palettes[url] = palette
        Appearance.shared.mood = palette
    }
}

/// Album colors already worked out, so replaying a song is instant.
@MainActor
final class MoodArtCache {
    static let shared = MoodArtCache()
    var palettes: [URL: MoodPalette?] = [:]
}
