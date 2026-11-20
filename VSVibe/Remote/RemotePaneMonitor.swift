/// Makes remote (SSH) panes as informative as local ones, over background ssh
/// calls (`RemoteSSH`): one hook-event stream per host with open panes
/// (`RemoteEventStreams`), each pane's git branch (`RemoteBranchTracker`) and,
/// once its hook events reported the remote transcript, its token usage
/// (`RemoteUsageTracker`). `SessionManager` reports the pane lifecycle;
/// nothing runs for a target `SSHCommand` rejects.
@MainActor
internal final class RemotePaneMonitor {
    private struct Pane {
        let connection: SSHConnection
        let branch: RemoteBranchTracker
        var usage: RemoteUsageTracker?
    }

    private let services: RemoteServices
    private let eventStreams: RemoteEventStreams
    private var panes: [TerminalSession.ID: Pane] = [:]

    /// Receives every event of the remote streams (on the main actor).
    internal var onEvent: (HookEvent) -> Void {
        get { eventStreams.onEvent }
        set { eventStreams.onEvent = newValue }
    }

    /// The hosts whose events are streamed.
    internal var streamedConnections: Set<SSHConnection> {
        eventStreams.connections
    }

    /// The panes being monitored.
    internal var monitoredPaneIDs: Set<TerminalSession.ID> {
        Set(panes.keys)
    }

    internal init(services: RemoteServices) {
        self.services = services
        self.eventStreams = RemoteEventStreams(services: services)
    }

    /// The remote transcript whose usage is streamed for pane `id`, if any.
    internal func streamedTranscriptPath(forPane id: TerminalSession.ID) -> String? {
        panes[id]?.usage?.transcriptPath
    }

    /// Starts monitoring a remote pane that has just typed its ssh line.
    internal func paneOpened(_ session: TerminalSession) {
        guard panes[session.id] == nil,
            let target = session.folder.remote,
            let connection = SSHConnection(target: target)
        else {
            return
        }
        let branch = RemoteBranchTracker(
            connection: connection,
            remotePath: target.remotePath,
            services: services
        ) { [weak session] branch in
            session?.gitBranch = branch
        }
        panes[session.id] = Pane(connection: connection, branch: branch)
        branch.start()
        conversationChanged(session)
        updateEventStreams()
    }

    /// Points the pane's usage at its current transcript: a new valid path
    /// restarts the stream and clears the shown usage (it belonged to another
    /// conversation); no valid path stops it.
    internal func conversationChanged(_ session: TerminalSession) {
        guard var pane = panes[session.id] else {
            return
        }
        let path = session.claudeTranscriptPath.flatMap { RemoteUsageTracker.isValidPath($0) ? $0 : nil }
        guard pane.usage?.transcriptPath != path else {
            return
        }
        if let current = pane.usage {
            current.stop()
            session.usage = nil
        }
        pane.usage = path.map { path in
            RemoteUsageTracker(
                connection: pane.connection,
                transcriptPath: path,
                services: services
            ) { [weak session] usage in
                session?.usage = usage
            }
        }
        panes[session.id] = pane
    }

    /// Stops the pane's trackers, and its host's event stream when it was the
    /// host's last remote pane.
    internal func paneClosed(id: TerminalSession.ID) {
        guard let pane = panes.removeValue(forKey: id) else {
            return
        }
        stop(pane)
        updateEventStreams()
    }

    /// Stops everything (all panes closed, or the app quits).
    internal func stopAll() {
        for pane in panes.values {
            stop(pane)
        }
        panes.removeAll()
        eventStreams.stopAll()
    }

    private func stop(_ pane: Pane) {
        pane.branch.stop()
        pane.usage?.stop()
    }

    private func updateEventStreams() {
        eventStreams.update(Set(panes.values.map(\.connection)))
    }

    deinit {
        // Stopped explicitly via stopAll().
    }
}
