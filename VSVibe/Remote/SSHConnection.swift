/// The host a remote project's background ssh calls go to: its destination and
/// port. Remote panes of the same connection share one event stream and one
/// multiplexed ssh connection (see `RemoteSSH`).
internal struct SSHConnection: Hashable, Sendable {
    internal let destination: String
    internal let port: Int?

    /// The connection of `target`; nil when `SSHCommand` rejects the target,
    /// so nothing invalid ever reaches an ssh argument list.
    internal init?(target: RemoteTarget) {
        guard SSHCommand.validationError(of: target) == nil else {
            return nil
        }
        self.destination = target.destination
        self.port = target.port
    }
}
