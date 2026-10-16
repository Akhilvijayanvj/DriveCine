import Foundation

public enum DriveAPIError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case quotaExceeded(String)
    case notFound(String)
    case serverError(Int, String)
    case networkError(String)
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Google Drive URL or File ID."
        case .unauthorized:
            return "Google Drive API access unauthorized. Please verify your Google API Key or OAuth token in Settings."
        case .quotaExceeded(let message):
            return "Google Drive Rate Limit / Download Quota Exceeded: \(message)"
        case .notFound(let id):
            return "File or Folder with ID '\(id)' was not found or is not shared publicly."
        case .serverError(let code, let msg):
            return "Google Drive API error (\(code)): \(msg)"
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .parsingError(let msg):
            return "Failed to parse Google Drive response: \(msg)"
        }
    }
}

public actor GoogleDriveClient {
    public static let shared = GoogleDriveClient()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    nonisolated private func getAuthHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        if let oauthToken = KeychainManager.shared.get(.oauthAccessToken), !oauthToken.isEmpty {
            headers["Authorization"] = "Bearer \(oauthToken)"
        }
        return headers
    }

    nonisolated private func getApiKey() -> String? {
        return KeychainManager.shared.get(.apiKey)
    }

    // MARK: - Metadata

    public func fetchItemMetadata(id: String) async throws -> DriveItem {
        var urlComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(id)")!
        var queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,size,md5Checksum,modifiedTime"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]
        if let key = getApiKey(), !key.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: key))
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else { throw DriveAPIError.invalidURL }

        var request = URLRequest(url: url)
        for (k, v) in getAuthHeaders() {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let mimeType = json["mimeType"] as? String else {
            throw DriveAPIError.parsingError("Invalid metadata response")
        }

        let size = Int64(json["size"] as? String ?? "") ?? Int64(json["size"] as? Int ?? 0)
        let md5 = json["md5Checksum"] as? String
        let modTime = json["modifiedTime"] as? String

        return DriveItem(
            id: id,
            name: name,
            mimeType: mimeType,
            size: size,
            md5Checksum: md5,
            modifiedTime: modTime,
            relativePath: name
        )
    }

    // MARK: - Recursive Folder Traversal

    public func traverseFolder(
        folderId: String,
        folderName: String = "",
        currentPath: String = "",
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> DriveItem {
        let rootMeta = try await fetchItemMetadata(id: folderId)
        let rootName = folderName.isEmpty ? rootMeta.name : folderName
        let relativeRoot = currentPath.isEmpty ? rootName : "\(currentPath)/\(rootName)"

        onProgress?("Scanning folder: \(relativeRoot)...")

        if !rootMeta.isFolder {
            var item = rootMeta
            item.relativePath = relativeRoot
            return item
        }

        var children: [DriveItem] = []
        var pageToken: String? = nil

        repeat {
            var urlComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            var queryItems = [
                URLQueryItem(name: "q", value: "'\(folderId)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,md5Checksum,modifiedTime)"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
            ]
            if let token = pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            if let key = getApiKey(), !key.isEmpty {
                queryItems.append(URLQueryItem(name: "key", value: key))
            }
            urlComponents.queryItems = queryItems

            guard let url = urlComponents.url else { throw DriveAPIError.invalidURL }
            var request = URLRequest(url: url)
            for (k, v) in getAuthHeaders() {
                request.setValue(v, forHTTPHeaderField: k)
            }

            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let filesList = json["files"] as? [[String: Any]] else {
                throw DriveAPIError.parsingError("Invalid file list format")
            }

            pageToken = json["nextPageToken"] as? String

            for itemDict in filesList {
                guard let id = itemDict["id"] as? String,
                      let name = itemDict["name"] as? String,
                      let mimeType = itemDict["mimeType"] as? String else { continue }

                let size = Int64(itemDict["size"] as? String ?? "") ?? Int64(itemDict["size"] as? Int ?? 0)
                let md5 = itemDict["md5Checksum"] as? String
                let modTime = itemDict["modifiedTime"] as? String
                let childPath = "\(relativeRoot)/\(name)"

                if mimeType == "application/vnd.google-apps.folder" {
                    // Recursively scan subfolder
                    let subFolder = try await traverseFolder(
                        folderId: id,
                        folderName: name,
                        currentPath: relativeRoot,
                        onProgress: onProgress
                    )
                    children.append(subFolder)
                } else {
                    let fileItem = DriveItem(
                        id: id,
                        name: name,
                        mimeType: mimeType,
                        size: size,
                        md5Checksum: md5,
                        modifiedTime: modTime,
                        parentId: folderId,
                        relativePath: childPath,
                        isSelected: true,
                        children: nil
                    )
                    children.append(fileItem)
                }
            }
        } while pageToken != nil

        return DriveItem(
            id: folderId,
            name: rootName,
            mimeType: "application/vnd.google-apps.folder",
            size: 0,
            parentId: nil,
            relativePath: relativeRoot,
            isSelected: true,
            children: children
        )
    }

    // MARK: - Download URL Request Builder

    nonisolated public func buildDownloadRequest(fileId: String, startByte: Int64 = 0) -> URLRequest {
        var urlComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        var queryItems = [
            URLQueryItem(name: "alt", value: "media"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]
        if let key = getApiKey(), !key.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: key))
        }
        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        for (k, v) in getAuthHeaders() {
            request.setValue(v, forHTTPHeaderField: k)
        }

        if startByte > 0 {
            request.setValue("bytes=\(startByte)-", forHTTPHeaderField: "Range")
        }

        return request
    }

    // MARK: - Response Validation

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }

        if http.statusCode == 401 {
            throw DriveAPIError.unauthorized
        }

        if http.statusCode == 403 {
            var msg = "Quota or permission issue"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let message = err["message"] as? String {
                msg = message
            }
            if msg.localizedCaseInsensitiveContains("unregistered callers") {
                throw DriveAPIError.unauthorized
            }
            throw DriveAPIError.quotaExceeded(msg)
        }

        if http.statusCode == 404 {
            throw DriveAPIError.notFound("Resource not found")
        }

        if http.statusCode >= 400 {
            var msg = "HTTP \(http.statusCode)"
            if let str = String(data: data, encoding: .utf8) {
                msg = str
            }
            throw DriveAPIError.serverError(http.statusCode, msg)
        }
    }
}
