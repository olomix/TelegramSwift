import XCTest
@testable import MacPasscode

/// Files written by the old `AppEncryptionParameters` (`BuildConfig.m`):
/// `initWithPath:` then `change:` for a passcode, with the key and salt
/// its `decrypt` returned.
private struct Fixture {
    let passcode: String?
    let file: String
    let key: String
    let salt: String

    var databaseKey: DatabaseKey { DatabaseKey(key: Data(hex: self.key), salt: Data(hex: self.salt))! }

    static let all = [
        Fixture(passcode: nil,
                file: "d7679aab656b89e927daf11bf678d8ec91d02a5be9498f6228d137212f4ae5988c5cb7f3008ca35bdec15ede089b98470bcab993e354581dbb2c3daff0c64633",
                key: "97a9b49def4a7aca653d1ac8cff5e4a612b567a3af94505bed1d069651cce078",
                salt: "13bf06f226d774fb91ef8d7c0fb043a4"),
        Fixture(passcode: "1234",
                file: "c102395304170aaec78801cd790d25dfe74dbc5940e225e87d8a259306b62914142831234c3eefade06e0b0525156ea9997367e65ad0b8f3c191dc84afe59ddb",
                key: "2b98110e3e04ca1eacf3a886840add1eeecb7f15405546a221a5a775eb2529d1",
                salt: "f1ab22fc373283e1e6256578f01b8dd9"),
        Fixture(passcode: "123456",
                file: "e3f618fbec5a40aabc437c310e6f632042d37ce90e1d543cbcfbbf9b6a6b2cf4ca2770568f2e3a629d9174b0fc2d10f589230d93d1caf135e43f513dc2182e90",
                key: "e090885a4e188f8cde3145eccc53ba535d41ed343b2af5adb6a8f91fc3c51090",
                salt: "61df39e4c00bc5f95a60fdf497530f02"),
        Fixture(passcode: "\u{0661}\u{0662}\u{0663}\u{0664}",
                file: "5d55b385f4c659b6b8a419f7e95f98da9f60352d1f3b9918ff1ef02150b9ff862c63dbd323b349d1733b234f4f8ac08cfe404aaf06b65373bae859c73ca168de",
                key: "34aab485ecb473ae03ef50798e7cabe1a0cc1b9f5e363959318f01a9f8522115",
                salt: "b3c1823b80120ed4c9aefcdcc3d6461a"),
        Fixture(passcode: "pa\u{0308}ss word",
                file: "49743609b76292b313587fc7387e53675a1fac403fe4a6b41776f5b7c95efc3c7cc8b2669643afb53e3866732365acfaa863032cae30a3c0dd1c74b15d5e8307",
                key: "eb8da88091ab46cac2595e8f3440c1176ca248e0cbabf42e5bd9f145bc865400",
                salt: "80866057ab22b5a4f6c5e4df8770782f"),
    ]
}

final class LegacyKeyReaderTests: XCTestCase {
    let directory = URL(fileURLWithPath: "/data")

    private func reader(_ fixture: Fixture?) -> (LegacyKeyReader, InMemoryStorage) {
        let storage = InMemoryStorage()
        let reader = LegacyKeyReader(directory: self.directory, storage: storage)
        if let fixture {
            storage.files[reader.encryptedURL] = Data(hex: fixture.file)
        }
        return (reader, storage)
    }

    func testDecryptsFilesWrittenByOldCode() throws {
        for fixture in Fixture.all {
            let (reader, storage) = self.reader(fixture)
            XCTAssertEqual(try reader.state(), .present(needsPasscode: fixture.passcode != nil))
            XCTAssertEqual(try reader.read(passcode: fixture.passcode), fixture.databaseKey)
            XCTAssertTrue(storage.writes.isEmpty)
        }
    }

