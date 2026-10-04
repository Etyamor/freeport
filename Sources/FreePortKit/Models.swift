import Foundation

/// Which bucket a listening port belongs to in the UI.
public enum PortGroup: String, CaseIterable, Identifiable, Sendable {
    case ddev = "DDEV"
    case docker = "Docker"
    case node = "Node"
    case php = "PHP"
    case database = "Databases"
    case other = "Other"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .ddev: return "shippingbox.fill"
        case .docker: return "cube.box.fill"
        case .node: return "hexagon.fill"
        case .php: return "chevron.left.forwardslash.chevron.right"
        case .database: return "cylinder.split.1x2.fill"
        case .other: return "app.dashed"
        }
    }

    /// Display order in the popover.
    public var rank: Int { PortGroup.allCases.firstIndex(of: self) ?? 99 }
}

/// How a port gets released when you click the X.
public enum ReleaseAction: Equatable, Sendable {
    /// Signal the owning process directly.
    case killProcess(pid: Int32, name: String)
    /// Stop a single container via the Docker API.
    case stopContainer(id: String, name: String)
    /// Stop every container belonging to one ddev project.
    case stopDdevProject(name: String, containerIDs: [String])
    /// Owned by another user or by the system — we won't touch it.
    case notPermitted(reason: String)

    public var confirmationTitle: String {
        switch self {
        case .killProcess(_, let name): return "Quit \(name)?"
        case .stopContainer(_, let name): return "Stop container \(name)?"
        case .stopDdevProject(let name, let ids): return "Stop ddev project \(name) (\(ids.count) containers)?"
        case .notPermitted: return "Can't release this port"
        }
    }
}

/// One listening TCP port, enriched with whatever we could learn about its owner.
public struct PortEntry: Identifiable, Hashable, Sendable {
    public let port: Int
    public let address: String        // "*", "127.0.0.1", "::1"
    public let isIPv6: Bool
    public let pid: Int32             // 0 when the port is known only from Docker
    public let command: String        // short process name from lsof
    public let user: String           // login name owning the process

    public var cwd: String?           // working directory of the owning process
    public var fullCommand: String?   // full argv, for distinguishing node processes
    public var container: ContainerInfo?

    public init(port: Int, address: String, isIPv6: Bool, pid: Int32, command: String, user: String,
                cwd: String? = nil, fullCommand: String? = nil, container: ContainerInfo? = nil) {
        self.port = port
        self.address = address
        self.isIPv6 = isIPv6
        self.pid = pid
        self.command = command
        self.user = user
        self.cwd = cwd
        self.fullCommand = fullCommand
        self.container = container
    }

    public var id: String { "\(port)|\(address)|\(pid)" }

    /// Primary label: the most human-meaningful name we have.
    public var title: String {
        if let c = container {
            return c.ddevProject.map { "\($0) · \(c.shortRole)" } ?? c.name
        }
        return command
    }

    /// Secondary label: where it lives.
    public var subtitle: String? {
        if let c = container {
            var parts: [String] = [c.image]
            if let priv = c.privatePortFor(public: port) { parts.append("→ :\(priv)") }
            return parts.joined(separator: " ")
        }
        if let cwd, cwd != "/" { return Self.abbreviate(cwd) }
        if let fullCommand, fullCommand.count > command.count {
            return String(fullCommand.prefix(90))
        }
        return nil
    }

    public var group: PortGroup {
        if let c = container {
            if c.ddevProject != nil || c.name.hasPrefix("ddev-") { return .ddev }
            if Self.databaseImages.contains(where: { c.image.lowercased().contains($0) }) { return .database }
            return .docker
        }
        let c = command.lowercased()
        if Self.nodeCommands.contains(c) { return .node }
        // Exact names only: "phpstorm" is an IDE, not a PHP runtime.
        if Self.phpCommands.contains(c) || c.hasPrefix("php-") { return .php }
        if Self.databaseImages.contains(where: { c.hasPrefix($0) }) { return .database }
        return .other
    }

    /// Scoped so that an accidental click can never nuke something important.
    /// - Parameters:
    ///   - ddevSiblings: every container sharing this entry's ddev project.
    ///   - currentUser: the login name we're allowed to signal.
    public func releaseAction(ddevSiblings: [ContainerInfo], currentUser: String = NSUserName()) -> ReleaseAction {
        if let c = container {
            if let project = c.ddevProject, !ddevSiblings.isEmpty {
                return .stopDdevProject(name: project, containerIDs: ddevSiblings.map(\.id))
            }
            return .stopContainer(id: c.id, name: c.name)
        }
        guard pid > 0 else {
            return .notPermitted(reason: "No owning process could be identified.")
        }
        guard user == currentUser else {
            return .notPermitted(reason: "Owned by \(user). Releasing it would need sudo.")
        }
        if Self.protectedCommands.contains(command.lowercased()) {
            return .notPermitted(reason: "\(command) is a system process.")
        }
        return .killProcess(pid: pid, name: command)
    }

    static let nodeCommands: Set<String> = [
        "node", "bun", "deno", "npm", "yarn", "pnpm", "next-server", "esbuild", "vite", "nodemon", "ts-node"
    ]
    static let phpCommands: Set<String> = ["php", "php-fpm", "php-cgi", "herd", "valet", "frankenphp"]
    static let databaseImages = ["postgres", "mysql", "mariadb", "redis", "mongo", "elastic", "clickhouse", "memcached"]
    static let protectedCommands = ["launchd", "kernel_task", "controlcenter", "rapportd", "sharingd", "loginwindow", "windowserver"]

    public static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// A Docker container as far as the UI cares.
public struct ContainerInfo: Hashable, Sendable {
    public let id: String
    public let name: String
    public let image: String
    public let status: String
    public let ddevProject: String?
    public let composeProject: String?
    /// public port -> private port
    public let portMap: [Int: Int]

    public init(id: String, name: String, image: String, status: String,
                ddevProject: String?, composeProject: String?, portMap: [Int: Int]) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.ddevProject = ddevProject
        self.composeProject = composeProject
        self.portMap = portMap
    }

    public func privatePortFor(public p: Int) -> Int? {
        guard let priv = portMap[p], priv != p else { return nil }
        return priv
    }

    /// "ddev-wp-to-sanity-web" with project "wp-to-sanity" -> "web"
    public var shortRole: String {
        guard let project = ddevProject else { return name }
        let prefix = "ddev-\(project)-"
        if name.hasPrefix(prefix) { return String(name.dropFirst(prefix.count)) }
        return name
    }
}
