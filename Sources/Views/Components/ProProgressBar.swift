import SwiftUI

public struct ProProgressBar: View {
    public let progress: Double
    public var height: CGFloat = 6
    public var tintColor: Color = ProTheme.accent
    public var showGlow: Bool = false

    public init(progress: Double, height: CGFloat = 6, tintColor: Color = ProTheme.accent, showGlow: Bool = false) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.height = height
        self.tintColor = tintColor
        self.showGlow = showGlow
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.black.opacity(0.4))
                    .frame(height: height)

                // Filled track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [tintColor.opacity(0.8), tintColor]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * CGFloat(progress), progress > 0 ? height : 0), height: height)
                    .shadow(color: showGlow ? tintColor.opacity(0.5) : Color.clear, radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: height)
    }
}