    func testEncryptPortMatchesOldCodeByteForByte() {
        for fixture in Fixture.all {
            XCTAssertEqual(LegacyFile.encrypt(fixture.databaseKey, passcode: fixture.passcode), Data(hex: fixture.file))
        }
    }

    func testPasscodeBytesAreNotNormalized() throws {
        // The old code hashed the UTF-8 as typed: composed or ASCII forms differ.
        let (decomposed, _) = self.reader(Fixture.all[4])
        XCTAssertNil(try decomposed.read(passcode: "p\u{00E4}ss word"))
        let (arabic, _) = self.reader(Fixture.all[3])
        XCTAssertNil(try arabic.read(passcode: "1234"))
    }

    func testWrongPasscodeReturnsNil() throws {
        let (reader, storage) = self.reader(Fixture.all[1])
        XCTAssertNil(try reader.read(passcode: "1235"))
        XCTAssertNil(try reader.read(passcode: nil))
        XCTAssertTrue(storage.writes.isEmpty)
    }

    func testMissingFileCreatesNothing() throws {
        let (reader, storage) = self.reader(nil)
        XCTAssertEqual(try reader.state(), .missing)
        XCTAssertNil(try reader.read(passcode: nil))
        XCTAssertNil(try reader.read(passcode: "1234"))
        XCTAssertTrue(storage.writes.isEmpty)
        XCTAssertTrue(storage.files.isEmpty)
    }

    func testMissingFileCreatesNothingOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let reader = LegacyKeyReader(directory: directory)
        XCTAssertEqual(try reader.state(), .missing)
        XCTAssertNil(try reader.read(passcode: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testUnreadableFileThrows() {
        let (reader, storage) = self.reader(Fixture.all[0])
        storage.unreadable.insert(reader.encryptedURL)
        XCTAssertThrowsError(try reader.state())
        XCTAssertThrowsError(try reader.read(passcode: nil))
    }

    func testUndecryptableFileNeedsPasscode() throws {
        let (reader, storage) = self.reader(nil)
        storage.files[reader.encryptedURL] = Data(repeating: 7, count: 63)
        XCTAssertEqual(try reader.state(), .present(needsPasscode: true))
        XCTAssertNil(try reader.read(passcode: "1234"))
    }

    func testPlaintextKeyOverridesEncryptedFile() throws {
        let (reader, storage) = self.reader(Fixture.all[1])
        let plain = DatabaseKey.random()
        storage.files[reader.plaintextURL] = plain.bytes
        XCTAssertEqual(try reader.state(), .present(needsPasscode: false))
        XCTAssertEqual(try reader.read(passcode: nil), plain)
        XCTAssertNil(try reader.read(passcode: "1234"))
    }

    func testPlaintextKeyOfOtherLengthIsIgnored() throws {
        let (reader, storage) = self.reader(nil)
        storage.files[reader.plaintextURL] = Data(count: 32)
        XCTAssertEqual(try reader.state(), .missing)
    }

    func testRetireLeavesUndecryptableFile() throws {
        for fixture in Fixture.all {
            let (reader, storage) = self.reader(fixture)
            storage.files[reader.plaintextURL] = DatabaseKey.random().bytes
            try reader.retire()
            let retired = try XCTUnwrap(storage.files[reader.encryptedURL])
            XCTAssertEqual(retired.count, 64)
            XCTAssertNil(storage.files[reader.plaintextURL])
            XCTAssertEqual(try reader.state(), .retired)
            XCTAssertNil(try reader.read(passcode: nil))
            XCTAssertNil(try reader.read(passcode: fixture.passcode))
            XCTAssertNil(LegacyKeyReader.decrypt(retired, passcode: LegacyKeyReader.defaultPasscode))
        }
    }

    func testRetireWithoutFileStillWritesMarker() throws {
        let (reader, storage) = self.reader(nil)
        storage.files[reader.plaintextURL] = DatabaseKey.random().bytes
        try reader.retire()
        XCTAssertEqual(try reader.state(), .retired)
    }
}
