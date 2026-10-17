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

    /// Flushes the file and its directory to disk before returning: a key
    /// file written later (the retired marker) must not outlive this one
    /// after a power loss.
    public func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError.current() }
        var renamed = false
        defer {
            if !renamed { unlink(temporary.path) }
        }
        do {
            defer { close(fd) }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw POSIXError.current()
                    }
                    offset += written
                }
            }
            try Self.flush(fd)
        }
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError.current() }
        renamed = true
        try Self.flushDirectory(directory)
    }

    private static func flush(_ fd: Int32) throws {
        // fsync alone leaves data in the drive's cache on macOS.
        guard fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0 else { throw POSIXError.current() }
    }

    private static func flushDirectory(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError.current() }
        defer { close(fd) }
        try self.flush(fd)
    }

    public func remove(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
        }
    }
}

private extension POSIXError {
    static func current() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
