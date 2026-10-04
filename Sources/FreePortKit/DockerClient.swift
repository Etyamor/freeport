import Foundation

/// Talks to Docker/OrbStack over its Unix socket.
/// Container metadata is what turns "OrbStack is on :5432" into "viburnum-postgres-1 is on :5432".
public struct DockerClient {
    /// Checked in order; the first one that exists wins.
    public static let candidateSockets: [String] = [
        "\(NSHomeDirectory())/.orbstack/run/docker.sock",
        "/var/run/docker.sock",
        "\(NSHomeDirectory())/.docker/run/docker.sock",
        "\(NSHomeDirectory())/.colima/default/docker.sock",
        "\(NSHomeDirectory())/.rd/docker.sock",
    ]

    public let socketPath: String

    public init(socketPath: String) { self.socketPath = socketPath }

    public static func detect() -> DockerClient? {
        let fm = FileManager.default
        for path in candidateSockets where fm.fileExists(atPath: path) {
            return DockerClient(socketPath: path)
        }
        if let env = ProcessInfo.processInfo.environment["DOCKER_HOST"],
           env.hasPrefix("unix://") {
            return DockerClient(socketPath: String(env.dropFirst("unix://".count)))
        }
        return nil
    }

    // MARK: - Reading

    private struct RawContainer: Decodable {
        let Id: String
        let Names: [String]?
        let Image: String?
        let Status: String?
        let Labels: [String: String]?
        let Ports: [RawPort]?
    }

    private struct RawPort: Decodable {
        let IP: String?
        let PrivatePort: Int?
        let PublicPort: Int?
    }

    public func containers() throws -> [ContainerInfo] {
        let response = try UnixHTTP.send(socketPath: socketPath, method: "GET", path: "/v1.41/containers/json")
        guard response.status == 200 else {
            throw UnixHTTP.Failure.socket("Docker API returned HTTP \(response.status).")
        }
        return try Self.decodeContainers(response.body)
    }

    /// Maps Docker's `/containers/json` payload onto `ContainerInfo`.
    static func decodeContainers(_ data: Data) throws -> [ContainerInfo] {
        let raw = try JSONDecoder().decode([RawContainer].self, from: data)
        return raw.map { c in
            var portMap: [Int: Int] = [:]
            for p in c.Ports ?? [] {
                if let pub = p.PublicPort, let priv = p.PrivatePort { portMap[pub] = priv }
            }
            let labels = c.Labels ?? [:]
            return ContainerInfo(
                id: c.Id,
                name: (c.Names?.first?.hasPrefix("/") == true
                       ? String(c.Names!.first!.dropFirst())
                       : c.Names?.first) ?? String(c.Id.prefix(12)),
                image: c.Image ?? "unknown",
                status: c.Status ?? "",
                // Shared ddev services (router, ssh-agent) carry the label but leave it empty.
                ddevProject: labels["com.ddev.site-name"].flatMap { $0.isEmpty ? nil : $0 },
                composeProject: labels["com.docker.compose.project"],
                portMap: portMap
            )
        }
    }

    // MARK: - Writing

    public func stop(containerID: String, timeoutSeconds: Int = 8) throws {
        let response = try UnixHTTP.send(
            socketPath: socketPath,
            method: "POST",
            path: "/v1.41/containers/\(containerID)/stop?t=\(timeoutSeconds)",
            timeout: TimeInterval(timeoutSeconds + 5)
        )
        // 204 = stopped, 304 = already stopped. Both are the outcome we want.
        guard response.status == 204 || response.status == 304 else {
            let detail = String(decoding: response.body, as: UTF8.self)
            throw UnixHTTP.Failure.socket("Docker refused to stop the container (HTTP \(response.status)). \(detail)")
        }
    }
}
