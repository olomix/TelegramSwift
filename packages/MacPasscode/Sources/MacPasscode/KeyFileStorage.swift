import Foundation

/// File access used for key files, injectable for tests.
public protocol KeyFileStorage {
    /// Returns nil only when the file does not exist; throws when it exists
    /// but cannot be read, so callers never mistake it for a missing file.
    func read(_ url: URL) throws -> Data?
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Removing a missing file is not an error.
    func remove(_ url: URL) throws
}

public struct LocalKeyFileStorage: KeyFileStorage {
    public init() {}

    public func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return nil
        }
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func remove(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
        }
    }
}
