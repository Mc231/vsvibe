import Foundation

/// The temporary stdin / stdout / stderr files of one `SSHCommandRunner`
/// call, private to the user (0600) and removed afterwards.
internal struct ProcessFiles {
    /// Open handles for the process's standard streams.
    internal struct Streams {
        internal let input: FileHandle
        internal let output: FileHandle
        internal let error: FileHandle

        internal func close() {
            for handle in [input, output, error] where handle !== FileHandle.nullDevice {
                try? handle.close()
            }
        }
    }

    private static let permissions: Int16 = 0o600

    private let inputURL: URL
    private let outputURL: URL
    private let errorURL: URL

    internal init(directory: URL = FileManager.default.temporaryDirectory) {
        let base = "vsvibe-ssh-\(UUID().uuidString)"
        inputURL = directory.appendingPathComponent(base + ".in")
        outputURL = directory.appendingPathComponent(base + ".out")
        errorURL = directory.appendingPathComponent(base + ".err")
    }

    /// Creates the files (stdin holds `input`; none when nil) and opens them.
    internal func open(input: Data?) -> Streams? {
        guard create(outputURL, contents: nil),
            create(errorURL, contents: nil),
            let output = try? FileHandle(forWritingTo: outputURL),
            let error = try? FileHandle(forWritingTo: errorURL)
        else {
            return nil
        }
        guard let input else {
            return Streams(input: .nullDevice, output: output, error: error)
        }
        guard create(inputURL, contents: input), let inputHandle = try? FileHandle(forReadingFrom: inputURL) else {
            try? output.close()
            try? error.close()
            return nil
        }
        return Streams(input: inputHandle, output: output, error: error)
    }

    internal func output() -> Data {
        (try? Data(contentsOf: outputURL)) ?? Data()
    }

    internal func errorOutput() -> Data {
        (try? Data(contentsOf: errorURL)) ?? Data()
    }

    internal func remove() {
        for url in [inputURL, outputURL, errorURL] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func create(_ url: URL, contents: Data?) -> Bool {
        FileManager.default.createFile(
            atPath: url.path,
            contents: contents,
            attributes: [.posixPermissions: Self.permissions]
        )
    }
}
