import SwiftUI

enum CyberpunkTheme {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.08)
    static let elevated = Color(red: 0.08, green: 0.10, blue: 0.15)
    static let panel = Color(red: 0.12, green: 0.14, blue: 0.20).opacity(0.86)
    static let cyan = Color(red: 0.13, green: 0.88, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.16, blue: 0.72)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.22)
    static let mint = Color(red: 0.26, green: 1.0, blue: 0.66)
    static let softText = Color.white.opacity(0.72)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                background,
                Color(red: 0.07, green: 0.08, blue: 0.13),
                Color(red: 0.09, green: 0.05, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GlassPanel: ViewModifier {
    var accent: Color = CyberpunkTheme.cyan

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CyberpunkTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accent.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(0.16), radius: 18, x: 0, y: 10)
            )
    }
}

extension View {
    func glassPanel(accent: Color = CyberpunkTheme.cyan) -> some View {
        modifier(GlassPanel(accent: accent))
    }
}
