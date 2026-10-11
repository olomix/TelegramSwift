#!/bin/bash
# Standalone regression runner for the libprisma tokenizer recursion bound
# (patches/libprisma/tokenize-depth-limit.patch).
#
# Compiles the four Mac libprisma C++ sources together with tests/libprisma/
# RecursionTests.cpp and the vendored Boost.Regex (submodules/regex, used
# header-only plus its src implementations), builds debug and optimized
# variants in a temporary directory, and runs each variant against the Mac
# grammars blob with a hard execution timeout. Crashes (SIGSEGV and friends)
# and timeouts are reported as failures.
#
# The runner never touches the submodule state and never applies patches:
# apply patches/libprisma/tokenize-depth-limit.patch to submodules/libprisma
# yourself (or via scripts/configure_frameworks.sh, which picks the patch up
# from patches/libprisma) before expecting a green run.
#
# Usage:
#   scripts/test-libprisma.sh                     (also verifies the tracked
#                                                 benign baseline
#                                                 tests/libprisma/benign-tokens.golden)
#   scripts/test-libprisma.sh --record FILE   write the benign token-tree
#                                             baseline to FILE (one write per
#                                             variant; identical content)
#   scripts/test-libprisma.sh --verify FILE   compare benign token trees
#                                             against the FILE baseline

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." >/dev/null && pwd )"

LIBPRISMA="$REPO_ROOT/submodules/libprisma/libprisma"
BOOST_REGEX_INCLUDE="$REPO_ROOT/submodules/regex/include"
BOOST_REGEX_SRC="$REPO_ROOT/submodules/regex/src"
TEST_SRC="$REPO_ROOT/tests/libprisma/RecursionTests.cpp"
GRAMMARS="$LIBPRISMA/grammars.dat"

TIMEOUT_SECONDS=10
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --record|--verify)
            if [ $# -lt 2 ]; then
                echo "error: $1 needs a file argument" >&2
                exit 2
            fi
            EXTRA_ARGS+=("$1" "$2")
            shift 2
            ;;
        *)
            echo "error: unknown argument $1 (supported: --record FILE, --verify FILE)" >&2
            exit 2
            ;;
    esac
done

FAILURES=0

for FILE in "$TEST_SRC" "$GRAMMARS" \
    "$LIBPRISMA/Highlight.cpp" "$LIBPRISMA/SyntaxHighlighter.cpp" \
    "$LIBPRISMA/TokenList.cpp" "$LIBPRISMA/LanguageTree.cpp" \
    "$BOOST_REGEX_INCLUDE/boost/regex.hpp" \
    "$BOOST_REGEX_SRC/regex.cpp" "$BOOST_REGEX_SRC/static_mutex.cpp" \
    "$BOOST_REGEX_SRC/posix_api.cpp" "$BOOST_REGEX_SRC/wide_posix_api.cpp"; do
    if [ ! -f "$FILE" ]; then
        echo "error: missing $FILE; check submodules are checked out" >&2
        exit 1
    fi
done

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/libprisma-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Run a built variant under a hard timeout. A timeout or a death by signal
# (e.g. the pre-fix stack overflow) is reported as a failure.
run_variant() {
    local label="$1"
    local binary="$2"
    shift 2
    "$binary" "$@" &
    local pid=$!
    local deadline=$(( TIMEOUT_SECONDS * 4 ))
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$deadline" ]; do
        sleep 0.25
        waited=$(( waited + 1 ))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        echo "FAIL: $label timed out after ${TIMEOUT_SECONDS}s" >&2
        FAILURES=$(( FAILURES + 1 ))
        return
    fi
    wait "$pid"
    local status=$?
    if [ "$status" -ge 128 ]; then
        echo "FAIL: $label died from signal $(( status - 128 ))" >&2
        FAILURES=$(( FAILURES + 1 ))
    elif [ "$status" -ne 0 ]; then
        echo "FAIL: $label exited with status $status" >&2
        FAILURES=$(( FAILURES + 1 ))
    else
        echo "ok: $label passed"
    fi
}

# Compile a variant; sources first so failures are easier to read.
build_variant() {
    local subdir="$1"
    local flags
    read -ra flags <<< "$2"
    mkdir -p "$BUILD_DIR/$subdir"
    local objects=()
    local source
    for source in "$LIBPRISMA/Highlight.cpp" "$LIBPRISMA/SyntaxHighlighter.cpp" \
        "$LIBPRISMA/TokenList.cpp" "$LIBPRISMA/LanguageTree.cpp" \
        "$BOOST_REGEX_SRC/regex.cpp" "$BOOST_REGEX_SRC/static_mutex.cpp" \
        "$BOOST_REGEX_SRC/posix_api.cpp" "$BOOST_REGEX_SRC/wide_posix_api.cpp" \
        "$TEST_SRC"; do
        local object
        object="$BUILD_DIR/$subdir/$(basename "$source" .cpp).o"
        local extra_flags=()
        if [ "$source" = "$TEST_SRC" ]; then
            # Point default-mode runs at the tracked benign baseline.
            extra_flags=("-DTESTS_BENIGN_GOLDEN_PATH=\"${REPO_ROOT}/tests/libprisma/benign-tokens.golden\"")
        fi
        if ! xcrun clang++ "${flags[@]}" ${extra_flags[@]+"${extra_flags[@]}"} \
            -I"$BOOST_REGEX_INCLUDE" -I"$LIBPRISMA" \
            -c "$source" -o "$object"; then
            echo "error: compiling $(basename "$source") ($subdir) failed" >&2
            FAILURES=$(( FAILURES + 1 ))
            return 1
        fi
        objects+=("$object")
    done
    if ! xcrun clang++ "${objects[@]}" -o "$BUILD_DIR/$subdir/RecursionTests"; then
        echo "error: linking RecursionTests ($subdir) failed" >&2
        FAILURES=$(( FAILURES + 1 ))
        return 1
    fi
}

echo "Building debug and optimized variants in $BUILD_DIR"
build_variant debug "-std=c++17 -O0 -g" || true
build_variant opt "-std=c++17 -O2" || true

if [ "$FAILURES" -ne 0 ]; then
    echo "libprisma recursion tests: $FAILURES failure(s) (build)" >&2
    exit 1
fi

for VARIANT in debug opt; do
    run_variant "$VARIANT variant" "$BUILD_DIR/$VARIANT/RecursionTests" \
        "$GRAMMARS" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
done

if [ "$FAILURES" -ne 0 ]; then
    echo "libprisma recursion tests: $FAILURES failure(s)" >&2
    exit 1
fi
echo "libprisma recursion tests: all variants passed"