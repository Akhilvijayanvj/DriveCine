import Foundation
import SwiftUI

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case queued = "Queued"
    case downloading = "Downloading"
    case paused = "Paused"
    case verifying = "Verifying MD5"
    case completed = "Completed"
    case failed = "Failed"

    public var iconName: String {
        switch self {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .verifying: return "checkmark.shield"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .queued: return Color.gray
        case .downloading: return Color(red: 0.25, green: 0.65, blue: 1.0)
        case .paused: return Color(red: 0.95, green: 0.70, blue: 0.20)
        case .verifying: return Color(red: 0.60, green: 0.40, blue: 0.95)
        case .completed: return Color(red: 0.20, green: 0.82, blue: 0.50)
        case .failed: return Color(red: 0.95, green: 0.30, blue: 0.30)
        }
    }
}

public struct DownloadTask: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sessionId: UUID
    public let driveFileId: String
    public let fileName: String
    public let relativePath: String
    public let fileSize: Int64
    public var downloadedBytes: Int64
    public let md5Checksum: String?
    public let localPath: String
    public var status: TaskStatus
    public var currentSpeed: Double // bytes per second
    public var errorMessage: String?
    public var retryCount: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        driveFileId: String,
        fileName: String,
        relativePath: String,
        fileSize: Int64,
        downloadedBytes: Int64 = 0,
        md5Checksum: String? = nil,
        localPath: String,
        status: TaskStatus = .queued,
        currentSpeed: Double = 0,
        errorMessage: String? = nil,
        retryCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.driveFileId = driveFileId
        self.fileName = fileName
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.downloadedBytes = downloadedBytes
        self.md5Checksum = md5Checksum
        self.localPath = localPath
        self.status = status
        self.currentSpeed = currentSpeed
        self.errorMessage = errorMessage
        self.retryCount = retryCount
        self.updatedAt = updatedAt
    }

    public var progress: Double {
        guard fileSize > 0 else { return status == .completed ? 1.0 : 0.0 }
        return min(max(Double(downloadedBytes) / Double(fileSize), 0.0), 1.0)
    }

    public var formattedSpeed: String {
        guard status == .downloading, currentSpeed > 0 else { return "--" }
        return "\(DriveItem.formatBytes(Int64(currentSpeed)))/s"
    }

    public var etaRemainingSeconds: TimeInterval? {
        guard status == .downloading, currentSpeed > 1024 else { return nil }
        let remainingBytes = Double(fileSize - downloadedBytes)
        guard remainingBytes > 0 else { return 0 }
        return remainingBytes / currentSpeed
    }

    public var formattedETA: String {
        guard let eta = etaRemainingSeconds else { return "--" }
        if eta < 60 {
            return String(format: "%ds", Int(eta))
        } else if eta < 3600 {
            return String(format: "%dm %ds", Int(eta) / 60, Int(eta) % 60)
        } else {
            return String(format: "%dh %dm", Int(eta) / 3600, (Int(eta) % 3600) / 60)
        }
    }

    public var formattedProgressText: String {
        let dl = DriveItem.formatBytes(downloadedBytes)
        let total = DriveItem.formatBytes(fileSize)
        let pct = Int(progress * 100)
        return "\(dl) / \(total) (\(pct)%)"
    }
}
