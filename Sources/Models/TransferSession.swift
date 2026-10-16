import Foundation
import SwiftUI

public enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case preparing = "Preparing"
    case ready = "Ready"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"

    public var color: Color {
        switch self {
        case .preparing: return Color.gray
        case .ready: return Color(red: 0.25, green: 0.65, blue: 1.0)
        case .downloading: return Color(red: 0.20, green: 0.75, blue: 1.0)
        case .paused: return Color(red: 0.95, green: 0.70, blue: 0.20)
        case .completed: return Color(red: 0.20, green: 0.82, blue: 0.50)
        case .failed: return Color(red: 0.95, green: 0.30, blue: 0.30)
        }
    }
}

public struct TransferSession: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public let rootDriveId: String
    public let originalUrl: String
    public let destinationPath: String
    public var totalFiles: Int
    public var totalBytes: Int64
    public var completedFiles: Int
    public var completedBytes: Int64
    public var status: SessionStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        rootDriveId: String,
        originalUrl: String,
        destinationPath: String,
        totalFiles: Int = 0,
        totalBytes: Int64 = 0,
        completedFiles: Int = 0,
        completedBytes: Int64 = 0,
        status: SessionStatus = .ready,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootDriveId = rootDriveId
        self.originalUrl = originalUrl
        self.destinationPath = destinationPath
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.completedFiles = completedFiles
        self.completedBytes = completedBytes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var progress: Double {
        guard totalBytes > 0 else { return completedFiles >= totalFiles && totalFiles > 0 ? 1.0 : 0.0 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0.0), 1.0)
    }

    public var formattedProgress: String {
        let pct = Int(progress * 100)
        return "\(DriveItem.formatBytes(completedBytes)) of \(DriveItem.formatBytes(totalBytes)) (\(pct)%)"
    }

    public var formattedCounts: String {
        return "\(completedFiles) of \(totalFiles) files"
    }
}
