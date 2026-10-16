import Foundation
import SwiftUI

/// Represents a file or folder fetched from Google Drive API v3
public struct DriveItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let size: Int64
    public let md5Checksum: String?
    public let modifiedTime: String?
    public let parentId: String?
    public var relativePath: String
    public var isSelected: Bool
    public var children: [DriveItem]?

    public init(
        id: String,
        name: String,
        mimeType: String,
        size: Int64 = 0,
        md5Checksum: String? = nil,
        modifiedTime: String? = nil,
        parentId: String? = nil,
        relativePath: String = "",
        isSelected: Bool = true,
        children: [DriveItem]? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.md5Checksum = md5Checksum
        self.modifiedTime = modifiedTime
        self.parentId = parentId
        self.relativePath = relativePath
        self.isSelected = isSelected
        self.children = children
    }

    public var isFolder: Bool {
        return mimeType == "application/vnd.google-apps.folder"
    }

    public var fileExtension: String {
        return (name as NSString).pathExtension.lowercased()
    }

    public var mediaCategory: MediaCategory {
        if isFolder { return .folder }
        let ext = fileExtension
        switch ext {
        case "mov", "mp4", "m4v", "mxf", "braw", "r3d", "ari", "avi", "mkv", "prores":
            return .video
        case "wav", "mp3", "aac", "aif", "aiff", "flac", "m4a":
            return .audio
        case "arw", "cr2", "cr3", "nef", "dng", "raw", "jpg", "jpeg", "png", "tif", "tiff", "heic":
            return .photo
        case "cube", "look", "3dl", "drp", "prproj", "fcpbundle", "fcpxml", "edl", "xml":
            return .projectFile
        default:
            return .other
        }
    }

    public var iconName: String {
        switch mediaCategory {
        case .all: return "film.stack"
        case .folder: return "folder.fill"
        case .video: return "film.stack.fill"
        case .audio: return "waveform"
        case .photo: return "camera.aperture"
        case .projectFile: return "slider.horizontal.3"
        case .other: return "doc.fill"
        }
    }

    public var categoryColor: Color {
        switch mediaCategory {
        case .all: return Color.white
        case .folder: return Color(red: 0.98, green: 0.75, blue: 0.28) // Amber
        case .video: return Color(red: 0.36, green: 0.68, blue: 0.99) // Cinema Cyan/Blue
        case .audio: return Color(red: 0.40, green: 0.88, blue: 0.60) // Mint green
        case .photo: return Color(red: 0.89, green: 0.48, blue: 0.93) // Magenta
        case .projectFile: return Color(red: 1.0, green: 0.55, blue: 0.25) // Orange
        case .other: return Color(red: 0.65, green: 0.65, blue: 0.70) // Slate
        }
    }

    public var formattedSize: String {
        if isFolder {
            let total = totalRecursiveSize
            return total > 0 ? DriveItem.formatBytes(total) : "--"
        }
        return DriveItem.formatBytes(size)
    }

    public var totalRecursiveSize: Int64 {
        if isFolder {
            return (children ?? []).reduce(0) { $0 + $1.totalRecursiveSize }
        }
        return size
    }

    public var totalRecursiveFileCount: Int {
        if isFolder {
            return (children ?? []).reduce(0) { $0 + $1.totalRecursiveFileCount }
        }
        return 1
    }

    /// Flattens this tree into all downloadable leaf files
    public func flattenFiles() -> [DriveItem] {
        if isFolder {
            return (children ?? []).flatMap { $0.flattenFiles() }
        } else {
            return [self]
        }
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024 {
            return "\(bytes) B"
        } else if b < 1024 * 1024 {
            return String(format: "%.1f KB", b / 1024)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", b / (1024 * 1024))
        } else if b < 1024 * 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", b / (1024 * 1024 * 1024))
        } else {
            return String(format: "%.2f TB", b / (1024 * 1024 * 1024 * 1024))
        }
    }
}

public enum MediaCategory: String, Codable, CaseIterable, Sendable {
    case all = "All Files"
    case video = "Video (4K/ProRes/RAW)"
    case audio = "Audio (WAV/Multitrack)"
    case photo = "Stills (RAW/Photos)"
    case projectFile = "Projects & LUTs"
    case folder = "Folders"
    case other = "Other"
}
