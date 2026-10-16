import Foundation
import CryptoKit

public enum MD5Verifier {
    /// Computes MD5 checksum of a local file using streaming buffers (safe for 100GB+ video files)
    public static func computeMD5(for url: URL, bufferSize: Int = 4 * 1024 * 1024) async -> String? {
        return await Task.detached(priority: .utility) {
            guard let fileStream = InputStream(url: url) else { return nil }
            fileStream.open()
            defer { fileStream.close() }

            var md5 = Insecure.MD5()
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while fileStream.hasBytesAvailable {
                let bytesRead = fileStream.read(&buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    md5.update(data: Data(buffer[0..<bytesRead]))
                } else if bytesRead < 0 {
                    return nil
                } else {
                    break
                }
            }

            let digest = md5.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

    /// Verifies if local file matches expected Google Drive MD5 checksum
    public static func verify(localURL: URL, expectedMD5: String) async -> Bool {
        guard let computed = await computeMD5(for: localURL) else { return false }
        return computed.lowercased() == expectedMD5.lowercased()
    }
}
