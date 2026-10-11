// Standalone regression runner for the unbounded-recursion DoS in the Mac
// libprisma code-block syntax highlighter, adapted from the iOS
// submodules/telegram-ios/third-party/libprisma/Tests/SyntaxHighlighterRecursionTests.cpp
// (see the "brightscript" report). A short message whose language is a Prism
// grammar with a token cycle (directive-statement -> expression ->
// directive-statement) drove SyntaxHighlighter::tokenize()/matchGrammar() into
// unbounded mutual recursion and exhausted the thread stack (SIGSEGV into the
// guard page) as soon as the block was highlighted.
//
// The fix bounds the grammar recursion with a depth counter
// (patches/libprisma/tokenize-depth-limit.patch). This test loads the real
// shipped Mac grammars.dat (passed as argv[1] via scripts/test-libprisma.sh)
// and highlights the report's payload; before the fix it crashes, after the
// fix it returns and highlighting stays lossless (the concatenated text is
// unchanged), with the nested syntax capped and terminating in plain text.
//
// Pure C++ host test, following the CHECK_TRUE + main() pattern of the tgcalls
// cc_tests. No gtest dependency. Run with scripts/test-libprisma.sh, which
// builds debug and optimized variants and enforces an execution timeout.
//
// Modes:
//   RecursionTests <grammars.dat>                  run the checks; additionally
//                                                  verify the benign token-tree
//                                                  baseline compiled in as
//                                                  TESTS_BENIGN_GOLDEN_PATH
//                                                  when it exists.
//   RecursionTests <grammars.dat> --record FILE    run the checks and write the
//                                                  serialized benign token
//                                                  trees to FILE.
//   RecursionTests <grammars.dat> --verify FILE    run the checks and compare
//                                                  the serialized benign token
//                                                  trees against FILE.

#include "SyntaxHighlighter.h"
#include "TokenList.h"

#include <pthread.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

static int g_failures = 0;

#define CHECK_TRUE(cond, msg)                                              \
    do {                                                                   \
        if (!(cond)) {                                                     \
            std::fprintf(stderr, "FAIL: %s (%s:%d)\n", (msg), __FILE__,    \
                         __LINE__);                                        \
            ++g_failures;                                                  \
        } else {                                                           \
            std::fprintf(stderr, "ok: %s\n", (msg));                       \
        }                                                                  \
    } while (0)

// Flatten a highlighted TokenList back to its plain text, mirroring the paint
// walk in Syntaxer.mm: Text nodes contribute their value, Syntax nodes recurse
// into their children. Highlighting must be lossless.
static void appendNode(const TokenListNode& node, std::string& out) {
    if (node.isSyntax()) {
        const auto& syntax = dynamic_cast<const Syntax&>(node);
        for (auto it = syntax.begin(); it != syntax.end(); ++it) {
            appendNode(*it, out);
        }
    } else {
        const auto& text = dynamic_cast<const Text&>(node);
        out.append(text.value());
    }
}

static std::string flatten(const TokenList& tokens) {
    std::string out;
    for (auto it = tokens.begin(); it != tokens.end(); ++it) {
        appendNode(*it, out);
    }
    return out;
}

// Count how deeply Syntax nodes nest, and whether the deepest nesting level
// terminates in plain text (a Text child) instead of recursing further.
struct TreeStats {
    int maxSyntaxLevel = 0;         // outermost Syntax is level 1
    bool deepestEndsInText = false; // a level-maxSyntaxLevel has a Text child
    int syntaxCount = 0;
};

static void collectStats(const TokenList& list, int level, TreeStats& stats) {
    for (auto it = list.begin(); it != list.end(); ++it) {
        const TokenListNode& node = *it;
        if (!node.isSyntax()) {
            if (level > 0 && level == stats.maxSyntaxLevel) {
                stats.deepestEndsInText = true;
            }
            continue;
        }
        const auto& syntax = dynamic_cast<const Syntax&>(node);
        ++stats.syntaxCount;
        const int syntaxLevel = level + 1;
        if (syntaxLevel > stats.maxSyntaxLevel) {
            stats.maxSyntaxLevel = syntaxLevel;
            stats.deepestEndsInText = false;
        }
        collectStats(syntax.children(), syntaxLevel, stats);
    }
}

static TreeStats treeStats(const TokenList& tokens) {
    TreeStats stats;
    collectStats(tokens, 0, stats);
    return stats;
}

// True if any Syntax node of the given type exists anywhere in the tree. This
// only proves the token kind was produced; the golden baseline pins the spans.
static bool containsTypedSyntax(const TokenList& list, const char* type) {
    for (auto it = list.begin(); it != list.end(); ++it) {
        const TokenListNode& node = *it;
        if (node.isSyntax()) {
            const auto& syntax = dynamic_cast<const Syntax&>(node);
            if (syntax.type() == type) {
                return true;
            }
            if (containsTypedSyntax(syntax.children(), type)) {
                return true;
            }
        }
    }
    return false;
}

