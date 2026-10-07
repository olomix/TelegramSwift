import Foundation

public enum DataFolderMigration {
    /// Moves each top-level item of `source` into `destination`, keeping
    /// items that already exist there. An existing directory holding nothing
    /// but hidden files or empty folders is replaced, since the app and the
    /// system pre-create those before any data is written.
    ///
    /// Does nothing when `source` is missing or when `destination` already
    /// holds an account database for one of `prefixes`.
    ///
    /// - Returns: the number of items moved.
    @discardableResult
    public static func move(from source: URL, to destination: URL, prefixes: [String], fileManager: FileManager) throws -> Int {
        guard fileManager.fileExists(atPath: source.path) else {
            return 0
        }
        let alreadyMigrated = prefixes.contains { prefix in
            fileManager.fileExists(atPath: destination.appendingPathComponent(prefix).appendingPathComponent("accounts-metadata").path)
        }
        if alreadyMigrated {
            return 0
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var moved = 0
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                guard isEffectivelyEmptyDirectory(target, fileManager: fileManager) else {
                    continue
                }
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: item, to: target)
            moved += 1
        }
        return moved
    }

    private static func isEffectivelyEmptyDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return false
        }
        return contents.allSatisfy { child in
            child.lastPathComponent.hasPrefix(".") || isEffectivelyEmptyDirectory(child, fileManager: fileManager)
        }
    }
}
