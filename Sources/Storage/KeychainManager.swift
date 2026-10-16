import Foundation
import Security
import LocalAuthentication

/// Thread-safe manager for storing sensitive API tokens and credentials.
/// Uses a combination of instant in-memory caching and persistent local database storage
/// to completely eliminate annoying macOS Keychain password prompts during transfers.
public final class KeychainManager: @unchecked Sendable {
    public static let shared = KeychainManager()
    private let serviceName = "com.drivecine.gdrive.credentials"
    private let lock = NSLock()
    private var memoryCache: [String: String] = [:]

    public enum Key: String {
        case apiKey = "google_api_key"
        case oauthAccessToken = "google_oauth_access_token"
        case oauthRefreshToken = "google_oauth_refresh_token"
        case oauthClientId = "google_oauth_client_id"
        case oauthClientSecret = "google_oauth_client_secret"
        case oauthTokenExpiry = "google_oauth_token_expiry"
    }

    private init() {
        // Preload known keys from persistent local storage to memory cache on launch
        let allKeys: [Key] = [
            .apiKey,
            .oauthAccessToken,
            .oauthRefreshToken,
            .oauthClientId,
            .oauthClientSecret,
            .oauthTokenExpiry
        ]
        for key in allKeys {
            if let val = DatabaseManager.shared.getSecureValue(for: key.rawValue) {
                memoryCache[key.rawValue] = val
            }
        }
    }

    public func set(_ value: String?, for key: Key) {
        lock.lock()
        defer { lock.unlock() }

        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            delete(key)
            return
        }

        // 1. Instant in-memory cache update
        memoryCache[key.rawValue] = value

        // 2. Persistent storage in app database (zero prompts, reliable across reboots)
        DatabaseManager.shared.setSecureValue(value, for: key.rawValue)

        // 3. Silent macOS Keychain synchronization with AccessibleAfterFirstUnlock
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    public func get(_ key: Key) -> String? {
        lock.lock()
        defer { lock.unlock() }

        // 1. Return from memory cache if available (0 ms, zero prompts)
        if let cached = memoryCache[key.rawValue] {
            return cached
        }

        // 2. Return from persistent local storage (zero prompts)
        if let dbVal = DatabaseManager.shared.getSecureValue(for: key.rawValue) {
            memoryCache[key.rawValue] = dbVal
            return dbVal
        }

        // 3. Silent fallback check from Keychain with UI suppressed
        let authContext = LAContext()
        authContext.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authContext
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            memoryCache[key.rawValue] = str
            DatabaseManager.shared.setSecureValue(str, for: key.rawValue)
            return str
        }

        return nil
    }

    public func delete(_ key: Key) {
        lock.lock()
        memoryCache.removeValue(forKey: key.rawValue)
        lock.unlock()

        DatabaseManager.shared.deleteSecureValue(for: key.rawValue)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    public func clearAll() {
        for key in [Key.apiKey, .oauthAccessToken, .oauthRefreshToken, .oauthClientId, .oauthClientSecret, .oauthTokenExpiry] {
            delete(key)
        }
    }
}
