import SwiftUI
import AppKit

enum Palette {
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let accent = adaptive(NSColor(srgbRed: 0.20, green: 0.48, blue: 0.36, alpha: 1), NSColor(srgbRed: 0.72, green: 0.65, blue: 0.86, alpha: 1))
    static let background = adaptive(NSColor(srgbRed: 0.967, green: 0.976, blue: 0.969, alpha: 1), NSColor(srgbRed: 0.105, green: 0.109, blue: 0.117, alpha: 1))
    static let card = adaptive(.white, NSColor(srgbRed: 0.15, green: 0.157, blue: 0.17, alpha: 1))
    static let ink = adaptive(NSColor(srgbRed: 0.15, green: 0.20, blue: 0.17, alpha: 1), NSColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1))
    static let secondary = adaptive(NSColor(srgbRed: 0.44, green: 0.51, blue: 0.47, alpha: 1), NSColor(srgbRed: 0.59, green: 0.61, blue: 0.65, alpha: 1))
    static let border = adaptive(NSColor(srgbRed: 0.85, green: 0.90, blue: 0.87, alpha: 1), NSColor(srgbRed: 0.24, green: 0.25, blue: 0.27, alpha: 1))
    static let outline = adaptive(NSColor(srgbRed: 0.60, green: 0.71, blue: 0.65, alpha: 1), NSColor(srgbRed: 0.43, green: 0.45, blue: 0.49, alpha: 1))
    static let checkInk = adaptive(.white, NSColor(srgbRed: 0.15, green: 0.17, blue: 0.23, alpha: 1))

}
