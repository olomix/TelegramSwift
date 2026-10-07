import Foundation

/// Persists `ApiCredentialsValues` as JSON in a single file readable only by
/// the owner.
public struct ApiCredentialsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Returns nil when the file is missing or cannot be decoded.
    public func load() -> ApiCredentialsValues? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(ApiCredentialsValues.self, from: data)
    }

    public func save(_ values: ApiCredentialsValues) throws {
        let data = try JSONEncoder().encode(values)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
