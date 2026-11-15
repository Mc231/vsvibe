@testable import VSVibe
import XCTest

internal final class ShellAliasParserTests: XCTestCase {
    private let home = "/Users/me"

    private func configDir(_ definition: String, command: String = "cw") -> String? {
        ShellAliasParser.claudeConfigDir(inDefinition: definition, command: command, home: home)?.path
    }

    // MARK: - ShellWords

    internal func testSplitsWordsAndRemovesQuotes() {
        XCTAssertEqual(ShellWords.split("a  'b c' \"d e\" f\\ g"), ["a", "b c", "d e", "f g"])
        XCTAssertEqual(ShellWords.split("x='a'\\''b'"), ["x=a'b"])
        XCTAssertEqual(ShellWords.split("''"), [""])
        XCTAssertEqual(ShellWords.split("   "), [])
    }

    internal func testSeparatorsEndWords() {
        XCTAssertEqual(ShellWords.split("a;b&&c|d (e) <f >g\nh"), ["a", "b", "c", "d", "e", "f", "g", "h"])
        XCTAssertEqual(ShellWords.split("a\\\nb"), ["ab"])
        XCTAssertEqual(ShellWords.split("trailing\\"), ["trailing"])
    }

    internal func testDoubleQuoteEscapes() {
        XCTAssertEqual(ShellWords.split("\"a\\\"b\\\\c\\$d\\x\""), ["a\"b\\c$d\\x"])
        XCTAssertEqual(ShellWords.split("\"a\\\nb\""), ["ab"])
    }

    internal func testHomeExpansion() {
        XCTAssertEqual(
            ShellWords.split("$HOME/a \"${HOME}/b\" '$HOME/c' ~/d ~ x~ ~other $USER ${X} $", home: home),
            ["/Users/me/a", "/Users/me/b", "$HOME/c", "/Users/me/d", "/Users/me", "x~", "~other", "$USER", "${X}", "$"]
        )
        XCTAssertEqual(ShellWords.split("~;", home: home), ["/Users/me"])
    }

    internal func testNoExpansionWithoutHome() {
        XCTAssertEqual(ShellWords.split("$HOME/a \"${HOME}\" ~/b ~"), ["$HOME/a", "${HOME}", "~/b", "~"])
    }

    // MARK: - Markers

    internal func testMarkedOutputIgnoresRcNoise() {
        let output = "Welcome!\n__VSVIBE_BEGIN__\nline1\nline2\n__VSVIBE_END__\nbye\n"
        XCTAssertEqual(ShellAliasParser.markedOutput(output), "line1\nline2")
        XCTAssertEqual(ShellAliasParser.markedOutput("__VSVIBE_BEGIN__\n__VSVIBE_END__\n"), "")
        XCTAssertNil(ShellAliasParser.markedOutput("__VSVIBE_BEGIN__\nno end\n"))
        XCTAssertNil(ShellAliasParser.markedOutput("nothing"))
    }

    // MARK: - CLAUDE_CONFIG_DIR

    internal func testZshAliasWithHomeVariable() {
        let zsh = "cw='CLAUDE_CONFIG_DIR=\"$HOME/.claude-impressit-2\" /Users/me/.local/bin/claude'"
        XCTAssertEqual(configDir(zsh), "/Users/me/.claude-impressit-2")
    }

    internal func testBashAliasLine() {
        let bash = "alias cw='CLAUDE_CONFIG_DIR=\"$HOME/.claude-work\" /opt/bin/claude'"
        XCTAssertEqual(configDir(bash), "/Users/me/.claude-work")
    }

    internal func testUnquotedTildeAndAbsoluteValues() {
        XCTAssertEqual(configDir("cw='CLAUDE_CONFIG_DIR=~/.cw claude'"), "/Users/me/.cw")
        XCTAssertEqual(configDir("cw='CLAUDE_CONFIG_DIR=/srv/claude/ claude'"), "/srv/claude")
        XCTAssertEqual(configDir("cw='env CLAUDE_CONFIG_DIR=${HOME}/x claude --model opus'"), "/Users/me/x")
        XCTAssertEqual(configDir("cw='CLAUDE_CONFIG_DIR=~ claude'"), "/Users/me")
    }

    internal func testZshQuotingOfEmbeddedSingleQuotes() {
        // Real `alias cy` output of zsh for: alias cy="CLAUDE_CONFIG_DIR='/tmp/it'\''s' claude"
        let zsh = #"cw='CLAUDE_CONFIG_DIR='\''/tmp/it'\''\'\'\''s'\'' claude'"#
        XCTAssertEqual(configDir(zsh), "/tmp/it's")
    }