// Canonical serialization of a token tree, used to compare benign output
// before and after the fix. Values are escaped so the encoding is injective.
static void escapeValue(const std::string_view value, std::string& out) {
    for (const char c : value) {
        const auto u = static_cast<unsigned char>(c);
        switch (u) {
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        case '\\': out += "\\\\"; break;
        default:
            if (u < 0x20 || u == 0x7f) {
                char buf[8];
                std::snprintf(buf, sizeof(buf), "\\x%02x", u);
                out += buf;
            } else {
                out += static_cast<char>(u);
            }
            break;
        }
    }
}

static void serializeTree(const TokenList& list, int indent, std::string& out) {
    for (auto it = list.begin(); it != list.end(); ++it) {
        const TokenListNode& node = *it;
        out.append(static_cast<size_t>(indent) * 2, ' ');
        if (node.isSyntax()) {
            const auto& syntax = dynamic_cast<const Syntax&>(node);
            out += "S ";
            out += syntax.type();
            out += " /";
            escapeValue(syntax.alias(), out);
            out += "/ ";
            out += std::to_string(syntax.length());
            out += "\n";
            serializeTree(syntax.children(), indent + 1, out);
        } else {
            const auto& text = dynamic_cast<const Text&>(node);
            out += "T ";
            escapeValue(text.value(), out);
            out += "\n";
        }
    }
}

struct BenignCase {
    const char* label;
    const char* language;
    const char* code;
};

// Inputs that must highlight exactly the same before and after the fix:
// real code with nested (inside grammars) and greedy patterns, no cycles.
static const BenignCase kBenignCases[] = {
    {"brightscript-basic", "brightscript", "print 1"},
    {"brightscript-multiline", "brightscript", "sub main()\nprint \"x\"\nend sub"},
    {"javascript-basic", "javascript", "var x = 1; function f() { return x; }"},
    {"javascript-template-string", "javascript", "const s = `hello ${name} world`;"},
    {"javascript-greedy", "javascript", "var s = \"a+b\" + 'c'; /* comment */"},
    {"javascript-regex", "javascript", "var re = /a+b/g;"},
    {"swift-basic", "swift", "class Foo { func bar() -> Int { return 1 } }"},
    {"swift-interpolation", "swift", "let s = \"value \\(x) end\""},
};

// The DoS payloads: "brightscript" code blocks whose directive-statement ->
// expression -> directive-statement token cycle recursed without limit.
// Before the depth bound this crashes with a stack overflow, so simply
// reaching the assertions below is the core of the regression.
static const std::vector<std::string> kCyclicPayloads = {
    "#iFclude <a>",
    "#iFclude <a>2}",
    "#iFclude <a>2}ss",
    "#iFncLude x <a>\fracde <a>\frac{{1}{2}",
};

// Upper bound mirrored from SyntaxHighlighter's kMaxTokenizeDepth: matching is
// permitted at depths 0..128, so nested syntax cannot exceed 129 levels, and
// the innermost matches are kept as plain text.
static constexpr int kMaxSyntaxLevels = 129;

static std::string serializeBenign(SyntaxHighlighter& highlighter) {
    std::string out;
    for (const auto& benign : kBenignCases) {
        const std::string code = benign.code;
        TokenList tokens = highlighter.tokenize(code, benign.language);
        out += "=== ";
        out += benign.label;
        out += " ===\n";
        serializeTree(tokens, 0, out);
    }
    return out;
}

