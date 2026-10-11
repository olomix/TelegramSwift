import XCTest
import SwiftSignalKit
import TelegramCore
import PasscodeAccessChallenge

// Written by AccountManagerImpl.cleanPasscodeMetadataIfNeeded after a vacuum.
private let passcodeCleanupMarkerName = "passcode-v1-metadata-clean"

final class PasscodeAccessChallengeTests: XCTestCase {
    private var basePath: String!

    override func setUp() {
        super.setUp()
        basePath = NSTemporaryDirectory() + "PasscodeAccessChallengeTests-\(UUID().uuidString)/accounts-metadata"
        try? FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: (basePath as NSString).deletingLastPathComponent)
        super.tearDown()
    }

    private var cleanupMarkerPath: String {
        return basePath + "/" + passcodeCleanupMarkerName
    }

    private func openManager(isReadOnly: Bool = false, accessChallenge: AccountManagerAccessChallenge = .passthrough) -> AccountManager<TelegramAccountManagerTypes> {
        return AccountManager<TelegramAccountManagerTypes>(basePath: basePath, isTemporary: false, isReadOnly: isReadOnly, useCaches: false, removeDatabaseOnError: true, accessChallenge: accessChallenge)
    }

    private func run<T>(_ manager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (AccountManagerModifier<TelegramAccountManagerTypes>) -> T) -> T {
        let done = expectation(description: "transaction")
        var result: T?
        let disposable = manager.transaction(f).start(next: { value in
            result = value
        }, completed: {
            done.fulfill()
        })
        wait(for: [done], timeout: 10)
        disposable.dispose()
        return result!
    }

    private func storedMarker(isReadOnly: Bool = false) -> PostboxAccessChallengeData {
        let manager = openManager(isReadOnly: isReadOnly)
        return run(manager) { $0.getAccessChallengeData() }
    }

    func testStoredMarkerIsReadBack() {
        let manager = openManager()
        run(manager) { $0.storeAccessChallengeData(.plaintextPassword(value: "")) }
        XCTAssertEqual(run(manager) { $0.getAccessChallengeData() }, .plaintextPassword(value: ""))
    }

    func testStoredMarkerSurvivesReopen() {
        run(openManager()) { $0.storeAccessChallengeData(.plaintextPassword(value: "")) }
        XCTAssertEqual(storedMarker(), .plaintextPassword(value: ""))
        XCTAssertEqual(storedMarker(isReadOnly: true), .plaintextPassword(value: ""))
    }

    func testStoringNoneClearsMarker() {
        let manager = openManager()
        run(manager) { $0.storeAccessChallengeData(.plaintextPassword(value: "")) }
        run(manager) { $0.storeAccessChallengeData(.none) }
        XCTAssertEqual(run(manager) { $0.getAccessChallengeData() }, .none)
        XCTAssertEqual(storedMarker(), .none)
        XCTAssertEqual(storedMarker(isReadOnly: true), .none)
    }

    // Pins the core contract behind the wrapper: a plain set is dropped.
    func testPlainSetIsDropped() {
        let manager = openManager()
        run(manager) { $0.setAccessChallengeData(.plaintextPassword(value: "")) }
        XCTAssertEqual(run(manager) { $0.getAccessChallengeData() }, .none)
    }

    func testExistingMarkersOpenUnchanged() {
        let markers: [PostboxAccessChallengeData] = [
            .numericalPassword(value: "1234"),
            .secured(id: "passcode", kind: .digits6)
        ]
        for marker in markers {
            run(openManager()) { $0.storeAccessChallengeData(marker) }
            XCTAssertEqual(storedMarker(), marker)
            XCTAssertEqual(storedMarker(isReadOnly: true), marker)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupMarkerPath))
        }
    }

    // Keeps the check above meaningful if the core renames its marker file.
    func testCoreWritesCleanupMarkerAtExpectedPath() {
        let resolving = AccountManagerAccessChallenge(
            prepare: { _ in },
            resolve: { current, _ in current ?? PostboxAccessChallengeData.none },
            finishInitialization: {}
        )
        let manager = openManager(accessChallenge: resolving)
        XCTAssertEqual(run(manager) { $0.getAccessChallengeData() }, .none)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cleanupMarkerPath))
    }
}
