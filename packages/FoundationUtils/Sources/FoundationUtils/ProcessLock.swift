import Foundation

/// An exclusive `flock` on a file, held for the lifetime of the instance.
///
/// The kernel releases the lock when the fd closes, including on exit or
/// crash, so a lock file left on disk is never stale. The fd is opened with
/// `O_CLOEXEC` so child processes do not inherit the lock.
public final class ProcessLock {
    let fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        close(fd)
    }

    /// Takes the lock on the file at `url`, creating the file if needed.
    ///
    /// - Parameter timeout: how long to keep retrying, every 100 ms, while
    ///   another holder has the lock. Zero tries once.
    /// - Returns: the held lock, or nil when another open file description
    ///   (another process, or another acquire in this one) still holds it.
    /// - Throws: `POSIXError` when the file cannot be opened or locked for
    ///   any other reason.
    public static func acquire(at url: URL, waitingUpTo timeout: TimeInterval = 0) throws -> ProcessLock? {
        // Monotonic, so a wall-clock change cannot stretch the wait.
        let deadline = DispatchTime.now() + timeout
        while true {
            if let lock = try tryAcquire(path: url.path) {
                return lock
            }
            if DispatchTime.now() >= deadline {
                return nil
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private static func tryAcquire(path: String) throws -> ProcessLock? {
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        if fd < 0 {
            throw posixError(errno)
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK {
                return nil
            }
            throw posixError(code)
        }
        return ProcessLock(fd: fd)
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        return POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
