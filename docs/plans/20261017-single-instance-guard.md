# Single-instance guard

## Overview
- Two copies of the app on the same data crash: Postbox runs
  `BEGIN IMMEDIATE` on the shared SQLCipher database, gets SQLITE_BUSY
  from the other copy's write lock and asserts
  (`SqliteValueBox.swift:40`). Seen 2026-10-11 and 2026-10-16 (old
  `Telegram.app` plus `Telex.app`).
- macOS blocks a second copy only for a Finder/Dock launch of the same
  bundle path. A bundle at another path, a terminal launch of the binary or
  `open -n` all bypass it.
- Fix: the main app takes an exclusive `flock` on `<group root>/app.lock`
  as the first step of `applicationDidFinishLaunching`. If another process
  holds it, show an alert, activate the running copy and quit.
- One lock for every build type: Debug (`debug/`) and Release (`stable/`)
  have separate account databases but share files at the group root
  (`api-credentials.json`, notification files, the legacy data move).

## Context (from discovery)
- `Telegram-Mac/AppDelegate.swift:369` `applicationDidFinishLaunching`:
  `moveLegacyDataIntoAppGroup()` runs first, then `ApiEnvironment.containerURL`,
  `TempBox`, the crash handler and at :557 `AccountManager`. The lock must
  come before the data move.
- `ApiEnvironment.dataRootURL` (`packages/ApiCredentials/Sources/ApiCredentials/Config.swift:36`)
  is the app group container root.
- `Telegram-Mac/AppRelauncher.swift` starts a `/bin/sh` helper that waits
  for this process to exit, then runs `open -n`. The helper must not
  inherit the lock fd, or the relaunched copy would find the lock held.
- `showDataMoveFailedAlert()` (`AppDelegate.swift:351`) is the pattern for
  an untranslated startup alert: the language pack lives in the data folder
  and is not loaded yet.
- Testable logic lives in SwiftPM packages; `packages/FoundationUtils` has
  no dependencies and an XCTest target. `appName` is in
  `Telegram-Mac/System.swift:22`.
- The TelegramShare extension is out of scope: it must keep working while
  the app runs.

## Development Approach
- **testing approach**: Regular (code first, then tests)
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes
  in that task
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**

## Testing Strategy
- **unit tests**: `cd packages/FoundationUtils && swift test`
- **build check**: `xcodebuild -workspace Telegram-Mac.xcworkspace -scheme
  Telegram -configuration Debug -destination 'platform=macOS,arch=arm64'
  -derivedDataPath ~/build/TelegramSwift build`
- **e2e**: none in the project; a terminal two-launch check (Task 3) plus
  manual scenarios in Post-Completion.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- keep plan in sync with actual work done

## Solution Overview
- `ProcessLock` in FoundationUtils wraps `open(O_RDWR|O_CREAT|O_CLOEXEC)`
  plus `flock(LOCK_EX|LOCK_NB)`. The instance owns the fd; the app keeps it
  for the process lifetime. The kernel drops the lock on exit or crash, so
  there are no stale lock files to clean up.
- `O_CLOEXEC` keeps the fd out of child processes such as the relaunch
  helper.
- An `flock` lock belongs to the open file description, so a second
  `open` + `flock` in the same process fails like another process would.
  The unit tests rely on this.
- If the lock file cannot be opened (no group container, I/O error), log
  and start anyway: a broken lock must never keep the user out of the app.
- Builds made before this change never take the lock, so an old build
  (e.g. an old `Telegram.app`) can still run next to a new one. Users must
  delete old builds; the docs say so.
- Known limitation: a refused copy started with a `tg://` link quits and the
  link is lost (`handleURLEvent` stores it before launch). Forwarding it to
  the running copy is out of scope.

## Technical Details
- API (names may be adjusted during implementation):
  ```swift
  public final class ProcessLock {
      /// nil when another open file description holds the lock.
      /// Throws when the file cannot be opened or locked for another reason.
      public static func acquire(at url: URL) throws -> ProcessLock?
      internal let fd: Int32     // read by tests (@testable import)
      // deinit closes fd, which releases the lock
  }
  ```
- `flock` returning `EWOULDBLOCK` → `nil`; other errno → throw with the
  errno. No `EINTR` loop: `LOCK_NB` does not block.
- App flow at the top of `applicationDidFinishLaunching`:
  1. `ApiEnvironment.dataRootURL` → `app.lock`; nil root → skip the guard
     (the existing container check alerts later).
  2. `ProcessLock.acquire` → store in an `AppDelegate` property.
  3. Held → write one line to stderr (`FileHandle.standardError`, not
     `print`), `NSApp.activate()` so the alert is not hidden behind a
     terminal, show an `NSAlert` ("\(appName) is already running",
     untranslated, one OK button). After it closes, find the other
     `NSRunningApplication` with the same bundle ID (excluding our pid),
     `NSApp.yieldActivation(to: other)` then `other.activate()` (macOS 14+
     cooperative activation; the deployment target is 27.0, so
     `.activateIgnoringOtherApps` does nothing), then `NSApp.terminate(nil)`
     and return.
  4. Throws → `NSLog` and continue.
- Quitting this early is already safe, no change needed:
  `applicationShouldTerminate` sees a nil `contextValue`,
  `applicationWillTerminate` guards `containerUrl` (:1584), the
  `crashIntermediateDate` timer is scheduled after the lock, and `SPARKLE`
  is not defined.

