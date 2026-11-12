import Foundation
import Observation

/// User registrations for existing shell commands. Built-in CLIs stay available
/// while custom aliases use the same hooks and transcript tracking pipeline.
@MainActor
@Observable
final class LaunchAliasStore {
    private(set) var customAliases: [LaunchAlias] = []
    private(set) var loadError: String?
    @ObservationIgnored private let fileURL: URL

    var aliases: [LaunchAlias] { LaunchCommandResolver.aliases + customAliases }

    init(fileURL: URL = AppPaths.aliasesFile) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode([LaunchAlias].self, from: Data(contentsOf: fileURL))
            var validated: [LaunchAlias] = []
            for alias in saved {
                let normalized = try Self.validate(command: alias.command,
                                                   configPath: alias.claudeConfigDir?.path ?? "")
                guard !validated.contains(where: { $0.command == normalized.command }) else {
                    throw AliasError.duplicateCommand
                }
                validated.append(normalized)
            }
            customAliases = validated
        } catch {
            loadError = "Could not load custom aliases: \(error.localizedDescription)"
        }
    }

    func alias(for command: String) -> LaunchAlias? {
        let base = LaunchCommandResolver.baseCommand(of: command)
        return aliases.first { $0.command == base }
    }

    /// Persist first so a failed write never looks like a successful edit.
    func save(command: String, configPath: String, replacing originalCommand: String? = nil) throws {
        let alias = try Self.validate(command: command, configPath: configPath)
        var updated = customAliases
        if let originalCommand {
            guard let index = updated.firstIndex(where: { $0.command == originalCommand }) else {
                throw AliasError.missingAlias
            }
            updated.remove(at: index)
            guard !updated.contains(where: { $0.command == alias.command }) else {
                throw AliasError.duplicateCommand
            }
            updated.insert(alias, at: index)
        } else {
            guard !updated.contains(where: { $0.command == alias.command }) else {
                throw AliasError.duplicateCommand
            }
            updated.append(alias)
        }
        try persist(updated)
    }

    func remove(command: String) throws {
        guard customAliases.contains(where: { $0.command == command }) else {
            throw AliasError.missingAlias
        }
        try persist(customAliases.filter { $0.command != command })
    }

    private static func validate(command: String, configPath: String) throws -> LaunchAlias {
        let name = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !name.hasPrefix("-"), name != ".", name != ".." else {
            throw AliasError.invalidCommand
        }
        guard !LaunchCommandResolver.knownAliases.contains(name) else { throw AliasError.builtInCommand }
        let path = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return LaunchAlias(command: name, claudeConfigDir: nil) }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !expanded.contains("\n"), !expanded.contains("\0") else {
            throw AliasError.invalidConfigPath
        }
        return LaunchAlias(command: name, claudeConfigDir: URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL)
    }

    private func persist(_ aliases: [LaunchAlias]) throws {
        // Preserve unreadable files for recovery instead of silently replacing them.
        guard loadError == nil else { throw AliasError.unreadableFile }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(aliases)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        customAliases = aliases
    }

    enum AliasError: LocalizedError {
        case invalidCommand, builtInCommand, duplicateCommand, invalidConfigPath, missingAlias, unreadableFile

        var errorDescription: String? {
            switch self {
            case .invalidCommand: "Use a command name containing letters, numbers, dots, hyphens or underscores, without arguments."
            case .builtInCommand: "That command is already built in."
            case .duplicateCommand: "An alias with that command already exists."
            case .invalidConfigPath: "Use an absolute config directory path or a path starting with ~/."
            case .missingAlias: "The custom alias no longer exists."
            case .unreadableFile: "Repair aliases.json and reopen the app before editing aliases."
            }
        }
    }
}
