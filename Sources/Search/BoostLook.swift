import Foundation
import SwiftUI

// A boost's colours and type, as switches rather than CSS you have to write:
// the page's ground, its ink, the font and how big the text is. Yab's boost
// editor has the same four, with sliders for spacing beside them.
//
// What this writes is CSS, and only that: a rule for the root element, put on
// the page before your own CSS, so anything you write there wins over it. A
// field left empty writes nothing at all, which is how "the site's own" is
// said.

struct BoostLook: Codable, Equatable {
    /// A colour as the page would write it: "#RRGGBB", or "" for the site's own.
    var background: String = ""
    var text: String = ""
    /// A font family, by name as the Mac knows it; empty for the site's own.
    var font: String = ""
    /// The root font size in points; nil for the site's own.
    var size: Double? = nil
    /// The distance between lines, as a multiple of the text's size.
    var lineHeight: Double? = nil
    /// The room around a paragraph, in points.
    var paragraphSpacing: Double? = nil

    var isEmpty: Bool {
        background.isEmpty && text.isEmpty && font.isEmpty && size == nil
            && lineHeight == nil && paragraphSpacing == nil
    }

    /// The fonts offered, as a person reads them: the Mac's own five families
    /// and whatever else the system has, by name.
    static let fonts = ["", "-apple-system", "Georgia", "Times New Roman", "Helvetica Neue",
                        "Menlo", "Courier New", "Avenir Next", "SF Pro Text", "Iowan Old Style"]

    static func title(of font: String) -> String {
        font.isEmpty ? "The site's own" : font
    }

    /// The CSS the look adds: one rule on the root, so it reaches the page and
    /// the page's own rules still win where they are more specific.
    func css() -> String {
        var rules: [String] = []
        if !background.isEmpty { rules.append("background-color: \(background) !important;") }
        if !text.isEmpty { rules.append("color: \(text) !important;") }
        if !font.isEmpty { rules.append("font-family: \"\(font)\", -apple-system, sans-serif;") }
        if let size, size >= 8, size <= 32 {
            rules.append("font-size: \(Int(size.rounded()))px;")
        }
        if let lineHeight, lineHeight >= 1, lineHeight <= 2.5 {
            rules.append("line-height: \(String(format: "%.2f", lineHeight));")
        }
        var text = ""
        if !rules.isEmpty { text = "html, body { \(rules.joined(separator: " ")) }" }
        // Paragraphs have their own room, which the root rule can't reach.
        if let spacing = paragraphSpacing, spacing >= 0, spacing <= 24 {
            let room = Int(spacing.rounded())
            text += (text.isEmpty ? "" : "\n") + "p, li { margin-block: \(room)px; }"
        }
        return text
    }

    /// A colour from a picker, as a hex string; nil and blank both mean "the
    /// site's own".
    static func hex(_ colour: Color?) -> String {
        guard let colour, let srgb = NSColor(colour).usingColorSpace(.sRGB) else { return "" }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// The other way, for a picker that starts where the boost is.
    static func colour(_ hex: String) -> Color? {
        guard hex.count == 7, hex.hasPrefix("#") else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: String(hex.dropFirst())).scanHexInt64(&value) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
