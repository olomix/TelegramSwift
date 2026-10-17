import CryptoKit
import XCTest
@testable import MacPasscode

final class DatabaseKeyFileTests: XCTestCase {
    let directory = URL(fileURLWithPath: "/data")
    let sealingKey = SymmetricKey(size: .bits256)

    func testSealRoundTrip() throws {
        let databaseKey = DatabaseKey.random()
        let sealed = try DatabaseKeyFile.seal(databaseKey, with: self.sealingKey)
        XCTAssertEqual(sealed.first, 1)
        XCTAssertEqual(sealed.count, DatabaseKeyFile.sealedLength)
        XCTAssertEqual(try DatabaseKeyFile.unseal(sealed, with: self.sealingKey), databaseKey)
    }

    func testRandomKeysDiffer() {
        XCTAssertNotEqual(DatabaseKey.random(), DatabaseKey.random())
    }

    func testWrongKeyFails() throws {
        let sealed = try DatabaseKeyFile.seal(DatabaseKey.random(), with: self.sealingKey)
        XCTAssertThrowsError(try DatabaseKeyFile.unseal(sealed, with: SymmetricKey(size: .bits256))) {
            XCTAssertEqual($0 as? DatabaseKeyFileError, .authenticationFailed)
        }
    }

    func testTamperedFileFails() throws {
        var sealed = try DatabaseKeyFile.seal(DatabaseKey.random(), with: self.sealingKey)
        sealed[20] ^= 1
        XCTAssertThrowsError(try DatabaseKeyFile.unseal(sealed, with: self.sealingKey)) {
            XCTAssertEqual($0 as? DatabaseKeyFileError, .authenticationFailed)
        }
    }

    func testTruncatedFileFails() throws {
        let sealed = try DatabaseKeyFile.seal(DatabaseKey.random(), with: self.sealingKey)
        for length in [0, 1, 29, sealed.count - 1] {
            XCTAssertThrowsError(try DatabaseKeyFile.unseal(sealed.prefix(length), with: self.sealingKey)) {
                XCTAssertEqual($0 as? DatabaseKeyFileError, .truncated, "length \(length)")
            }
        }
    }

    func testUnknownVersionFails() throws {
        var sealed = try DatabaseKeyFile.seal(DatabaseKey.random(), with: self.sealingKey)
        sealed[0] = 2
        XCTAssertThrowsError(try DatabaseKeyFile.unseal(sealed, with: self.sealingKey)) {
            XCTAssertEqual($0 as? DatabaseKeyFileError, .unknownVersion(2))
        }
    }

    func testWriteThenRead() throws {
        let storage = InMemoryStorage()
        let file = DatabaseKeyFile(directory: self.directory, storage: storage)
        let databaseKey = DatabaseKey.random()
        XCTAssertNil(try file.read(with: self.sealingKey))
        try file.write(databaseKey, with: self.sealingKey)
        XCTAssertEqual(storage.writes, [self.directory.appendingPathComponent("db-key.v2")])
        XCTAssertEqual(try file.read(with: self.sealingKey), databaseKey)
    }

    func testWriteVerifiesWhatLandedOnDisk() {
        let storage = InMemoryStorage()
        storage.corruptWrites = true
        let file = DatabaseKeyFile(directory: self.directory, storage: storage)
        XCTAssertThrowsError(try file.write(DatabaseKey.random(), with: self.sealingKey))
    }

    func testUnreadableFileThrows() {
        let storage = InMemoryStorage()
        let file = DatabaseKeyFile(directory: self.directory, storage: storage)
        storage.unreadable.insert(file.url)
        XCTAssertThrowsError(try file.contents())
    }

    func testDatabaseKeyRejectsWrongLengths() {
        XCTAssertNil(DatabaseKey(key: Data(count: 31), salt: Data(count: 16)))
        XCTAssertNil(DatabaseKey(key: Data(count: 32), salt: Data(count: 15)))
        XCTAssertNotNil(DatabaseKey(key: Data(count: 32), salt: Data(count: 16)))
    }
}

final class LocalKeyFileStorageTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
        try FileManager.default.removeItem(at: self.directory)
    }

    func testMissingFileIsNil() throws {
        XCTAssertNil(try LocalKeyFileStorage().read(self.directory.appendingPathComponent("none")))
    }

    func testUnreadableFileThrowsInsteadOfNil() throws {
        let url = self.directory.appendingPathComponent("locked")
        try Data([1, 2, 3]).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        XCTAssertThrowsError(try LocalKeyFileStorage().read(url))
    }

    func testWriteReadRemove() throws {
        let storage = LocalKeyFileStorage()
        let url = self.directory.appendingPathComponent("file")
        try storage.writeAtomically(Data([1]), to: url)
        try storage.writeAtomically(Data([2]), to: url)
        XCTAssertEqual(try storage.read(url), Data([2]))
        try storage.remove(url)
        try storage.remove(url)
        XCTAssertNil(try storage.read(url))
    }

    func testWriteLeavesNoTemporaryFiles() throws {
        let url = self.directory.appendingPathComponent("file")
        try LocalKeyFileStorage().writeAtomically(Data(count: 100), to: url)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: self.directory.path), ["file"])
    }

    func testFailedWriteKeepsTheOldFile() throws {
        let url = self.directory.appendingPathComponent("file")
        try LocalKeyFileStorage().writeAtomically(Data([1]), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: self.directory.path)
        XCTAssertThrowsError(try LocalKeyFileStorage().writeAtomically(Data([2]), to: url))
        XCTAssertEqual(try LocalKeyFileStorage().read(url), Data([1]))
    }
}
