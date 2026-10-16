import SwiftUI

public struct StatusPill: View {
    public let status: TaskStatus

    public init(status: TaskStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.iconName)
                .font(.system(size: 10, weight: .bold))
            Text(status.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(status.color)
        .background(status.color.opacity(0.15))
        .overlay(
            Capsule()
                .stroke(status.color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

public struct SessionStatusPill: View {
    public let status: SessionStatus

    public init(status: SessionStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(status.color)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }
}
