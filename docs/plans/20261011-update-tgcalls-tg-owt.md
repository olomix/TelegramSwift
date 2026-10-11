# Update tgcalls and tg_owt

## Overview
- Move `submodules/tgcalls` to the commit upstream iOS uses
  (TelegramMessenger/tgcalls `ios-13.0.0` = `a024eaab`, 2026-09-22) and
  `submodules/tg_owt` to desktop-app/tg_owt master (`d1cf250e`,
  2026-10-07, the same commit tdesktop pins).
- Why:
  - Our tgcalls (`5ddc3ccf20`, 2025-06-17) is 76 commits behind iOS. Calls
    between this Mac build and current phones are the most likely thing
    to break quietly.
  - Our pinned commit is on no branch of `overtake/tgcalls`, the URL in
    `.gitmodules`, so a fresh clone may not be able to fetch it.
  - tg_owt is 33 commits behind.
- Keep current call behaviour. No new call UI.
- **No automatic fallback.** If iOS tgcalls cannot be made to build
  against tg_owt with small fixes, stop and report. The user then decides
  whether to switch to the tdesktop pair: tgcalls `development` =
  `1c236c09` with the same tg_owt.

## Context (from discovery)
- Mac call stack:
  - `submodules/tgcalls` is built as a SwiftPM package (`Package.swift`,
    `macos/` Objective-C wrappers).
  - It is built against WebRTC from `submodules/tg_owt`, which
    `core-xprojects/webrtc` compiles.
  - The Swift side is `Telegram-Mac/OngoingCallContext.swift` (versions,
    `maxLayer`, context creation) plus group-call code.
- iOS builds tgcalls against a different WebRTC (`ali-fareed/webrtc`).
  The review checked that all 281 WebRTC includes the non-excluded
  tgcalls sources use exist in tg_owt `d1cf250e`, including the DTLS
  transport API `MtProtoDtlsTransport` overrides. tdesktop builds
  `development` against this tg_owt, so WebRTC API errors are unlikely.
- The real build risk is SwiftPM: `Package.swift` uses `path: "."`, so it
  compiles every new `.cpp` that is not excluded. At `a024eaab` that is 17
  files under `tgcalls/v2wasm` and `tools`:
  - they include WAMR's `wasm_export.h`, which tgcalls does not vendor
    (iOS gets it from `//third-party/wamr`)
  - `CallCoreHost.cpp` uses `kReferenceCoreWasm`, made by a Bazel genrule
  - `reference_core_factory.cpp` and `variant_core_factory.cpp` both
    define `createModuleCore`
  - `tools/cli/main.cpp` has a `main()`
- Nothing outside `tgcalls/v2wasm` includes it. The Mac wrapper
  (`macos/Sources/OngoingCallThreadLocalContext.mm`) registers only
  `InstanceImpl`, `InstanceV2Impl` and `InstanceV2ReferenceImpl`, so
  versions 14, 18 and 19 can't be reached on Mac, and excluding the
  folder loses nothing.
- The two upstream tgcalls branches have diverged since `efd330c`
  (2026-09-04):
  - `ios-13.0.0` has 20 commits that `development` lacks: group
    ReferenceImpl fixes and the MtProto-in-DTLS transport.
  - `development` has 2 decompression-limit fixes that `ios-13.0.0`
    lacks (`6d5ce90`, `1c236c0`).
- Local patches:
  - `patches/tgcalls/group-call-is-broadcast.patch` is only partly
    upstream. `a024eaab` has the `bool isBroadcast` header field,
    `GroupNetworkState.connectionMode` and its assignment. It lacks the
    `.mm` mapping `mappedState.isBroadcast = …GroupConnectionModeBroadcast`
    and maybe the change-detection clause in `GroupInstanceCustomImpl.cpp`.
    Without the mapping `isBroadcast` is uninitialized in Swift. The patch
    must be regenerated with what is still missing, not deleted.
  - `patches/tg_owt/candidate-lifetimebound.patch` is upstream in tg_owt
    `89df288d`; `d1cf250e` no longer has the attribute. Delete it, or the
    configure loop would skip it silently forever.
