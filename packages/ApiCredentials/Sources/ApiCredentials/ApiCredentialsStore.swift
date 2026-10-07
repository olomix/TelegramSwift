import Foundation

/// Persists `ApiCredentialsValues` as JSON in a single file readable only by
/// the owner.
public struct ApiCredentialsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Returns nil when the file is missing, cannot be decoded, or holds
    /// values that would not pass `ApiCredentialsValues.validate`.
    public func load() -> ApiCredentialsValues? {
        guard let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(ApiCredentialsValues.self, from: data) else {
            return nil
        }
        return try? ApiCredentialsValues.validate(apiId: String(stored.apiId), apiHash: stored.apiHash).get()
    }

    /// Writes atomically with mode 0600, creating the parent folder if needed.
    /// On failure the previous file, if any, is left unchanged.
    public func save(_ values: ApiCredentialsValues) throws {
        let data = try JSONEncoder().encode(values)
        let fileManager = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Restrict a temporary copy first so the real path never holds the
        // values with wider permissions.
        let temporaryURL = folder.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString)")
        do {
            try data.write(to: temporaryURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            if rename(temporaryURL.path, fileURL.path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
