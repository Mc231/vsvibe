import Foundation

/// Splits a byte stream into lines: each `append` returns the lines completed
/// by the new bytes (without their `\n`) and keeps a trailing incomplete line
/// for the next call. Shared by the events-file watcher, the remote event
/// streams and transcript usage parsing.
internal struct LineSplitter {
    private static let newline: UInt8 = 0x0A

    private var partial = Data()

    /// The complete lines in the kept partial line plus `chunk`, in order.
    internal mutating func append(_ chunk: Data) -> [Data] {
        let buffer = partial + chunk
        var lines: [Data] = []
        var lineStart = buffer.startIndex
        while let newlineIndex = buffer[lineStart...].firstIndex(of: Self.newline) {
            lines.append(buffer.subdata(in: lineStart..<newlineIndex))
            lineStart = newlineIndex + 1
        }
        partial = Data(buffer[lineStart...])
        return lines
    }

    /// Drops the kept partial line (the stream restarted).
    internal mutating func reset() {
        partial.removeAll()
    }
}
