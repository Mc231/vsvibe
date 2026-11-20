/// The VSVibe Claude hooks on a remote host, as `RemoteHookInstaller` found
/// (or left) them.
internal enum RemoteHookState: Equatable {
    /// Connected, but a remote step failed (the message says why).
    case failed(String)
    /// The current script, registered for every event VSVibe uses.
    case installed
    /// Neither the script nor any VSVibe entry in `settings.json`.
    case missing
    /// Installed by an older VSVibe, or only partly.
    case outdated
    /// ssh could not connect or log in without a prompt (the message says why).
    case unreachable(String)
}
