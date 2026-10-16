import SwiftUI

public enum ProTheme {
    // Dark Pro Palette
    public static let bgDarkest = Color(red: 0.07, green: 0.08, blue: 0.09)      // #121417
    public static let bgDark = Color(red: 0.10, green: 0.11, blue: 0.13)         // #1A1C21
    public static let bgSurface = Color(red: 0.14, green: 0.16, blue: 0.19)      // #242930
    public static let bgSurfaceHover = Color(red: 0.18, green: 0.20, blue: 0.24) // #2E333D
    public static let border = Color(red: 0.22, green: 0.25, blue: 0.30)         // #38404D
    public static let borderSubtle = Color(red: 0.18, green: 0.20, blue: 0.24)

    // Accents
    public static let accent = Color(red: 0.22, green: 0.65, blue: 1.0)          // Cinema Cyan
    public static let accentGlow = Color(red: 0.22, green: 0.65, blue: 1.0).opacity(0.3)
    public static let success = Color(red: 0.15, green: 0.85, blue: 0.55)        // Emerald Mint
    public static let warning = Color(red: 0.98, green: 0.73, blue: 0.25)        // Amber Gold
    public static let danger = Color(red: 0.98, green: 0.35, blue: 0.35)         // Ruby Red
    public static let purple = Color(red: 0.65, green: 0.45, blue: 0.95)

    // Text
    public static let textPrimary = Color(red: 0.95, green: 0.96, blue: 0.98)
    public static let textSecondary = Color(red: 0.65, green: 0.68, blue: 0.74)
    public static let textMuted = Color(red: 0.45, green: 0.48, blue: 0.54)
}

extension View {
    public func proCardStyle() -> some View {
        self
            .background(ProTheme.bgSurface)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ProTheme.borderSubtle, lineWidth: 1)
            )
    }

    public func proHeaderStyle() -> some View {
        self
            .background(ProTheme.bgDark)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(ProTheme.borderSubtle),
                alignment: .bottom
            )
    }
}
