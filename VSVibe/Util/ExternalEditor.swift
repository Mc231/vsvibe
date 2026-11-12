import AppKit
import Foundation
import SwiftUI

internal struct ExternalEditor: Identifiable, Hashable {
    /// Resolves a bundle identifier to an installed application URL.
    internal typealias AppLookup = (String) -> URL?

    /// Production lookup: asks Launch Services via `NSWorkspace`.
    internal static let workspaceLookup: AppLookup = { bundleIdentifier in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    internal let id: String
    internal let displayName: String
    internal let bundleIdentifiers: [String]
    internal let iconSystemName: String
    internal let shortcutKey: String?
    internal let shortcutModifiers: EventModifiers

    internal static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// First installed application among `bundleIdentifiers`, in order.
    internal func resolvedAppURL(lookup: AppLookup = workspaceLookup) -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = lookup(bundleIdentifier) {
                return url
            }
        }
        return nil
    }

    internal func isInstalled(lookup: AppLookup = workspaceLookup) -> Bool {
        resolvedAppURL(lookup: lookup) != nil
    }
}
