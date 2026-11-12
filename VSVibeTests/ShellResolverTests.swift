@testable import VSVibe
import XCTest

internal final class ShellResolverTests: XCTestCase {
    internal func testPasswdShellWins() {
        let shell = ShellResolver.resolveShell(passwdShell: "/bin/bash", environment: ["SHELL": "/bin/fish"])
        XCTAssertEqual(shell, "/bin/bash")
    }

    internal func testEmptyPasswdShellFallsBackToEnvironment() {
        XCTAssertEqual(ShellResolver.resolveShell(passwdShell: "", environment: ["SHELL": "/bin/fish"]), "/bin/fish")
        XCTAssertEqual(ShellResolver.resolveShell(passwdShell: nil, environment: ["SHELL": "/bin/fish"]), "/bin/fish")
    }

    internal func testFallsBackToZshWhenNothingIsSet() {
        XCTAssertEqual(ShellResolver.resolveShell(passwdShell: nil, environment: [:]), "/bin/zsh")
        XCTAssertEqual(ShellResolver.resolveShell(passwdShell: nil, environment: ["SHELL": ""]), "/bin/zsh")
    }

    internal func testUserLoginShellIsAnAbsolutePath() {
        let shell = ShellResolver.userLoginShell()
        XCTAssertTrue(shell.hasPrefix("/"), shell)
        XCTAssertFalse(shell.isEmpty)
    }

    internal func testLoginArgsRequestLoginShell() {
        XCTAssertEqual(ShellResolver.loginArgs(for: "/bin/zsh"), ["-l"])
    }

    deinit {
        // Stateless tests.
    }
}
