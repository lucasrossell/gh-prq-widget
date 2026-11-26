import AppKit
import PRQueueCore
import ServiceManagement
import SwiftUI

@MainActor
final class QueueModel: ObservableObject {
    private enum Keys {
        static let command = "command"
        static let refreshMinutes = "refreshMinutes"
        static let showWaiting = "showWaiting"
        static let openOnClick = "openOnClick"
    }

    static let commandTimeout: TimeInterval = 120

    // MARK: Settings (persisted)

    @Published var command: String {
        didSet {
            guard command != oldValue else { return }
            defaults.set(command, forKey: Keys.command)
            legacyJSON = false
            refresh()
        }
    }
    @Published var refreshMinutes: Int {
        didSet {
            guard refreshMinutes != oldValue else { return }
            defaults.set(refreshMinutes, forKey: Keys.refreshMinutes)
            scheduleRefreshTimer()
        }
    }
    @Published var showWaiting: Bool {
        didSet {
            defaults.set(showWaiting, forKey: Keys.showWaiting)
            summary = QueueSummary.make(from: items, showWaiting: showWaiting)
        }
    }
    @Published var openOnClick: Bool {
        didSet { defaults.set(openOnClick, forKey: Keys.openOnClick) }
    }

    // MARK: State

    @Published private(set) var summary = QueueSummary.empty
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var staleReason: String?
    @Published private(set) var errorText: String?
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published private(set) var now = Date()
    @Published private(set) var launchAtLoginError: String?

    private var items: [PullRequest] = []
    /// Set once a gh-prq without --envelope rejects the flag; reset when the command changes.
    private var legacyJSON = false
    private let defaults: UserDefaults
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.command: QueueCommand.defaultCommand,
            Keys.refreshMinutes: 5,
            Keys.showWaiting: false,
            Keys.openOnClick: true,
        ])
        command = defaults.string(forKey: Keys.command) ?? QueueCommand.defaultCommand
        refreshMinutes = max(1, defaults.integer(forKey: Keys.refreshMinutes))
        showWaiting = defaults.bool(forKey: Keys.showWaiting)
        openOnClick = defaults.bool(forKey: Keys.openOnClick)

        scheduleRefreshTimer()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        // After sleep the queue is stale; give Wi-Fi a moment to come back first.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                self?.refresh()
            }
        }
        refresh()
    }

    var actionableCount: Int { summary.actionableCount }

    func refresh() {
        let current = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !current.isEmpty else { return }
        busy = true
        let legacy = legacyJSON
        let effective = legacy ? QueueCommand.withoutEnvelope(current) : current

        Task {
            let result = await CommandRunner.run(effective, timeout: Self.commandTimeout)
            busy = false
            // The command was edited while this one ran; its output no longer applies.
            guard current == command.trimmingCharacters(in: .whitespacesAndNewlines) else {
                refresh()
                return
            }
            switch RefreshInterpreter.interpret(result, usingLegacyJSON: legacy) {
            case .retryWithoutEnvelope:
                legacyJSON = true
                refresh()
            case .failed(let message):
                errorText = message
            case .loaded(let snapshot):
                items = snapshot.items
                fetchedAt = snapshot.fetchedAt
                staleReason = snapshot.staleReason
                errorText = nil
                loaded = true
                now = Date()
                summary = QueueSummary.make(from: items, showWaiting: showWaiting)
            }
        }
    }

    func open(_ pr: PullRequest) {
        guard openOnClick, let url = pr.webURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Open at login

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        objectWillChange.send()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(1, refreshMinutes) * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer?.tolerance = 10
    }
}
