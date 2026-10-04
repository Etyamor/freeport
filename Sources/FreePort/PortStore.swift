import Foundation
import SwiftUI
import FreePortKit

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var containers: [ContainerInfo] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastScan: Date?
    @Published var dockerError: String?
    @Published var status: StatusMessage?
    @Published var searchText = ""
    @Published var collapsedGroups: Set<PortGroup> = []

    // Deliberately not @AppStorage: inside an ObservableObject it never fires
    // objectWillChange, so the menu bar and the timer would ignore the change.
    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval); schedule() }
    }
    @Published var showCountInMenuBar: Bool {
        didSet { defaults.set(showCountInMenuBar, forKey: Keys.showCount) }
    }
    @Published var hideSystemPorts: Bool {
        didSet { defaults.set(hideSystemPorts, forKey: Keys.hideSystem) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let showCount = "showCountInMenuBar"
        static let hideSystem = "hideSystemPorts"
    }

    struct StatusMessage: Equatable {
        let text: String
        let isError: Bool
    }

    private var timer: Timer?
    private var isPopoverOpen = false

    /// Idle cadence while the popover is closed — just enough to keep the
    /// menu bar count honest without scanning every few seconds all day.
    private let idleInterval: TimeInterval = 20

    init() {
        let stored = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = stored > 0 ? stored : 3
        showCountInMenuBar = defaults.object(forKey: Keys.showCount) as? Bool ?? true
        hideSystemPorts = defaults.bool(forKey: Keys.hideSystem)
        schedule()
    }

    // MARK: - Lifecycle

    func startPolling() {
        isPopoverOpen = true
        refresh()
        schedule()
    }

    func stopPolling() {
        isPopoverOpen = false
        status = nil
        schedule()
    }

    func schedule() {
        timer?.invalidate()
        let interval = isPopoverOpen ? max(1, refreshInterval) : idleInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Data

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .userInitiated) {
            let snapshot = PortScanner.scan()
            await MainActor.run {
                self.entries = snapshot.entries
                self.containers = snapshot.containers
                self.dockerError = snapshot.dockerError
                self.lastScan = Date()
                self.isRefreshing = false
            }
        }
    }

    /// Ports the user actually cares about, after search and filtering.
    var visibleEntries: [PortEntry] {
        var result = entries
        if hideSystemPorts {
            result = result.filter { $0.group != .other || $0.user == NSUserName() }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return result }
        return result.filter { entry in
            String(entry.port).contains(query)
                || entry.title.lowercased().contains(query)
                || entry.command.lowercased().contains(query)
                || (entry.subtitle?.lowercased().contains(query) ?? false)
                || (entry.cwd?.lowercased().contains(query) ?? false)
        }
    }

    var groupedEntries: [(group: PortGroup, entries: [PortEntry])] {
        Dictionary(grouping: visibleEntries, by: \.group)
            .sorted { $0.key.rank < $1.key.rank }
            .map { (group: $0.key, entries: $0.value) }
    }

    var devPortCount: Int {
        entries.filter { [.ddev, .docker, .node, .php, .database].contains($0.group) }.count
    }

    // MARK: - Actions

    func action(for entry: PortEntry) -> ReleaseAction {
        entry.releaseAction(ddevSiblings: ddevSiblings(of: entry))
    }

    /// Every container in the same ddev project, so stopping a site stops web+db
    /// together instead of leaving half of it running.
    func ddevSiblings(of entry: PortEntry) -> [ContainerInfo] {
        guard let project = entry.container?.ddevProject else { return [] }
        return containers.filter { $0.ddevProject == project }
    }

    /// Shared infrastructure that other projects depend on deserves a prompt.
    func needsConfirmation(_ action: ReleaseAction) -> Bool {
        switch action {
        case .stopDdevProject: return true
        case .stopContainer(_, let name): return name.hasPrefix("ddev-router") || name.hasPrefix("ddev-ssh-agent")
        default: return false
        }
    }

    func release(_ entry: PortEntry) {
        let action = action(for: entry)
        let port = entry.port
        Task.detached(priority: .userInitiated) {
            do {
                let message = try PortScanner.release(action, port: port)
                await MainActor.run {
                    self.status = StatusMessage(text: message, isError: false)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.status = StatusMessage(text: error.localizedDescription, isError: true)
                }
            }
        }
    }

    /// "Free port 3000" from the quick field — works even if the port isn't listed yet.
    func releasePort(_ port: Int) {
        guard let entry = entries.first(where: { $0.port == port }) else {
            status = StatusMessage(text: "Nothing is listening on :\(port).", isError: false)
            return
        }
        release(entry)
    }

    func toggle(_ group: PortGroup) {
        if collapsedGroups.contains(group) { collapsedGroups.remove(group) }
        else { collapsedGroups.insert(group) }
    }
}
