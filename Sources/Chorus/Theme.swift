import SwiftUI
import AppKit

enum Theme {
    // Resolve through AppKit's current appearance so sheets and native controls agree.
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0x7038AC, 0xCCACFF)
    static let action = adaptive(0x8343DC, 0x8343DC)
    static let background = adaptive(0xFDFBFF, 0x08080C)
    static let sidebar = adaptive(0xF4F1F8, 0x0D0D12)
    static let inspector = adaptive(0xF8F5FC, 0x101016)
    static let surface = adaptive(0xFCFAFF, 0x15151D)
    static let control = adaptive(0xEEE8F6, 0x23232E)
    static let border = adaptive(0xDCD2E8, 0x3C3A49)
    static let ink = adaptive(0x292331, 0xF6F3FC)
    static let secondary = adaptive(0x665E70, 0xB9B4C5)
    static let muted = adaptive(0x70667A, 0xAAA3B8)
}

struct StudioBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Theme.background
            GeometryReader { geometry in
                    RadialGradient(colors: [Color.purple.opacity(scheme == .dark ? 0.19 : 0.065), .clear], center: .bottomTrailing,
                                   startRadius: 0, endRadius: geometry.size.width * 0.65)
                    RadialGradient(colors: [Color.pink.opacity(scheme == .dark ? 0.08 : 0.025), .clear], center: .bottomLeading,
                                   startRadius: 0, endRadius: geometry.size.width * 0.45)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct FloatingMaterial: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct GlassControl: ViewModifier {
    var prominent = false
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass).tint(Theme.control).foregroundStyle(Theme.ink) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

struct GlassGroup: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 16) { content }
        } else { content }
    }
}

struct NavigationMaterial: ViewModifier {
    var selected: Bool
    func body(content: Content) -> some View {
        if selected {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.tint(Theme.accent.opacity(0.14)), in: .rect(cornerRadius: 14))
            } else {
                content.background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
        } else { content }
    }
}