    internal func testFunctionBodies() {
        let zsh = "cw () {\n\texport CLAUDE_CONFIG_DIR=~/.cf \n\tclaude \"$@\"\n}"
        XCTAssertEqual(configDir(zsh), "/Users/me/.cf")
        let bash = "cw () \n{ \n    export CLAUDE_CONFIG_DIR=\"$HOME/.cb\";\n    claude \"$@\"\n}"
        XCTAssertEqual(configDir(bash), "/Users/me/.cb")
    }

    internal func testNoUsableAssignment() {
        XCTAssertNil(configDir("cw=claude"))
        XCTAssertNil(configDir(""))
        XCTAssertNil(configDir("cw='CLAUDE_CONFIG_DIR=$XDG/claude claude'"))
        XCTAssertNil(configDir("cw='CLAUDE_CONFIG_DIR=relative/dir claude'"))
        XCTAssertNil(configDir("cw='CLAUDE_CONFIG_DIR= claude'"))
        XCTAssertNil(configDir("cw='CLAUDE_CONFIG_DIR=\"/a\tb\" claude'"))
        // The single-quoted $HOME is literal in the shell too.
        XCTAssertNil(configDir("cw='CLAUDE_CONFIG_DIR='\\''$HOME/x'\\'' claude'"))
    }

    // MARK: - Resolver

    internal func testScriptQuotesOnlyValidNames() {
        XCTAssertEqual(
            ShellAliasResolver.script(for: "cw"),
            "printf '%s\\n' '__VSVIBE_BEGIN__'; alias 'cw' 2>/dev/null || typeset -f 'cw' 2>/dev/null; "
                + "printf '%s\\n' '__VSVIBE_END__'"
        )
        XCTAssertNil(ShellAliasResolver.script(for: "cw'; rm -rf ~; '"))
        XCTAssertNil(ShellAliasResolver.script(for: "$(id)"))
    }

    internal func testResolverParsesInjectedShellOutput() {
        let resolver = ShellAliasResolver { shell, script in
            XCTAssertEqual(shell, "/bin/zsh")
            XCTAssertTrue(script.contains("alias 'cw'"))
            return "noise\n__VSVIBE_BEGIN__\ncw='CLAUDE_CONFIG_DIR=\"$HOME/.cw\" claude'\n__VSVIBE_END__\n"
        }
        XCTAssertEqual(resolver.claudeConfigDir(forCommand: "cw", shell: "/bin/zsh", home: home)?.path, "/Users/me/.cw")
    }

    internal func testResolverNeverRunsUnsafeNamesAndHandlesFailures() {
        let neverRun = ShellAliasResolver { _, _ in
            XCTFail("must not run")
            return nil
        }
        XCTAssertNil(neverRun.claudeConfigDir(forCommand: "a;b", shell: "/bin/zsh", home: home))
        let failing = ShellAliasResolver { _, _ in nil }
        XCTAssertNil(failing.claudeConfigDir(forCommand: "cw", shell: "/bin/zsh", home: home))
        let unmarked = ShellAliasResolver { _, _ in "cw='CLAUDE_CONFIG_DIR=/x claude'\n" }
        XCTAssertNil(unmarked.claudeConfigDir(forCommand: "cw", shell: "/bin/zsh", home: home))
    }

    internal func testLiveResolverRunsTheScriptInTheShell() throws {
        let directory = TestSupport.makeTempDir("alias-shell")
        defer { TestSupport.remove(directory) }
        // A shell whose rc defines the alias: sh runs the script after defining it.
        let body = FakeShell.defaultBody.replacingOccurrences(
            of: "exec /bin/sh -c \"$4\"",
            with: "exec /bin/sh -c \"alias cw='CLAUDE_CONFIG_DIR=/opt/claude-cw claude'; echo rc-noise; $4\""
        )
        let shell = FakeShell.make(in: directory, body: body)
        let found = ShellAliasResolver.live.claudeConfigDir(forCommand: "cw", shell: shell, home: home)
        XCTAssertEqual(try XCTUnwrap(found).path, "/opt/claude-cw")
        XCTAssertNil(ShellAliasResolver.live.claudeConfigDir(forCommand: "missing", shell: shell, home: home))
        XCTAssertNil(ShellAliasResolver.live.claudeConfigDir(forCommand: "cw", shell: "/bin/not-a-shell", home: home))
    }

    deinit {
        // Pure value tests.
    }
}
