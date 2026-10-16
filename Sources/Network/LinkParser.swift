import Foundation

public enum DriveResourceType: String, Sendable {
    case folder
    case file
    case unknown
}

public struct ParsedDriveResource: Sendable {
    public let id: String
    public let type: DriveResourceType
    public let originalUrl: String
}

public enum LinkParser {
    public static func parse(input: String) -> ParsedDriveResource? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If it's just an alphanumeric string (likely direct Google Drive ID)
        let idRegex = try? NSRegularExpression(pattern: "^[a-zA-Z0-9_-]{20,}$")
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if let idRegex = idRegex, idRegex.firstMatch(in: trimmed, range: range) != nil {
            return ParsedDriveResource(id: trimmed, type: .unknown, originalUrl: trimmed)
        }

        // Folder URL patterns:
        // drive.google.com/drive/folders/{ID}
        // drive.google.com/drive/u/0/folders/{ID}
        let folderPatterns = [
            "/folders/([a-zA-Z0-9_-]+)",
            "[?&]id=([a-zA-Z0-9_-]+)"
        ]

        for pattern in folderPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: trimmed) {
                let id = String(trimmed[r])
                return ParsedDriveResource(id: id, type: .folder, originalUrl: trimmed)
            }
        }

        // File URL patterns:
        // drive.google.com/file/d/{ID}
        let filePatterns = [
            "/file/d/([a-zA-Z0-9_-]+)"
        ]

        for pattern in filePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: trimmed) {
                let id = String(trimmed[r])
                return ParsedDriveResource(id: id, type: .file, originalUrl: trimmed)
            }
        }

        return nil
    }
}
