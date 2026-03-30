import SwiftUI

extension Color {
    /// Attempt to parse a CSS color string into a SwiftUI Color.
    /// Supports: #rgb, #rrggbb, #rrggbbaa, rgb(...), rgba(...)
    /// Returns nil for unsupported values (e.g. named colors, var(), keywords).
    init?(cssString raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        if s.hasPrefix("#") {
            guard let color = Color(hexString: s) else { return nil }
            self = color
        } else if s.lowercased().hasPrefix("rgb") {
            guard let color = Color(rgbString: s) else { return nil }
            self = color
        } else {
            return nil
        }
    }

    /// Output a CSS color string.
    /// Uses rgba() when alpha < 1, #rrggbb otherwise.
    var cssString: String {
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = resolved.redComponent
        let g = resolved.greenComponent
        let b = resolved.blueComponent
        let a = resolved.alphaComponent

        if a < 0.9995 {
            let ri = Int((r * 255).rounded())
            let gi = Int((g * 255).rounded())
            let bi = Int((b * 255).rounded())
            let af = (a * 1000).rounded() / 1000
            return "rgba(\(ri), \(gi), \(bi), \(af))"
        } else {
            let ri = Int((r * 255).rounded())
            let gi = Int((g * 255).rounded())
            let bi = Int((b * 255).rounded())
            return String(format: "#%02x%02x%02x", ri, gi, bi)
        }
    }

    // MARK: - Private helpers

    private init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("#") { hex.removeFirst() }

        switch hex.count {
        case 3:
            hex = hex.map { "\($0)\($0)" }.joined()
        case 4:
            hex = hex.map { "\($0)\($0)" }.joined()
        case 6:
            break
        case 8:
            break
        default:
            return nil
        }

        guard let value = UInt64(hex, radix: 16) else { return nil }

        let r, g, b, a: Double
        if hex.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8)  & 0xFF) / 255
            a = Double( value        & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8)  & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
            a = 1
        }

        self = Color(red: r, green: g, blue: b, opacity: a)
    }

    private init?(rgbString: String) {
        // Match: rgb(r, g, b) or rgba(r, g, b, a) with optional spaces
        let lower = rgbString.lowercased()
        let isRGBA = lower.hasPrefix("rgba")
        let prefix = isRGBA ? "rgba(" : "rgb("
        guard lower.hasPrefix(prefix), lower.hasSuffix(")") else { return nil }

        let inner = rgbString
            .dropFirst(prefix.count)
            .dropLast()
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 3,
              let r = Double(parts[0]),
              let g = Double(parts[1]),
              let b = Double(parts[2]) else { return nil }

        let a: Double
        if isRGBA, parts.count >= 4, let parsed = Double(parts[3]) {
            a = parsed
        } else {
            a = 1
        }

        self = Color(
            red:     r / (r > 1 ? 255 : 1),
            green:   g / (g > 1 ? 255 : 1),
            blue:    b / (b > 1 ? 255 : 1),
            opacity: a
        )
    }
}
