import Foundation

public enum DataFolderMigration {
    /// The items `move` could not move, keyed by name, with the error for each.
    public struct Failure: Error {
        public let errors: [String: Error]
    }

    /// Moves each top-level item of `source` into `destination`. An item that
    /// already exists there is replaced unless it holds data worth keeping:
    /// a regular file, or a folder with an `account-*` folder inside. The app
    /// and the Share extension pre-create folders and empty databases before
    /// any account exists, and those must not block the move.
    ///
    /// Each item is decided on its own, so a second build type or a re-run
    /// after a partial move still moves what is left, and an item that fails
    /// does not stop the rest. Does nothing when `source` is missing. Throws
    /// `Failure` after trying every item if any of them failed.
    public static func move(from source: URL, to destination: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var errors: [String: Error] = [:]
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            do {
                try moveItem(item, into: destination, fileManager: fileManager)
            } catch {
                errors[item.lastPathComponent] = error
            }
        }
        if !errors.isEmpty {
            throw Failure(errors: errors)
        }
    }

    private static func moveItem(_ item: URL, into destination: URL, fileManager: FileManager) throws {
        let target = destination.appendingPathComponent(item.lastPathComponent)
        if fileManager.fileExists(atPath: target.path) {
            if holdsData(target, fileManager: fileManager) {
                return
            }
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: item, to: target)
    }

    /// True when `source` still has the item `name` and `move` would move it,
    /// i.e. the copy in `destination` is missing or holds no data worth keeping.
    public static func isPending(_ name: String, from source: URL, to destination: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: source.appendingPathComponent(name).path) else {
            return false
        }
        return !holdsData(destination.appendingPathComponent(name), fileManager: fileManager)
    }

    private static func holdsData(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        guard isDirectory.boolValue else {
            return true
        }
        let children = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        return children.contains { $0.hasPrefix("account-") }
    }
}
