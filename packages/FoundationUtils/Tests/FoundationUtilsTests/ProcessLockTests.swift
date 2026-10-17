import XCTest
@testable import FoundationUtils

final class ProcessLockTests: XCTestCase {
    private let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private var directory: URL!
    private var lockURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProcessLockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        lockURL = directory.appendingPathComponent("app.lock")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testFirstAcquireSucceedsAndCreatesFile() throws {
        XCTAssertNotNil(try ProcessLock.acquire(at: lockURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    }

    func testSecondAcquireReturnsNilWhileFirstIsHeld() throws {
        let first = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        XCTAssertNil(try ProcessLock.acquire(at: lockURL))
        withExtendedLifetime(first) {}
    }

    func testBusyAcquireClosesItsFd() throws {
        let first = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        let before = try nextFreeFd()
        XCTAssertNil(try ProcessLock.acquire(at: lockURL))
        XCTAssertEqual(try nextFreeFd(), before)
        withExtendedLifetime(first) {}
    }

    func testAcquireSucceedsAfterFirstLockIsDeallocated() throws {
        var first: ProcessLock? = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        first = nil
        XCTAssertNotNil(try ProcessLock.acquire(at: lockURL))
    }

    func testAcquireWaitsForHolderToRelease() throws {
        var first: ProcessLock? = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        let released = expectation(description: "released")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            first = nil
            released.fulfill()
        }
        XCTAssertNotNil(try ProcessLock.acquire(at: lockURL, waitingUpTo: 2))
        wait(for: [released], timeout: 2)
    }

    func testAcquireGivesUpAfterTimeout() throws {
        let first = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        XCTAssertNil(try ProcessLock.acquire(at: lockURL, waitingUpTo: 0.3))
        withExtendedLifetime(first) {}
    }

    func testFdHasCloseOnExec() throws {
        let lock = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        let flags = fcntl(lock.fd, F_GETFD)
        XCTAssertGreaterThanOrEqual(flags, 0)
        XCTAssertNotEqual(flags & FD_CLOEXEC, 0)
    }

    func testAcquireInMissingDirectoryThrowsENOENT() {
        let missing = directory.appendingPathComponent("missing/app.lock")
        XCTAssertThrowsError(try ProcessLock.acquire(at: missing)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOENT)
        }
    }

    func testOtherProcessCannotTakeHeldLock() throws {
        var lock: ProcessLock? = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        XCTAssertEqual(try otherProcessLockStatus(), 1)
        lock = nil
        XCTAssertEqual(try otherProcessLockStatus(), 0)
    }

    func testLockHeldByOtherProcessIsFreedWhenItIsKilled() throws {
        let output = Pipe()
        let holder = perlLockProcess(
            "open F, \">>\", $ARGV[0] or exit 2; flock(F, LOCK_EX) or exit 3; "
                + "$| = 1; print \"ok\\n\"; sleep 30")
        holder.standardOutput = output
        try holder.run()
        defer {
            if holder.isRunning {
                kill(holder.processIdentifier, SIGKILL)
            }
        }
        let line = output.fileHandleForReading.availableData
        XCTAssertEqual(String(decoding: line, as: UTF8.self), "ok\n")

        XCTAssertNil(try ProcessLock.acquire(at: lockURL))
        kill(holder.processIdentifier, SIGKILL)
        holder.waitUntilExit()
        XCTAssertNotNil(try ProcessLock.acquire(at: lockURL))
    }

    func testChildProcessDoesNotKeepLock() throws {
        var lock: ProcessLock? = try XCTUnwrap(ProcessLock.acquire(at: lockURL))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "sleep 5"]
        try child.run()
        defer { child.terminate() }
        lock = nil
        XCTAssertTrue(child.isRunning)
        XCTAssertNotNil(try ProcessLock.acquire(at: lockURL))
    }

    /// Exit status of a perl child trying the lock: 0 taken, 1 busy.
    private func otherProcessLockStatus() throws -> Int32 {
        let process = perlLockProcess(
            "open F, \">>\", $ARGV[0] or exit 2; "
                + "exit(flock(F, LOCK_EX|LOCK_NB) ? 0 : 1)")
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A perl process running `script` with Fcntl's flock constants and the
    /// lock file path as $ARGV[0].
    private func perlLockProcess(_ script: String) -> Process {
        let process = Process()
        process.executableURL = perl
        process.arguments = ["-MFcntl=:flock", "-e", script, lockURL.path]
        return process
    }

    /// The lowest free fd number; open() always returns the lowest one.
    private func nextFreeFd() throws -> Int32 {
        let fd = open("/dev/null", O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        close(fd)
        return fd
    }
}
