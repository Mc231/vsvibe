/// Why `RemoteHookInstaller` could not use a remote file it read.
internal enum RemoteHookInstallerError: Error, Equatable {
    /// Reading the file over ssh failed (the message says why).
    case readFailed(String)
}
