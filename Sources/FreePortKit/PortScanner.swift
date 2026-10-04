import Foundation

/// Builds the list of listening TCP ports by combining three sources:
///   1. lsof  — who is actually bound to the socket
///   2. ps    — the full command line, so "node" becomes "node vite dev"
///   3. Docker— so a port held by the OrbStack proxy names its real container
///
/// Every parsing step is a pure function over command output, so the awkward
/// parts can be tested without a particular machine's processes.
public enum PortScanner {

    public struct Snapshot: Sendable {
        public var entries: [PortEntry]
        public var containers: [ContainerInfo]
        public var dockerError: String?

        public init(entries: [PortEntry], containers: [ContainerInfo], dockerError: String? = nil) {
            self.entries = entries
            self.containers = containers
            self.dockerError = dockerError
        }
    }

    // MARK: - Collecting

    public static func scan() -> Snapshot {
        guard let lsof = Shell.which("lsof") else {
            return Snapshot(entries: [], containers: [], dockerError: "lsof is not available.")
        }

        var entries = parseListening(
            Shell.run(lsof, ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcLnt"]),
            excluding: ProcessInfo.processInfo.processIdentifier
        )

        let pids = Set(entries.map(\.pid)).filter { $0 > 0 }
        if !pids.isEmpty {
            let list = pids.map(String.init).joined(separator: ",")
            let cwds = parseWorkingDirectories(Shell.run(lsof, ["-a", "-d", "cwd", "-F", "pn", "-p", list]))
            let commands = Shell.which("ps").map { parseCommandLines(Shell.run($0, ["-ww", "-o", "pid=,command=", "-p", list])) } ?? [:]
            for i in entries.indices {
                entries[i].cwd = cwds[entries[i].pid]
                entries[i].fullCommand = commands[entries[i].pid]
            }
        }

        var containers: [ContainerInfo] = []
        var dockerError: String?
        if let docker = DockerClient.detect() {
            do { containers = try docker.containers() }
            catch { dockerError = error.localizedDescription }
        }

        return Snapshot(entries: merge(entries: entries, containers: containers),
                        containers: containers,
                        dockerError: dockerError)
    }

    // MARK: - Parsing

    /// `-F` field mode is used instead of the column output because paths and
    /// command names can contain spaces, which makes column parsing unreliable.
    static func parseListening(_ output: String, excluding selfPID: Int32) -> [PortEntry] {
        var result: [PortEntry] = []
        var pid: Int32 = 0
        var command = ""
        var user = ""
        var family = ""

        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value) ?? 0
                // Field order is per-process, so a new process resets the rest.
                command = ""
                user = ""
            case "c": command = value
            case "L": user = value.hasPrefix("^") ? String(value.dropFirst()) : value
            case "t": family = value
            case "n":
                guard pid != selfPID, let parsed = parseAddress(value) else { continue }
                result.append(PortEntry(port: parsed.port,
                                        address: parsed.address,
                                        isIPv6: family == "IPv6",
                                        pid: pid,
                                        command: command,
                                        user: user))
            default: break
            }
        }
        return result
    }

    /// Handles `*:8080`, `127.0.0.1:3000`, `[::1]:32222`, `[fe80::1%lo0]:123`.
    static func parseAddress(_ raw: String) -> (address: String, port: Int)? {
        guard let colon = raw.lastIndex(of: ":") else { return nil }
        let portPart = raw[raw.index(after: colon)...]
        guard let port = Int(portPart), (1...65535).contains(port) else { return nil }
        var address = String(raw[raw.startIndex..<colon])
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        return (address.isEmpty ? "*" : address, port)
    }

    /// `lsof -d cwd -F pn` output: a `p<pid>` line followed by an `n<path>` line.
    static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
        var map: [Int32: String] = [:]
        var current: Int32 = 0
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            if tag == "p" { current = Int32(value) ?? 0 }
            else if tag == "n", current != 0 { map[current] = value }
        }
        return map
    }

    /// `ps -o pid=,command=` output: leading-padded pid, space, then argv.
    static func parseCommandLines(_ output: String) -> [Int32: String] {
        var map: [Int32: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[trimmed.startIndex..<space]) else { continue }
            map[pid] = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    /// Attaches containers to the ports they publish, and adds any published
    /// port that lsof didn't attribute to a visible process.
    static func merge(entries: [PortEntry], containers: [ContainerInfo]) -> [PortEntry] {
        var byPublicPort: [Int: ContainerInfo] = [:]
        for c in containers {
            for pub in c.portMap.keys { byPublicPort[pub] = c }
        }

        var result = entries
        for i in result.indices {
            if let c = byPublicPort[result[i].port] { result[i].container = c }
        }

        let seen = Set(result.map(\.port))
        for c in containers {
            for pub in c.portMap.keys.sorted() where !seen.contains(pub) {
                result.append(PortEntry(port: pub, address: "127.0.0.1", isIPv6: false,
                                        pid: 0, command: "docker", user: NSUserName(),
                                        container: c))
            }
        }

        return dedupe(result).sorted { $0.port < $1.port }
    }

    /// One process listening on both IPv4 and IPv6 for the same port is one
    /// thing to the user, not two rows.
    static func dedupe(_ entries: [PortEntry]) -> [PortEntry] {
        var seen = Set<String>()
        var result: [PortEntry] = []
        for entry in entries where seen.insert("\(entry.port)|\(entry.pid)").inserted {
            result.append(entry)
        }
        return result
    }

    // MARK: - Releasing

    public enum ReleaseError: LocalizedError, Equatable {
        case notPermitted(String)
        case signalFailed(String)
        case stillListening(Int)
        case noDocker

        public var errorDescription: String? {
            switch self {
            case .notPermitted(let r): return r
            case .signalFailed(let r): return r
            case .stillListening(let p): return "Port \(p) is still in use — the process ignored both signals."
            case .noDocker: return "Docker isn't reachable, so the container can't be stopped."
            }
        }
    }

    /// Returns a short description of what happened, for the status line.
    @discardableResult
    public static func release(_ action: ReleaseAction, port: Int) throws -> String {
        switch action {
        case .notPermitted(let reason):
            throw ReleaseError.notPermitted(reason)

        case .killProcess(let pid, let name):
            if kill(pid, SIGTERM) != 0 && errno != ESRCH {
                throw ReleaseError.signalFailed("Couldn't signal \(name) (errno \(errno)).")
            }
            // Give it a moment to shut down cleanly before escalating.
            for _ in 0..<12 {
                usleep(125_000)
                if kill(pid, 0) != 0 { return "Freed :\(port) — \(name) quit." }
            }
            if kill(pid, SIGKILL) != 0 && errno != ESRCH {
                throw ReleaseError.signalFailed("Couldn't force-quit \(name) (errno \(errno)).")
            }
            usleep(300_000)
            if kill(pid, 0) == 0 { throw ReleaseError.stillListening(port) }
            return "Freed :\(port) — \(name) force-quit."

        case .stopContainer(let id, let name):
            guard let docker = DockerClient.detect() else { throw ReleaseError.noDocker }
            try docker.stop(containerID: id)
            return "Freed :\(port) — stopped \(name)."

        case .stopDdevProject(let name, let ids):
            guard let docker = DockerClient.detect() else { throw ReleaseError.noDocker }
            for id in ids { try docker.stop(containerID: id) }
            return "Stopped ddev project \(name) (\(ids.count) containers)."
        }
    }
}