static void checkBenign(SyntaxHighlighter& highlighter) {
    for (const auto& benign : kBenignCases) {
        const std::string code = benign.code;
        TokenList tokens = highlighter.tokenize(code, benign.language);
        const std::string label = std::string("benign ") + benign.label + " stays lossless";
        CHECK_TRUE(flatten(tokens) == code, label.c_str());
    }
    // Recognizable syntax tokens in the benign output.
    {
        TokenList tokens = highlighter.tokenize(std::string("print 1"), "brightscript");
        CHECK_TRUE(containsTypedSyntax(tokens, "keyword"), "benign brightscript has keyword syntax");
        CHECK_TRUE(containsTypedSyntax(tokens, "number"), "benign brightscript has number syntax");
    }
    {
        TokenList tokens = highlighter.tokenize(std::string("const s = `hello ${name} world`;"), "javascript");
        CHECK_TRUE(containsTypedSyntax(tokens, "template-string"), "javascript template string is nested syntax");
        CHECK_TRUE(containsTypedSyntax(tokens, "interpolation"), "javascript template interpolation is nested syntax");
    }
    {
        TokenList tokens = highlighter.tokenize(std::string("var s = \"a+b\" + 'c'; /* comment */"), "javascript");
        CHECK_TRUE(containsTypedSyntax(tokens, "string"), "greedy javascript strings are syntax");
        CHECK_TRUE(containsTypedSyntax(tokens, "comment"), "greedy javascript comment is syntax");
    }
    {
        TokenList tokens = highlighter.tokenize(std::string("var re = /a+b/g;"), "javascript");
        CHECK_TRUE(containsTypedSyntax(tokens, "regex"), "javascript regex literal is nested syntax");
        CHECK_TRUE(containsTypedSyntax(tokens, "quantifier"), "javascript regex quantifier is nested syntax");
    }
    {
        TokenList tokens = highlighter.tokenize(std::string("class Foo { func bar() -> Int { return 1 } }"), "swift");
        CHECK_TRUE(containsTypedSyntax(tokens, "class-name"), "benign swift has class-name syntax");
        CHECK_TRUE(containsTypedSyntax(tokens, "keyword"), "benign swift has keyword syntax");
    }
    {
        TokenList tokens = highlighter.tokenize(std::string("let s = \"value \\(x) end\""), "swift");
        CHECK_TRUE(containsTypedSyntax(tokens, "string-literal"), "swift string literal is nested syntax");
        CHECK_TRUE(containsTypedSyntax(tokens, "interpolation"), "swift interpolation is nested syntax");
    }
}

static void checkDegenerate(SyntaxHighlighter& highlighter) {
    {
        const std::string code;
        TokenList tokens = highlighter.tokenize(code, "brightscript");
        CHECK_TRUE(flatten(tokens).empty(), "empty text stays empty");
    }
    {
        const std::string code = "plain words";
        TokenList tokens = highlighter.tokenize(code, "not-a-known-language");
        CHECK_TRUE(flatten(tokens) == code, "unknown language returns plain text");
    }
}

static void checkCyclicMainStack(SyntaxHighlighter& highlighter) {
    for (const std::string& code : kCyclicPayloads) {
        TokenList tokens = highlighter.tokenize(code, "brightscript");
        CHECK_TRUE(flatten(tokens) == code,
                   "brightscript DoS payload highlights losslessly without overflow");

        const TreeStats stats = treeStats(tokens);
        const std::string bounded = "cyclic payload nests at most " + std::to_string(kMaxSyntaxLevels) + " syntax levels";
        CHECK_TRUE(stats.maxSyntaxLevel <= kMaxSyntaxLevels, bounded.c_str());
        CHECK_TRUE(stats.deepestEndsInText, "cyclic payload terminates in plain text");
    }
    // The cycle must actually recurse deeply for the cap to be what stops it;
    // real (acyclic) grammars bottom out after a handful of levels.
    {
        const std::string code = kCyclicPayloads[0];
        TokenList tokens = highlighter.tokenize(code, "brightscript");
        CHECK_TRUE(treeStats(tokens).maxSyntaxLevel > 50,
                   "cyclic payload recurses deeply before the cap");
    }
    // Controls: benign input must not come anywhere near the cap.
    {
        const std::string code = "print 1";
        TokenList tokens = highlighter.tokenize(code, "brightscript");
        CHECK_TRUE(treeStats(tokens).maxSyntaxLevel < 10, "benign brightscript nests shallowly");
    }
}

struct SmallStackContext {
    SyntaxHighlighter* highlighter;
    const std::string* code;
    bool lossless = false;
};

static void* smallStackWorker(void* arg) {
    auto* context = static_cast<SmallStackContext*>(arg);
    // Tokenization, traversal and destruction all happen on this 512 KiB
    // stack; before the depth bound this overflows and kills the process.
    TokenList tokens = context->highlighter->tokenize(*context->code, "brightscript");
    context->lossless = (flatten(tokens) == *context->code);
    return nullptr;
}

static void checkCyclicSmallStack(SyntaxHighlighter& highlighter) {
    const std::string code = kCyclicPayloads[0];

    pthread_attr_t attr;
    CHECK_TRUE(pthread_attr_init(&attr) == 0, "pthread attr init");
    CHECK_TRUE(pthread_attr_setstacksize(&attr, 512 * 1024) == 0, "pthread stack size set to 512 KiB");

    SmallStackContext context;
    context.highlighter = &highlighter;
    context.code = &code;

    pthread_t thread;
    const int created = pthread_create(&thread, &attr, smallStackWorker, &context);
    CHECK_TRUE(created == 0, "worker thread created");
    if (created == 0) {
        CHECK_TRUE(pthread_join(thread, nullptr) == 0, "worker thread joined");
        CHECK_TRUE(context.lossless, "cyclic payload highlights losslessly on a 512 KiB stack");
    }
    pthread_attr_destroy(&attr);
}

