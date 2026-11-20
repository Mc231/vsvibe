import Foundation

internal extension HookEvent {
    /// One `events.jsonl` line (without its newline) decoded, or nil for an
    /// empty or malformed line (logged). Used for the local events file and
    /// the remote event streams alike.
    static func decoded(fromLine data: Data) -> Self? {
        guard !data.isEmpty else {
            return nil
        }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            let text = String(bytes: data, encoding: .utf8) ?? "<binary>"
            let detail = "failed to parse line: \(text) error=\(String(describing: error))"
            Log.app.error("Hook events: \(detail, privacy: .public)")
            return nil
        }
    }
}
