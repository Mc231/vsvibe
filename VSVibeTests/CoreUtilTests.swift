import XCTest
@testable import VSVibe

final class TranscriptLocatorTests: XCTestCase {
    func testEncodedProjectNameReplacesSlashesAndDots() {
        let url = URL(fileURLWithPath: "/Users/x/pet/my.proj")
        XCTAssertEqual(TranscriptLocator.encodedProjectName(for: url), "-Users-x-pet-my-proj")
    }

    func testProjectDir() {
        let config = URL(fileURLWithPath: "/Users/x/.claude")
        let folder = URL(fileURLWithPath: "/Users/x/demo")
        let dir = TranscriptLocator.projectDir(claudeConfigDir: config, folderURL: folder)
        XCTAssertEqual(dir.path, "/Users/x/.claude/projects/-Users-x-demo")
    }
}

final class LaunchCommandResolverTests: XCTestCase {
    func testDefaultCommandForXimAncestor() {
        let url = URL(fileURLWithPath: "/Users/x/work/impressit/xim/lifelight")
        XCTAssertEqual(LaunchCommandResolver.defaultCommand(for: url), "claudexim")
    }

    func testDefaultCommandForOrdinaryFolder() {
        let url = URL(fileURLWithPath: "/Users/x/pet/demo")
        XCTAssertEqual(LaunchCommandResolver.defaultCommand(for: url), "claude")
    }

    func testAliasLookup() {
        XCTAssertNotNil(LaunchCommandResolver.alias(for: "claude")?.claudeConfigDir)
        XCTAssertNotNil(LaunchCommandResolver.alias(for: "claudexim")?.claudeConfigDir)
        XCTAssertNil(LaunchCommandResolver.alias(for: "opencode")?.claudeConfigDir)
        XCTAssertFalse(LaunchCommandResolver.alias(for: "opencode")!.supportsClaudeHooks)
        XCTAssertNil(LaunchCommandResolver.alias(for: "not-a-real-alias"))
    }

    func testHookCapableAliasesExcludeOpencode() {
        let capable = LaunchCommandResolver.hookCapableAliases
        XCTAssertFalse(capable.contains { $0.command == "opencode" })
        XCTAssertTrue(capable.allSatisfy { $0.claudeConfigDir != nil })
        XCTAssertTrue(capable.count >= 2)
    }

    func testKnownAliases() {
        XCTAssertTrue(LaunchCommandResolver.knownAliases.contains("claude"))
        XCTAssertTrue(LaunchCommandResolver.knownAliases.contains("claudexim"))
        XCTAssertTrue(LaunchCommandResolver.knownAliases.contains("claudeimpressit"))
        XCTAssertTrue(LaunchCommandResolver.knownAliases.contains("opencode"))
    }

    func testClaudeImpressitAliasUsesOwnConfigDir() {
        let alias = LaunchCommandResolver.alias(for: "claudeimpressit")
        XCTAssertTrue(alias?.supportsClaudeHooks ?? false)
        XCTAssertEqual(alias?.claudeConfigDir?.lastPathComponent, ".claude-impressit-2")
        // Distinct from claudexim's config dir.
        XCTAssertNotEqual(alias?.claudeConfigDir,
                          LaunchCommandResolver.alias(for: "claudexim")?.claudeConfigDir)
    }

    func testBaseCommandStripsArguments() {
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: "claude --continue"), "claude")
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: "claude"), "claude")
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: "  claudexim --resume foo "), "claudexim")
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: ""), "")
    }

    func testBaseCommandResolvesAliasForCommandWithFlags() {
        let alias = LaunchCommandResolver.alias(for: LaunchCommandResolver.baseCommand(of: "claude --continue"))
        XCTAssertNotNil(alias?.claudeConfigDir)
        XCTAssertEqual(alias?.command, "claude")
    }

    func testContinueCommandAppendsFlag() {
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claude"), "claude --continue")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claudexim"), "claudexim --continue")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "  claude  "), "claude --continue")
    }

    func testContinueCommandIsIdempotent() {
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claude --continue"), "claude --continue")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claude -c"), "claude -c")
    }

    func testContinueCommandLeavesEmptyUnchanged() {
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: ""), "")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "   "), "")
    }
}

final class EnvBuilderTests: XCTestCase {
    private func dict(_ pairs: [String]) -> [String: String] {
        var d: [String: String] = [:]
        for pair in pairs {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            d[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        return d
    }

    func testSetsTerminalEnv() {
        let env = dict(EnvBuilder.build())
        XCTAssertEqual(env["TERM"], "xterm-256color")
        XCTAssertEqual(env["COLORTERM"], "truecolor")
        XCTAssertEqual(env["VSVIBE"], "1")
    }

    func testPathContainsPrependedDirs() {
        let env = dict(EnvBuilder.build())
        let path = env["PATH"] ?? ""
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/local/bin"))
    }

    func testPathHasNoDuplicates() {
        let env = dict(EnvBuilder.build())
        let parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertEqual(parts.count, Set(parts).count)
    }

    func testExtraPathsIncluded() {
        let env = dict(EnvBuilder.build(extraPaths: ["/custom/tool/bin"]))
        XCTAssertTrue((env["PATH"] ?? "").contains("/custom/tool/bin"))
    }
}

final class FormatTests: XCTestCase {
    func testCost() {
        XCTAssertEqual(Format.cost(0), "$0.00")
        XCTAssertEqual(Format.cost(12.5), "$12.50")
        XCTAssertEqual(Format.cost(150), "$150")
    }

    func testTokens() {
        XCTAssertEqual(Format.tokens(950), "950")
        XCTAssertEqual(Format.tokens(1200), "1k")
        XCTAssertEqual(Format.tokens(1_500_000), "1.5M")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(0), "0s")
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(90), "1m")
        XCTAssertEqual(Format.duration(3661), "1h 1m")
    }

    func testModelPrettify() {
        XCTAssertEqual(Format.model("claude-opus-4-7"), "Opus 4.7")
        XCTAssertEqual(Format.model("claude-sonnet-4-6"), "Sonnet 4.6")
        XCTAssertEqual(Format.model("opus"), "Opus")
    }
}
