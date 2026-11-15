import Foundation

/// A stand-in for the user's shell. A real interactive login shell would read
/// the developer's rc files, so tests point probes at an executable script
/// instead. The default body checks it was started as `-i -l -c <script>` (exit
/// 99 otherwise) and runs the script with /bin/sh.
internal enum FakeShell {
    internal static let defaultBody = """
        [ "$1" = "-i" ] && [ "$2" = "-l" ] && [ "$3" = "-c" ] || exit 99
        exec /bin/sh -c "$4"
        """

    /// Writes an executable `fake-shell` with `body` into `directory` and
    /// returns its path.
    internal static func make(in directory: URL, body: String = defaultBody) -> String {
        let url = directory.appendingPathComponent("fake-shell")
        TestSupport.write("#!/bin/sh\n" + body + "\n", to: url)
        try? FileManager.default.setAttributes([.posixPermissions: Int(0o755)], ofItemAtPath: url.path)
        return url.path
    }
}
