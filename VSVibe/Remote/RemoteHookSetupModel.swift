import Observation

/// State of the project editor's "Claude hooks on <host>" section: checks or
/// installs the hooks for the target being edited. A result that arrives
/// after the target changed is dropped.
@MainActor
@Observable
internal final class RemoteHookSetupModel {
    internal enum Phase: Equatable {
        case checking
        case finished(RemoteHookReport)
        case idle
        case installing
    }

    internal private(set) var phase = Phase.idle
    @ObservationIgnored private let installer: RemoteHookInstaller
    @ObservationIgnored private var target: RemoteTarget?

    /// A check or install is running.
    internal var isBusy: Bool {
        phase == .checking || phase == .installing
    }

    /// One line for the section (empty before the first check).
    internal var statusText: String {
        switch phase {
        case .checking:
            "Checking the hooks on the host…"

        case .finished(let report):
            report.statusText

        case .idle:
            ""

        case .installing:
            "Installing the hooks on the host…"
        }
    }

    /// Whether the last result is good (shown with a checkmark).
    internal var isInstalled: Bool {
        report?.state == .installed
    }

    private var report: RemoteHookReport? {
        if case .finished(let report) = phase {
            return report
        }
        return nil
    }

    internal init(installer: RemoteHookInstaller) {
        self.installer = installer
    }

    /// Title of the install button for `host`.
    internal func actionTitle(host: String) -> String {
        switch report?.state {
        case .installed:
            "Reinstall Hooks on \(host)"

        case .outdated:
            "Update Hooks on \(host)"

        default:
            "Install Hooks on \(host)"
        }
    }

    /// Reads the hook state on `target`'s host.
    internal func check(_ target: RemoteTarget) async {
        begin(.checking, for: target)
        let report = await installer.status(of: target)
        finish(report, for: target)
    }

    /// Installs or updates the hooks on `target`'s host.
    internal func install(_ target: RemoteTarget) async {
        begin(.installing, for: target)
        let report = await installer.install(on: target)
        finish(report, for: target)
    }

    /// Forgets the result (the target was edited).
    internal func reset() {
        target = nil
        phase = .idle
    }

    private func begin(_ phase: Phase, for target: RemoteTarget) {
        self.target = target
        self.phase = phase
    }

    private func finish(_ report: RemoteHookReport, for target: RemoteTarget) {
        guard self.target == target else {
            return
        }
        phase = .finished(report)
    }

    deinit {
        // Nothing to release.
    }
}
