import CoreText
import SwiftUI

/// The colors and type of Lighthouse, shared with the web app.
enum Theme {
    static let background = Color(light: 0xEDF0F4, dark: 0x0A0F17)
    static let sidebar = Color(light: 0xE6EAF0, dark: 0x0D131E)
    static let surface = Color(light: 0xFFFFFF, dark: 0x111826)
    static let surface2 = Color(light: 0xF3F5F8, dark: 0x182131)
    static let surface3 = Color(light: 0xE6EAF0, dark: 0x212C3F)
    static let ink = Color(light: 0x111A2B, dark: 0xE6EBF3)
    static let ink2 = Color(light: 0x4B5568, dark: 0xA3AEC0)
    static let ink3 = Color(light: 0x626C80, dark: 0x8C97AA)
    static let line = Color(light: 0xDCE1E9, dark: 0x263145)
    static let lamp = Color(light: 0xA15C00, dark: 0xF0A73A)
    static let onLamp = Color(light: 0xFFFFFF, dark: 0x1C1205)
    static let lampSoft = Color(light: 0xFBEED8, dark: 0x33240D)
    static let lampInk = Color(light: 0x7A4500, dark: 0xF5BE6A)
    static let ok = Color(light: 0x1D7A4C, dark: 0x4FC28B)
    static let okSoft = Color(light: 0xE0F2E8, dark: 0x10301F)
    static let crit = Color(light: 0xB42318, dark: 0xF2766C)
    static let critSoft = Color(light: 0xFCE6E3, dark: 0x3A1613)
    static let info = Color(light: 0x2357B0, dark: 0x80A9F2)
    static let infoSoft = Color(light: 0xE2EBFA, dark: 0x142441)

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Schibsted Grotesk", size: size, relativeTo: .body).weight(weight)
    }

    static func body(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .custom("IBM Plex Sans", size: size, relativeTo: .body).weight(weight)
    }

    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .custom("IBM Plex Mono", size: size, relativeTo: .body).weight(weight)
    }
}

extension Color {
    fileprivate init(light: UInt32, dark: UInt32) {
        #if os(macOS)
            self.init(
                nsColor: NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    return NSColor(hex: isDark ? dark : light)
                })
        #else
            self.init(
                uiColor: UIColor { traits in
                    UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
                })
        #endif
    }
}

#if os(macOS)
    extension NSColor {
        fileprivate convenience init(hex: UInt32) {
            self.init(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
#else
    extension UIColor {
        fileprivate convenience init(hex: UInt32) {
            self.init(
                red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
#endif

/// Makes the bundled typefaces available. Call once at launch.
public enum LighthouseFonts {
    private static let registered: Void = {
        guard let folder = Bundle.module.resourceURL?.appending(path: "Fonts"),
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }()

    public static func register() {
        _ = registered
    }
}
