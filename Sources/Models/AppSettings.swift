import Foundation

public enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case apiKey = "Google API Key (Public / Anyone with Link)"
    case oauth = "OAuth 2.0 (Private Drives & Shared with Me)"
    case directPublic = "Direct Public Web Stream"
}

public struct AppSettings: Codable, Sendable {
    public var maxConcurrentDownloads: Int
    public var verifyChecksums: Bool
    public var defaultDestinationPath: String
    public var autoRetryOnRateLimit: Bool
    public var maxRetries: Int
    public var retryDelaySeconds: Double
    public var authMethod: AuthMethod
    public var enableSounds: Bool
    public var showNotifications: Bool

    public static let `default` = AppSettings(
        maxConcurrentDownloads: 4,
        verifyChecksums: true,
        defaultDestinationPath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/Volumes",
        autoRetryOnRateLimit: true,
        maxRetries: 5,
        retryDelaySeconds: 3.0,
        authMethod: .apiKey,
        enableSounds: true,
        showNotifications: true
    )
}
