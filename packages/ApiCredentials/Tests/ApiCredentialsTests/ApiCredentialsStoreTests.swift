import XCTest
@testable import ApiCredentials

final class ApiCredentialsStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ApiCredentialsStore!
    private let values = ApiCredentialsValues(apiId: 12345, apiHash: "0123456789abcdef0123456789abcdef")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ApiCredentialsStore(fileURL: directory.appendingPathComponent("api-credentials.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTrip() throws {
        try store.save(values)
        XCTAssertEqual(store.load(), values)
    }

    func testSaveOverwritesPreviousValues() throws {
        try store.save(values)
        let updated = ApiCredentialsValues(apiId: 777, apiHash: "ffffffffffffffffffffffffffffffff")
        try store.save(updated)
        XCTAssertEqual(store.load(), updated)
    }

    func testSaveCreatesMissingParentDirectory() throws {
        let nested = ApiCredentialsStore(fileURL: directory.appendingPathComponent("a/b/api-credentials.json"))
        try nested.save(values)
        XCTAssertEqual(nested.load(), values)
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(store.load())
    }

    func testCorruptJSONLoadsNil() throws {
        try Data("{not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
    }

    func testWrongShapeJSONLoadsNil() throws {
        try Data(#"{"apiId":"12345"}"#.utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
    }

    func testSavedFileIsOwnerReadWriteOnly() throws {
        try store.save(values)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o600)
    }

    func testRemoveDeletesFile() throws {
        try store.save(values)
        store.remove()
        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testRemoveWithoutFileDoesNothing() {
        store.remove()
        XCTAssertNil(store.load())
    }
}
