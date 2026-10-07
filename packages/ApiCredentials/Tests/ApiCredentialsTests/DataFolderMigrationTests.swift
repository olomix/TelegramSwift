import XCTest
@testable import ApiCredentials

final class DataFolderMigrationTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var source: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = root.appendingPathComponent("legacy")
        destination = root.appendingPathComponent("group")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func write(_ text: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        return (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func migrate(fileManager: FileManager? = nil) throws {
        try DataFolderMigration.move(from: source, to: destination, fileManager: fileManager ?? self.fileManager)
    }

    private func exists(_ url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }

    private func populateSource() throws {
        try write("db", to: source.appendingPathComponent("debug/accounts-metadata/db"))
        try write("icon", to: source.appendingPathComponent("debug/icons/a.png"))
        try write("prefs", to: source.appendingPathComponent("settings.json"))
    }

    func testMovesEverythingIntoMissingDestination() throws {
        try populateSource()
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent("debug/icons/a.png")), "icon")
        XCTAssertEqual(read(destination.appendingPathComponent("settings.json")), "prefs")
        XCTAssertFalse(exists(source.appendingPathComponent("debug")))
    }

    func testMovesEverythingIntoEmptyDestination() throws {
        try populateSource()
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
    }

    func testHiddenFilesInDestinationDoNotBlockMove() throws {
        try populateSource()
        try write("meta", to: destination.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
        try write("ds", to: destination.appendingPathComponent(".DS_Store"))
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent(".DS_Store")), "ds")
    }

    func testEmptyPrecreatedPrefixFolderIsReplaced() throws {
        try populateSource()
        try fileManager.createDirectory(at: destination.appendingPathComponent("debug/trlottie-animations"), withIntermediateDirectories: true)
        try write("ds", to: destination.appendingPathComponent("debug/.DS_Store"))
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent("debug/icons/a.png")), "icon")
    }

    func testAccountManagerWithoutAccountsDoesNotBlockMove() throws {
        try populateSource()
        // What the Share extension leaves when opened before the app.
        try write("guard", to: destination.appendingPathComponent("debug/accounts-metadata/guard_db/db_sqlite"))
        try write("{}", to: destination.appendingPathComponent("debug/accounts-metadata/atomic-state"))
        try write("log", to: destination.appendingPathComponent("debug/logs/log.txt"))
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertFalse(exists(destination.appendingPathComponent("debug/accounts-metadata/atomic-state")))
        XCTAssertFalse(exists(source.appendingPathComponent("debug")))
    }

    func testFolderWithAccountIsKept() throws {
        try populateSource()
        try write("current", to: destination.appendingPathComponent("debug/account-1/postbox/db"))
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("debug/account-1/postbox/db")), "current")
        XCTAssertFalse(exists(destination.appendingPathComponent("debug/accounts-metadata")))
        XCTAssertEqual(read(source.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent("settings.json")), "prefs")
    }

    func testExistingFileIsKept() throws {
        try populateSource()
        try write("new prefs", to: destination.appendingPathComponent("settings.json"))
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("settings.json")), "new prefs")
        XCTAssertEqual(read(source.appendingPathComponent("settings.json")), "prefs")
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
    }

    func testFileInDestinationIsKeptOverSourceFolder() throws {
        try populateSource()
        try write("file", to: destination.appendingPathComponent("debug"))
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("debug")), "file")
        XCTAssertEqual(read(source.appendingPathComponent("debug/accounts-metadata/db")), "db")
    }

    func testOnePrefixMigratedDoesNotBlockAnother() throws {
        try write("old stable", to: source.appendingPathComponent("stable/accounts-metadata/db"))
        try write("current", to: destination.appendingPathComponent("debug/account-1/postbox/db"))
        try write("meta", to: destination.appendingPathComponent("debug/accounts-metadata/db"))
        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("stable/accounts-metadata/db")), "old stable")
        XCTAssertEqual(read(destination.appendingPathComponent("debug/account-1/postbox/db")), "current")
    }

    func testFailedMoveLeavesRestAndRerunCompletesIt() throws {
        try populateSource()
        let failing = FailingFileManager(failingName: "settings.json")
        XCTAssertThrowsError(try migrate(fileManager: failing))
        XCTAssertEqual(read(source.appendingPathComponent("settings.json")), "prefs")
        XCTAssertFalse(exists(destination.appendingPathComponent("settings.json")))

        try migrate()
        XCTAssertEqual(read(destination.appendingPathComponent("settings.json")), "prefs")
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: source.path), [])
    }

    func testFailingItemDoesNotStopOthers() throws {
        try populateSource()
        try write("old stable", to: source.appendingPathComponent("stable/accounts-metadata/db"))
        let failing = FailingFileManager(failingName: "stable")
        XCTAssertThrowsError(try migrate(fileManager: failing)) { error in
            XCTAssertEqual((error as? DataFolderMigration.Failure)?.errors.keys.sorted(), ["stable"])
        }
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent("settings.json")), "prefs")
        XCTAssertFalse(DataFolderMigration.isPending("debug", from: source, to: destination, fileManager: fileManager))
        XCTAssertTrue(DataFolderMigration.isPending("stable", from: source, to: destination, fileManager: fileManager))
    }

    func testItemLeftByFailedMoveIsPending() throws {
        try populateSource()
        let failing = FailingFileManager(failingName: "debug")
        XCTAssertThrowsError(try migrate(fileManager: failing))
        XCTAssertTrue(DataFolderMigration.isPending("debug", from: source, to: destination, fileManager: fileManager))
    }

    func testMovedItemIsNotPending() throws {
        try populateSource()
        try migrate()
        XCTAssertFalse(DataFolderMigration.isPending("debug", from: source, to: destination, fileManager: fileManager))
    }

    func testItemKeptForDestinationDataIsNotPending() throws {
        try populateSource()
        try write("current", to: destination.appendingPathComponent("debug/account-1/postbox/db"))
        try migrate()
        XCTAssertFalse(DataFolderMigration.isPending("debug", from: source, to: destination, fileManager: fileManager))
    }

    func testNoOpWhenSourceIsMissing() throws {
        try fileManager.removeItem(at: source)
        try migrate()
        XCTAssertFalse(exists(destination))
    }
}

private final class FailingFileManager: FileManager {
    private let failingName: String

    init(failingName: String) {
        self.failingName = failingName
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent == failingName {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
