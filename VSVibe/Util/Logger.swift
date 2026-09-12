import Foundation
import os

enum Log {
    static let subsystem = "com.shyrochuk.vsvibe"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let terminal = Logger(subsystem: subsystem, category: "terminal")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