## What Goes Where
- **Implementation Steps**: the lock type, its tests, the AppDelegate wiring,
  docs.
- **Post-Completion**: manual launch scenarios from Finder and `open -n`.

## Implementation Steps

### Task 1: Add ProcessLock to FoundationUtils

**Files:**
- Create: `packages/FoundationUtils/Sources/FoundationUtils/ProcessLock.swift`
- Create: `packages/FoundationUtils/Tests/FoundationUtilsTests/ProcessLockTests.swift`

- [x] implement `ProcessLock.acquire(at:)` with `O_RDWR|O_CREAT|O_CLOEXEC`,
      `flock(LOCK_EX|LOCK_NB)`, nil on `EWOULDBLOCK`, throw otherwise; close
      the fd on every failure path
- [x] close the fd in `deinit`; expose it as `internal let fd`
- [x] write tests: first acquire succeeds and creates the file; second
      acquire on the same path returns nil while the first is held
- [x] write tests: acquire succeeds again after the first lock is
      deallocated; `fcntl(lock.fd, F_GETFD)` has `FD_CLOEXEC` set
- [x] write tests: acquire in a missing directory throws
- [x] write a test that another process cannot take the lock while this one
      holds it: run `/usr/bin/perl -MFcntl=:flock -e 'open F, ">>",
      $ARGV[0] or exit 2; exit(flock(F, LOCK_EX|LOCK_NB) ? 0 : 1)'` via
      `Process` and expect exit 1 (0 after the lock is deallocated); fail if
      `/usr/bin/perl` is missing (review: no silent skip)
- [x] ➕ review: throw `POSIXError` instead of a custom error type; add
      `waitingUpTo:` retry; tests for ENOENT, fd closed on the busy path,
      lock freed when a holding process is killed, `Process` child not
      keeping the lock, retry success and timeout
- [x] run `cd packages/FoundationUtils && swift test` — must pass

### Task 2: Guard app startup with the lock

**Files:**
- Modify: `Telegram-Mac/AppDelegate.swift`

- [x] add a stored `ProcessLock?` property on `AppDelegate`
- [x] at the very top of `applicationDidFinishLaunching`, before
      `moveLegacyDataIntoAppGroup()`, take the lock on
      `<dataRootURL>/app.lock`
- [x] when held: write the stderr line, `NSApp.activate()`, show the
      untranslated alert, then `NSApp.yieldActivation(to:)` + `activate()`
      on the other copy (same bundle ID, other pid), terminate, return
- [x] when acquire throws: `NSLog` and continue
- [x] ➕ review: retry the lock for 1 s (a relaunched copy can start before
      the exiting one closes the fd); after activating the other copy, send
      it a reopen (pid-addressed distributed notification) so a closed window shows
- [x] build the app with the build-check command — must succeed

### Task 3: Verify acceptance criteria
- [x] launch the Debug binary from a terminal
      (`~/build/TelegramSwift/Build/Products/Debug/Telex.app/Contents/MacOS/Telex &`),
      then launch it a second
      time: the second copy prints the stderr line and shows the alert;
      after dismissing it (or killing it if no screen access) it exits and
      the first copy keeps running
      (verified with a perl `flock` holder standing in for the first copy:
      a pre-guard Debug build was already running on `debug/`, so a full
      guarded first copy would have shared its database. The second copy
      printed the stderr line, showed the alert without opening `debug/`,
      exited on OK)
- [x] ⚠️ quit the first copy and launch again: it starts normally (no stale
      lock) (only partly verified, full app restart moved to
      Post-Completion: after the holder exited, `lsof` showed no
      holder and a new `flock` succeeded; a full app start skipped for the
      same reason)
- [x] ⚠️ check the relaunch helper does not hold the lock: `lsof
      <group root>/app.lock` while the app runs lists only the app pid
      (skipped - needs a full app run next to the running pre-guard build;
      `O_CLOEXEC` and a `Process` child not keeping the lock are covered by
      ProcessLock unit tests; moved to Post-Completion)
- [x] run `cd packages/FoundationUtils && swift test` — must pass
- [x] run the build-check command — must succeed

### Task 4: [Final] Update documentation
- [x] INSTALL.md: replace "Run only one copy of the app at a time; copies
      share the same data folder." with a note that the app refuses a second
      copy (any build type) and why, and that older builds without the
      guard (e.g. an old `Telegram.app`) must be deleted
- [x] remove the single-instance item from `nogit_todo.md`
- [x] update CLAUDE.md if new patterns discovered (none needed)
- [x] leave moving this plan to docs/plans/completed/ to the exec
      completion step

## Post-Completion
*Items requiring manual intervention or external systems - no checkboxes, informational only*

**Manual verification**:
- None of the checks below ran against a real guarded first copy: a
  pre-guard Debug build was running on `debug/` during implementation.
- First delete older builds without the guard (old `Telegram.app` in
  `~/build/TelegramSwift/Build/Products/*` and DerivedData).
- Start the guarded app, start a second copy (alert, first window comes to
  the front even if it was closed), quit, start again (no stale lock).
- Run a Release `Telex.app` and start a Debug build: the Debug copy shows
  the alert, the Release window comes to the front.
- Start a second copy with `open -n Telex.app`: same alert.
- Settings > API credentials change that relaunches the app: the new copy
  starts (the guard does not block `AppRelauncher`; the app retries the
  lock for 1 s before alerting). While the app runs, `lsof
  <group root>/app.lock` lists only the app pid.
- Share extension still works while the app runs.
