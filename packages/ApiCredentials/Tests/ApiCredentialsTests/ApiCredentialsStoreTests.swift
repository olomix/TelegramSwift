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

    func testSaveRestrictsPermissionsOfExistingWiderFile() throws {
        try Data("{}".utf8).write(to: store.fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path)
        try store.save(values)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["api-credentials.json"])
    }

    func testFailedSaveKeepsPreviousFile() throws {
        try store.save(values)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        XCTAssertThrowsError(try store.save(ApiCredentialsValues(apiId: 777, apiHash: "ffffffffffffffffffffffffffffffff")))
        XCTAssertEqual(store.load(), values)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["api-credentials.json"])
    }

    func testOutOfRangeValuesLoadNil() throws {
        for json in [#"{"apiId":0,"apiHash":""}"#, #"{"apiId":-5,"apiHash":"XYZ"}"#, #"{"apiId":5,"apiHash":"0123"}"#] {
            try Data(json.utf8).write(to: store.fileURL)
            XCTAssertNil(store.load(), json)
        }
    }

    func testUpperCaseHashLoadsLowerCased() throws {
        try Data(#"{"apiId":12345,"apiHash":"0123456789ABCDEF0123456789ABCDEF"}"#.utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), values)
    }

    func testSaveThrowsWhenParentIsAFile() throws {
        let blocker = directory.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let blocked = ApiCredentialsStore(fileURL: blocker.appendingPathComponent("api-credentials.json"))
        XCTAssertThrowsError(try blocked.save(values))
    }
}
