import SwiftUI
import ServiceManagement
import AppKit
import FreePortKit

struct ContentView: View {
    @EnvironmentObject private var store: PortStore
    @State private var pendingConfirmation: PortEntry?
    @State private var contentHeight: CGFloat = 0
    @State private var spin: Double = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .onAppear {
            store.startPolling()
            searchFocused = true
        }
        .onDisappear { store.stopPolling() }
        .alert(item: $pendingConfirmation) { entry in
            let action = store.action(for: entry)
            return Alert(
                title: Text(action.confirmationTitle),
                message: Text("Other projects may depend on it."),
                primaryButton: .destructive(Text("Stop")) { store.release(entry) },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "powerplug.fill")
                .foregroundStyle(.tint)
            Text("Ports")
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: String(store.visibleEntries.count))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .foregroundStyle(.secondary)

            Spacer()

            // Spin only on an explicit click, and animate the rotation alone:
            // a view-level .animation(value:) also animates the button's
            // position, which drifts every time the popover resizes.
            Button {
                withAnimation(.linear(duration: 0.5)) { spin += 360 }
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(spin))
            }
            .buttonStyle(.plain)
            .help("Refresh now")

            SettingsMenu()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search, or type a port and press ⏎ to free it", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit {
                    if let port = Int(store.searchText.trimmingCharacters(in: .whitespaces)) {
                        store.releasePort(port)
                        store.searchText = ""
                    }
                }
            if !store.searchText.isEmpty {
                Button { store.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if store.visibleEntries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: store.entries.isEmpty ? "moon.zzz" : "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text(store.entries.isEmpty ? "No listening ports" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ScrollView {
                // VStack, not LazyVStack: lazy containers don't reliably report a
                // full content height, and 30-odd rows cost nothing to lay out.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.groupedEntries, id: \.group) { section in
                        Section {
                            if !store.collapsedGroups.contains(section.group) {
                                ForEach(section.entries) { entry in
                                    PortRow(entry: entry) { requestRelease(entry) }
                                }
                            }
                        } header: {
                            GroupHeader(group: section.group,
                                        count: section.entries.count,
                                        collapsed: store.collapsedGroups.contains(section.group)) {
                                store.toggle(section.group)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(height: min(max(contentHeight, 44), Self.maxListHeight))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
    }

    /// Everything the list doesn't get: header, search field, footer, dividers.
    private static let chromeHeight: CGFloat = 105

    static var maxListHeight: CGFloat { maxPopoverHeight - chromeHeight }

    private func requestRelease(_ entry: PortEntry) {
        let action = store.action(for: entry)
        if store.needsConfirmation(action) { pendingConfirmation = entry }
        else { store.release(entry) }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if let status = store.status {
                Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(status.isError ? .orange : .green)
                Text(status.text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let error = store.dockerError {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Updated \(store.lastScan.map(Self.timeFormatter.string(from:)) ?? "—")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 26)
    }

    /// Twice the original 540pt cap, clamped to what the screen can actually
    /// show beneath the menu bar so the popover never gets clipped.
    static var maxPopoverHeight: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 900) - 16
        return min(1080, max(540, available))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - Rows

private struct GroupHeader: View {
    let group: PortGroup
    let count: Int
    let collapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(.tertiary)
                Image(systemName: group.symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(group.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(verbatim: String(count))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(.regularMaterial)
        }
        .buttonStyle(.plain)
    }
}

private struct PortRow: View {
    let entry: PortEntry
    let release: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: String(entry.port))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if entry.address == "*" {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Bound to all interfaces — reachable from your network")
            }

            Button(action: release) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(hovering ? Color.red : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .help(releaseHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(localhostLabel) { copy("localhost:\(entry.port)") }
            Button("Open in browser") {
                if let url = URL(string: "http://localhost:\(entry.port)") { NSWorkspace.shared.open(url) }
            }
            if entry.pid > 0 {
                Button(pidLabel) { copy(String(entry.pid)) }
            }
            if let cwd = entry.cwd {
                Button("Reveal \(PortEntry.abbreviate(cwd))") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                }
            }
        }
    }

    // Plain Strings, so SwiftUI uses the verbatim initializer rather than
    // treating these as localization keys and formatting the numbers.
    private var localhostLabel: String { "Copy localhost:" + String(entry.port) }
    private var pidLabel: String { "Copy PID " + String(entry.pid) }

    private var releaseHelp: String {
        if let c = entry.container {
            return c.ddevProject.map { "Stop ddev project \($0)" } ?? "Stop container \(c.name)"
        }
        return "Quit \(entry.command) and free :\(entry.port)"
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Settings

private struct SettingsMenu: View {
    @EnvironmentObject private var store: PortStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Menu {
            Picker("Refresh every", selection: $store.refreshInterval) {
                Text("1 second").tag(1.0)
                Text("3 seconds").tag(3.0)
                Text("10 seconds").tag(10.0)
            }

            Toggle("Show count in menu bar", isOn: $store.showCountInMenuBar)
            Toggle("Hide other users' ports", isOn: $store.hideSystemPorts)

            Divider()
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in setLaunchAtLogin(enabled) }
            if let loginError {
                Text(loginError).font(.caption)
            }

            Divider()
            Button("Quit FreePort") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Needs a signed copy in /Applications."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}


/// Carries the laid-out height of the list up to the enclosing frame.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
