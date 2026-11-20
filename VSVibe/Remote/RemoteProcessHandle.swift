/// A running stream process started by `RemoteProcessLaunching`.
@MainActor
internal protocol RemoteProcessHandle: AnyObject {
    /// Stops the process; no more output is delivered (its exit still is).
    func terminate()
}