static bool readFile(const std::string& path, std::string& out) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return false;
    }
    std::stringstream stream;
    stream << file.rdbuf();
    out = stream.str();
    return true;
}

static void firstDifference(const std::string& expected, const std::string& actual, char* buffer, size_t size) {
    size_t index = 0;
    while (index < expected.size() && index < actual.size() && expected[index] == actual[index]) {
        ++index;
    }
    const size_t line = static_cast<size_t>(std::count(expected.begin(), expected.begin() + std::min(index, expected.size()), '\n')) + 1;
    std::snprintf(buffer, size, "baseline mismatch near line %zu (expected %zu bytes, got %zu bytes)",
                  line, expected.size(), actual.size());
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <path-to-grammars.dat> [--record FILE | --verify FILE]\n", argv[0]);
        return 2;
    }

    const char* recordPath = nullptr;
    const char* verifyPath = nullptr;
    for (int i = 2; i + 1 < argc; i += 2) {
        if (std::strcmp(argv[i], "--record") == 0) {
            recordPath = argv[i + 1];
        } else if (std::strcmp(argv[i], "--verify") == 0) {
            verifyPath = argv[i + 1];
        } else {
            std::fprintf(stderr, "unknown option %s\n", argv[i]);
            return 2;
        }
    }
    if (argc % 2 != 0) {
        std::fprintf(stderr, "option %s needs a value\n", argv[argc - 1]);
        return 2;
    }

    std::string grammars;
    if (!readFile(argv[1], grammars)) {
        std::fprintf(stderr, "cannot open grammars.dat at %s\n", argv[1]);
        return 2;
    }
    CHECK_TRUE(grammars.size() > 100000, "grammars.dat loaded");

    SyntaxHighlighter highlighter(grammars);

    if (recordPath == nullptr && verifyPath == nullptr) {
        // Default mode: verify the tracked benign baseline next to the test
        // source when it is available (the runner compiles its path in).
#ifdef TESTS_BENIGN_GOLDEN_PATH
        std::string discard;
        if (readFile(TESTS_BENIGN_GOLDEN_PATH, discard)) {
            verifyPath = TESTS_BENIGN_GOLDEN_PATH;
        } else {
            std::fprintf(stderr, "note: benign baseline not found at %s; skipping tree comparison\n",
                         TESTS_BENIGN_GOLDEN_PATH);
        }
#endif
    }

    // Fail explicitly when the Mac blob lacks the languages under test; the
    // runner then reports a failure instead of silently testing nothing.
    {
        const std::map<std::string, std::string> languages = highlighter.languages();
        for (const char* language : {"brightscript", "javascript", "swift"}) {
            const std::string message = std::string("grammar blob provides language ") + language;
            CHECK_TRUE(languages.count(language) != 0, message.c_str());
        }
    }

    // Benign cases first: they must highlight correctly both before and after
    // the fix, so the baseline gets written even if a payload crashes later.
    checkBenign(highlighter);
    checkDegenerate(highlighter);

    if (recordPath) {
        const std::string baseline = serializeBenign(highlighter);
        std::ofstream out(recordPath, std::ios::binary);
        if (!out) {
            std::fprintf(stderr, "FAIL: cannot write baseline to %s\n", recordPath);
            ++g_failures;
        } else {
            out << baseline;
            out.close();
            std::fprintf(stderr, "ok: baseline written to %s\n", recordPath);
        }
    }
    if (verifyPath) {
        std::string expected;
        if (!readFile(verifyPath, expected)) {
            std::fprintf(stderr, "FAIL: cannot read baseline from %s\n", verifyPath);
            ++g_failures;
        } else {
            const std::string actual = serializeBenign(highlighter);
            if (actual == expected) {
                std::fprintf(stderr, "ok: benign token trees match %s\n", verifyPath);
            } else {
                char message[256];
                firstDifference(expected, actual, message, sizeof(message));
                std::fprintf(stderr, "FAIL: %s\n", message);
                ++g_failures;
            }
        }
    }

    // The crashers. Keep these last so a pre-fix SIGSEGV cannot prevent the
    // benign checks and baseline handling above from completing.
    checkCyclicMainStack(highlighter);
    checkCyclicSmallStack(highlighter);

    if (g_failures == 0) {
        std::fprintf(stderr, "ALL PASS\n");
        return 0;
    }
    std::fprintf(stderr, "%d FAILURE(S)\n", g_failures);
    return 1;
}