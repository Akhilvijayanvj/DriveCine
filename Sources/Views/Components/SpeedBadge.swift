import SwiftUI

public struct SpeedBadge: View {
    public let speed: Double

    public init(speed: Double) {
        self.speed = speed
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(speed > 0 ? ProTheme.accent : ProTheme.textMuted)

            Text(speed > 0 ? "\(DriveItem.formatBytes(Int64(speed)))/s" : "0.0 MB/s")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(speed > 0 ? ProTheme.textPrimary : ProTheme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(ProTheme.bgSurface)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(speed > 0 ? ProTheme.accent.opacity(0.4) : ProTheme.borderSubtle, lineWidth: 1)
        )
    }
}
