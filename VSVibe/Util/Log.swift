import os

internal enum Log {
    internal static let subsystem = "com.shyrochuk.vsvibe"
    internal static let app = Logger(subsystem: subsystem, category: "app")
    internal static let store = Logger(subsystem: subsystem, category: "store")
    internal static let session = Logger(subsystem: subsystem, category: "session")
}