- `scripts/configure_frameworks.sh` applies `patches/*/*.patch`. The
  WebRTC Xcode project runs its build script only when
  `core-xprojects/webrtc/build` is missing, so the old build must be
  deleted.
- tg_owt's nested submodules (abseil-cpp, crc32c, libsrtp, libyuv) are
  at the same commits in `be39b8c8` and `d1cf250e`, with https URLs.
- tg_owt `d1cf250e` no longer forces `CMAKE_OSX_DEPLOYMENT_TARGET 10.13`;
  it takes the target from Xcode's environment (27.0, same as the app).
  Harmless; noted in case the linker warns about deployment targets.
- `.gitmodules` URLs:
  - tgcalls: `git@github.com:overtake/tgcalls.git`
  - tg_owt: `git@github.com:desktop-app/tg_owt.git`
- Both submodules have `ignore = dirty`. Use `git -C submodules/<name>
  status` to see their trees.

## Development Approach
- **testing approach**: Regular (code first, then tests). The call code
  has no unit tests. Verification is building the native libraries,
  `swift build` of the tgcalls package where possible, the Debug and
  Release app builds, and the existing package tests. Real calls are a
  manual post-completion check.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include its verification** (build or test)
  before it is marked done
- **CRITICAL: all builds and tests must pass before starting the next
  task**, no exceptions
- **CRITICAL: update this plan file when scope changes during
  implementation**
- **Stop rule:** if tgcalls `a024eaab` needs more than small fixes to
  build against tg_owt (for example, porting WebRTC APIs into tg_owt),
  stop. Mark the task ⚠️ with the exact errors, log a `[deviation]`, and
  do not switch to the tdesktop pair on your own.

## Testing Strategy
- **builds**:
  - `CMAKE_POLICY_VERSION_MINIMUM=3.5 bash scripts/configure_frameworks.sh`
  - Debug and Release:
    ```
    xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
      -configuration Debug -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath ~/build/TelegramSwift -allowProvisioningUpdates build
    ```
- **unit tests** (regression only, once in Task 4; they don't touch
  calls):
  - `cd packages/FoundationUtils && swift test`
  - `cd packages/ApiCredentials && swift test`
  - `cd packages/PasscodeAccessChallenge && swift test`
- **e2e tests**: none. Calls are checked manually (Post-Completion).

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope
- keep plan in sync with actual work done

## Solution Overview
- Point the tgcalls submodule at TelegramMessenger/tgcalls over https.
  That repo has both `ios-13.0.0` and `development`, so either pin can be
  fetched by anyone. Point tg_owt at https as well, so a clone needs no
  GitHub SSH key.
- Move tg_owt first and rebuild WebRTC with the current tgcalls. That
  separates tg_owt breakage from tgcalls breakage.
- Then move tgcalls, drop the patch that upstream now contains, and fix
  the Mac call sites.
- Check which call versions the Mac now advertises (including 18.0.0 and
  19.0.0, the native and wasm cores). Record the list; don't change it
  unless a version fails to build.

## Technical Details
- Pins:
  - tgcalls `a024eaabf13c189d9577a14fb244bd242825ac96`
  - tg_owt `d1cf250ea73de26c4c1f0a3c8173eb2648efbb04`
- Rollback pins (current):
  - tgcalls `5ddc3ccf20`
  - tg_owt `be39b8c8d0db1f377118f813f0c4bd331d341d5e`
- Alternative tgcalls pin if the user chooses it later: `1c236c09`
  (`development`).
- After changing a URL in `.gitmodules`, run `git submodule sync
  submodules/<name>` so the local config follows.
- The tgcalls submodule working tree has local changes (patches applied)
  and untracked `.swiftpm/xcode/xcuserdata/`. Reverse the patch before
  checkout; leave xcuserdata alone. `SharedHeaders/` is gitignored, survives
  checkout and is refreshed by the `configure_frameworks.sh` rerun.

## What Goes Where
- **Implementation Steps**: `.gitmodules`, gitlinks, patches,
  `core-xprojects/webrtc` build, Mac call-site fixes, docs.
- **Post-Completion**: real 1:1 and group calls with phones and desktop.

## Implementation Steps

