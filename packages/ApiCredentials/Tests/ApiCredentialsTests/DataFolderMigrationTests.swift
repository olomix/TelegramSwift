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

    private func migrate() throws -> Int {
        return try DataFolderMigration.move(from: source, to: destination, prefixes: ["debug", "stable"], fileManager: fileManager)
    }

    private func populateSource() throws {
        try write("db", to: source.appendingPathComponent("debug/accounts-metadata/db"))
        try write("icon", to: source.appendingPathComponent("debug/icons/a.png"))
        try write("prefs", to: source.appendingPathComponent("settings.json"))
    }

    func testMovesEverythingIntoMissingDestination() throws {
        try populateSource()
        XCTAssertEqual(try migrate(), 2)
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent("debug/icons/a.png")), "icon")
        XCTAssertEqual(read(destination.appendingPathComponent("settings.json")), "prefs")
        XCTAssertFalse(fileManager.fileExists(atPath: source.appendingPathComponent("debug").path))
    }

    func testMovesEverythingIntoEmptyDestination() throws {
        try populateSource()
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        XCTAssertEqual(try migrate(), 2)
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
    }

    func testHiddenFilesInDestinationDoNotBlockMove() throws {
        try populateSource()
        try write("meta", to: destination.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
        try write("ds", to: destination.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(try migrate(), 2)
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent(".DS_Store")), "ds")
    }

    func testEmptyPrecreatedPrefixFolderIsReplaced() throws {
        try populateSource()
        try fileManager.createDirectory(at: destination.appendingPathComponent("debug/trlottie-animations"), withIntermediateDirectories: true)
        try write("ds", to: destination.appendingPathComponent("debug/.DS_Store"))
        XCTAssertEqual(try migrate(), 2)
        XCTAssertEqual(read(destination.appendingPathComponent("debug/accounts-metadata/db")), "db")
        XCTAssertEqual(read(destination.appendingPathComponent("debug/icons/a.png")), "icon")
    }

    func testExistingItemsAreKept() throws {
        try populateSource()
        try write("new prefs", to: destination.appendingPathComponent("settings.json"))
        try write("other", to: destination.appendingPathComponent("debug/logs/log.txt"))
        XCTAssertEqual(try migrate(), 0)
        XCTAssertEqual(read(destination.appendingPathComponent("settings.json")), "new prefs")
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("debug/accounts-metadata").path))
        XCTAssertEqual(read(source.appendingPathComponent("settings.json")), "prefs")
    }

    func testNoOpWhenDestinationHasAccounts() throws {
        try populateSource()
        try write("current", to: destination.appendingPathComponent("stable/accounts-metadata/db"))
        XCTAssertEqual(try migrate(), 0)
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("settings.json").path))
        XCTAssertEqual(read(source.appendingPathComponent("settings.json")), "prefs")
    }

    func testNoOpWhenSourceIsMissing() throws {
        try fileManager.removeItem(at: source)
        XCTAssertEqual(try migrate(), 0)
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
    }
}
