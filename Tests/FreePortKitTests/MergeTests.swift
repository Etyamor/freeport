import Testing
import Foundation
@testable import FreePortKit

@Suite("Merging lsof results with Docker containers")
struct MergeTests {

    private func entry(_ port: Int, pid: Int32 = 1, command: String = "OrbStack", ipv6: Bool = false) -> PortEntry {
        PortEntry(port: port, address: "127.0.0.1", isIPv6: ipv6, pid: pid, command: command, user: "maksym")
    }

    private func container(_ name: String, image: String = "nginx", ddev: String? = nil,
                           ports: [Int: Int] = [:]) -> ContainerInfo {
        ContainerInfo(id: "id-" + name, name: name, image: image, status: "Up",
                      ddevProject: ddev, composeProject: nil, portMap: ports)
    }

    /// The whole point of the Docker lookup: a port the proxy holds should name
    /// the container, not "OrbStack".
    @Test("Attaches a container to the port it publishes")
    func attachesContainer() {
        let merged = PortScanner.merge(
            entries: [entry(5433)],
            containers: [container("cooknotes-db-1", image: "postgres:17-alpine", ports: [5433: 5432])]
        )
        #expect(merged.count == 1)
        #expect(merged[0].title == "cooknotes-db-1")
        #expect(merged[0].subtitle == "postgres:17-alpine → :5432")
        #expect(merged[0].group == .database)
    }

    @Test("Adds published ports that lsof never reported")
    func addsContainerOnlyPorts() {
        let merged = PortScanner.merge(
            entries: [],
            containers: [container("api", ports: [8080: 80])]
        )
        #expect(merged.map(\.port) == [8080])
        #expect(merged[0].pid == 0)
        #expect(merged[0].container?.name == "api")
    }

    @Test("Does not duplicate a port reported by both lsof and Docker")
    func noDuplicates() {
        let merged = PortScanner.merge(
            entries: [entry(8080)],
            containers: [container("api", ports: [8080: 80])]
        )
        #expect(merged.count == 1)
    }

    @Test("Collapses the IPv4 and IPv6 rows of one process")
    func collapsesDualStack() {
        let merged = PortScanner.merge(
            entries: [entry(3000, pid: 42), entry(3000, pid: 42, ipv6: true)],
            containers: []
        )
        #expect(merged.count == 1)
    }

    @Test("Keeps two different processes that bind the same port number")
    func keepsDistinctProcesses() {
        let merged = PortScanner.merge(
            entries: [entry(3000, pid: 42), entry(3000, pid: 43)],
            containers: []
        )
        #expect(merged.count == 2)
    }

    @Test("Sorts by port number")
    func sortsByPort() {
        let merged = PortScanner.merge(
            entries: [entry(9000, pid: 1), entry(80, pid: 2), entry(3000, pid: 3)],
            containers: []
        )
        #expect(merged.map(\.port) == [80, 3000, 9000])
    }

    @Test("Hides the private port when it matches the published one")
    func hidesRedundantPrivatePort() {
        let merged = PortScanner.merge(
            entries: [],
            containers: [container("redis", image: "redis:7-alpine", ports: [6379: 6379])]
        )
        #expect(merged[0].subtitle == "redis:7-alpine")
    }
}