### Task 1: Move tg_owt to master and rebuild WebRTC

**Files:**
- Modify: `.gitmodules` (tg_owt URL → https)
- Modify: `submodules/tg_owt` (gitlink)
- Delete: `patches/tg_owt/candidate-lifetimebound.patch`
- ➕ Modify: `core-xprojects/webrtc/webrtc/build.sh` (pin
  `CMAKE_OSX_DEPLOYMENT_TARGET=10.13`)

- [x] reverse `patches/tg_owt/*.patch` in the submodule, change the URL
      to `https://github.com/desktop-app/tg_owt.git`, `git submodule sync`
      (global `insteadOf` still rewrites https to ssh locally; harmless)
- [x] check out `d1cf250e` and run
      `git -C submodules/tg_owt submodule update --init --recursive`
      (safety; the nested commits don't change)
- [x] delete `patches/tg_owt/candidate-lifetimebound.patch` (upstream in
      `89df288d`); confirm `src/api/candidate.h` has no
      `ABSL_ATTRIBUTE_LIFETIME_BOUND` on `set_type` (only the constructor
      parameter keeps it)
- [x] delete `core-xprojects/webrtc/build` and rerun
      `configure_frameworks.sh`; WebRTC must build
      (first run failed: with Xcode's 27.0 target, `CGDisplayCreateImage`,
      `CGWindowListCreateImage`, `CGDisplayStream*` are unavailable in
      `desktop_capture/mac`; fixed by passing
      `-DCMAKE_OSX_DEPLOYMENT_TARGET=10.13` in `build.sh`, which tg_owt
      itself forced before `65d3d606`)
- [x] Debug app build with the OLD tgcalls must succeed. If tgcalls fails
      only because of tg_owt API changes, record the errors (⚠️). They
      are expected to go away with the new tgcalls in Task 2, so continue
      to Task 2 without fixing old tgcalls (succeeded, no tgcalls errors)

### Task 2: Move tgcalls to ios-13.0.0

**Files:**
- Modify: `.gitmodules` (tgcalls URL →
  `https://github.com/TelegramMessenger/tgcalls.git`)
- Modify: `submodules/tgcalls` (gitlink)
- Modify: `patches/tgcalls/group-call-is-broadcast.patch` (keep only
  what upstream lacks)
- Create: `patches/tgcalls/package-exclude-v2wasm-tools.patch`

- [x] reverse `patches/tgcalls/*.patch` in the submodule, change the URL,
      `git submodule sync`, fetch, and check out `a024eaab`
      (URL change committed; the old pin `5ddc3ccf20` is an ancestor of
      upstream `development` and `ios-13.0.0`, so it fetches from there.
      ⚠️ gitlink rolled back to `5ddc3ccf20` after the stop rule below)
- [x] regenerate `group-call-is-broadcast.patch` with only what
      `a024eaab` lacks: the `.mm` mapping `mappedState.isBroadcast = …`
      (near line 1510) and, if upstream's own clause near line 2847 does
      not already cover it, the connection-mode change detection in
      `GroupInstanceCustomImpl.cpp`. Then grep the `.mm` to confirm
      `isBroadcast` is set
      (only the one-line `.mm` mapping is needed; upstream's
      `setConnectionMode` clause covers change detection. ⚠️ not committed:
      the old full patch stays while the gitlink is on `5ddc3ccf20`)
- [x] create `patches/tgcalls/package-exclude-v2wasm-tools.patch` that adds
      `"tgcalls/v2wasm"` and `"tools"` to `exclude:` in `Package.swift`.
      Do not build or vendor WAMR
      (also needed `"tgcalls/group/GroupInstanceReferenceImpl.cpp"`: it uses
      `OnUnDemuxableRtpPacket` and `RTCConfiguration::
      disable_payload_type_demuxing` from the iOS WebRTC; only `tools/cli`
      uses it. ⚠️ not committed, it only applies to `a024eaab`)
- [x] rerun `configure_frameworks.sh` (patch loop) and build the Debug
      app; collect errors (configure OK; Debug build fails in
      `TgVoipWebrtc`, see below)
- [x] ⚠️ **STOP RULE APPLIED.** Errors come from WebRTC APIs missing in
      tg_owt `d1cf250e`, in `InstanceV2ReferenceImpl.cpp`, which the Mac
      wrapper registers (`Register<InstanceV2ReferenceImpl>`), so it cannot
      be excluded:
      ```
      tgcalls/v2/InstanceV2ReferenceImpl.cpp:503:28: error: no member named
        'external_transport_security' in
        'webrtc::PeerConnectionFactoryInterface::Options'
      tgcalls/v2/InstanceV2ReferenceImpl.cpp:776:40: error: no member named
        'dtls_transport_factory' in 'webrtc::PeerConnectionDependencies'
      ```
      Both are the MtProto-in-DTLS hooks (`8717d34`, `bd22b80`, only on
      `ios-13.0.0`). tg_owt has a DTLS factory only inside
      `JsepTransportController::Config`, not on the public PeerConnection
      API, so fixing it means porting WebRTC APIs into tg_owt. Disabling
      the `network_use_mtproto` path in tgcalls would build but could break
      calls with peers that use it. Not switched to the tdesktop pair
      (`development` `1c236c09`, which lacks the MtProto-in-DTLS commits);
      the user decides. ➕ User decision: port the WebRTC seams into tg_owt
      (Task 3) and keep `ios-13.0.0`

### Task 3: ➕ Port iOS WebRTC "tgcalls seams" into tg_owt and move tgcalls to ios-13.0.0

User decision after the stop rule: carry the hooks iOS's WebRTC fork
(`ali-fareed/webrtc`, checked out at
`submodules/telegram-ios/third-party/webrtc/webrtc`, pinned `6513c71d6c`)
added for tgcalls, as a tg_owt patch. Five commits, about 150 lines:
`58d2ac4281` (Allow SCTP without DTLS; superseded by the next),
`e806a6aa73` (three seams: `Options::external_transport_security`,
`PeerConnectionDependencies::dtls_transport_factory`, …),
`697ab266dc` (forward-declare `DtlsTransportFactory`), `4046a21626`
(release an unnegotiated `sctp_mid` on rollback), `6513c71d6c`
(`RTCConfiguration::disable_payload_type_demuxing`).

**Files:**
- Create: `patches/tg_owt/tgcalls-seams.patch`
- Modify: `submodules/tgcalls` (gitlink → `a024eaab`)
- Modify: `patches/tgcalls/group-call-is-broadcast.patch` (drafted in the
  scratch dir: only the `.mm` mapping)
- Create: `patches/tgcalls/package-exclude-v2wasm-tools.patch` (drafted in
  the scratch dir)

- [x] port the five seam commits onto tg_owt `src/` (`git -C <webrtc> show
      <sha>` and apply with path prefix `src/`, resolving context
      differences by hand); save as `patches/tg_owt/tgcalls-seams.patch`
      (the commits are contiguous, so ported their net diff
      `58d2ac4281^..6513c71d6c`; `58d2ac4281` is fully reverted by
      `e806a6aa73` and contributes nothing. Applied cleanly, 6 files,
      +140/-7)
- [x] if a seam cannot be ported without reworking WebRTC internals
      beyond these commits, apply the **stop rule** (⚠️ with exact errors,
      `[deviation]`, stop) — the fallback (tdesktop pair) is the user's
      call (not needed: every API the seams use already exists in tg_owt)
- [x] delete `core-xprojects/webrtc/build`, rerun
      `configure_frameworks.sh`; WebRTC must build (1451/1451)
- [x] check out tgcalls `a024eaab`, install the two drafted tgcalls patches
      (re-check them; keep `GroupInstanceReferenceImpl.cpp` excluded only
      if it still needs hooks tg_owt lacks), rerun the patch loop
      (exclusion dropped: its hooks are now in the seams, and it compiles;
      the exclude patch only lists `tgcalls/v2wasm` and `tools`)
- [x] Debug app build succeeds; Swift call-site errors, if any, go to
      Task 4 (➕) (BUILD SUCCEEDED, no Swift call-site errors)

### Task 4: Fix Mac call sites for the new tgcalls

**Files:**
- Modify: `Telegram-Mac/OngoingCallContext.swift` and group-call files
  under `Telegram-Mac/` that fail to compile

- [x] fix compile errors in the Mac Swift code with the smallest change
      that keeps current behaviour; new enum cases and fields get neutral
      defaults (none needed: Debug and Release build with no Swift
      errors; the Mac wrapper header gained one line, no Swift-visible
      API change)
- [x] list the call versions the Mac advertises
      (`OngoingCallThreadLocalContextWebrtc.versions`) before and after,
      and record both lists here. They are expected to be the same:
      advertising 14/18/19 would need new instance types registered in
      the Mac wrapper, which is out of scope
      (determined from source, app not launched. Both pins register only
      `InstanceImpl` (2.7.7, 5.0.0), `InstanceV2Impl` (7.0.0, 8.0.0,
      9.0.0, 12.0.0, 13.0.0) and `InstanceV2ReferenceImpl` (10.0.0,
      11.0.0); `versions(withIncludeReference:)` ignores its argument and
      returns all of `Meta::Versions()` sorted as strings, and
      `OngoingCallContext.versions` ignores `includeExperimental` /
      `includeReference`.
      Before `5ddc3ccf20`: 10.0.0, 11.0.0, 12.0.0, 13.0.0, 2.7.7, 5.0.0,
      7.0.0, 8.0.0, 9.0.0.
      After `a024eaab`: the same nine. `maxLayer` stays 92)
- [x] Debug and Release builds succeed; `codesign --verify --deep
      --strict` on the Release app (both BUILD SUCCEEDED, codesign OK;
      package tests pass: FoundationUtils 19, ApiCredentials 40,
      PasscodeAccessChallenge 6)
- [x] launch check is manual (needs the user's account): mark it
      "(needs manual run)" in Post-Completion

### Task 5: Verify acceptance criteria
- [x] `git submodule status` shows tgcalls at `a024eaab` and tg_owt at
      `d1cf250e`, and every `patches/*/*.patch` applies (`git apply
      --check -R` on the current tree) (both commits match; all 8
      patches in telegram-ios, tg_owt and tgcalls reverse-check OK)
- [x] fresh-clone check (needs Tasks 1-3 committed): plain `git clone`
      of the local repo into the scratch directory, then
      `git submodule update --init --recursive submodules/tgcalls
      submodules/tg_owt`; both fetch over https with no SSH key. Delete
      the clone afterwards (run with `GIT_CONFIG_GLOBAL=/dev/null` and
      `GIT_SSH_COMMAND=false`, so no insteadOf rewrite and no SSH
      possible; tgcalls, tg_owt and its nested submodules all cloned
      over https at the pinned commits; clone deleted)
- [x] full test suite: FoundationUtils, ApiCredentials,
      PasscodeAccessChallenge `swift test` (reused Task 4 results:
      no commits or working-tree changes since a1d67511a)
- [x] Debug and Release builds succeed (reused Task 4 results, same
      reason)

### Task 6: [Final] Update documentation
- [x] INSTALL.md: mention that after a tg_owt update
      `core-xprojects/webrtc/build` must be deleted before
      `configure_frameworks.sh` (like ffmpeg) (also notes that
      `patches/tg_owt/tgcalls-seams.patch` must keep applying)
- [x] `nogit_todo.md`: remove the tgcalls and tg_owt items, or update
      them with what is left (one item left: the 2 `development`
      decompression-limit fixes; calls line marked done, pending a
      manual call test)
- [x] move plan (done by orchestrator at completion)

## Post-Completion
*Items requiring manual intervention or external systems - no checkboxes, informational only*

**Manual verification**:
- Launch the Debug app on your account; no crash (needs manual run).
- 1:1 voice and video call with an up-to-date iPhone, both directions.
- Group call / video chat: join, speak, unmute mid-call, screen share.
- If calls fail, the fallback is the tdesktop pair: tgcalls
  `development` `1c236c09` with the same tg_owt.

**Follow-ups**:
- The 2 decompression-limit fixes on `development` (`6d5ce90`,
  `1c236c0`) are not in `ios-13.0.0`. Pick them up when the branches
  merge, or carry them as a patch.
