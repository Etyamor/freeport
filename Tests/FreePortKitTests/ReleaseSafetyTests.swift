import Testing
import Foundation
@testable import FreePortKit

/// These rules are the difference between a handy utility and one that
/// force-quits WindowServer, so they are pinned down explicitly.
@Suite("Release safety rules")
struct ReleaseSafetyTests {

    private func process(_ command: String, pid: Int32 = 500, user: String = "maksym") -> PortEntry {
        PortEntry(port: 3000, address: "*", isIPv6: false, pid: pid, command: command, user: user)
    }

    private func container(_ name: String, ddev: String? = nil) -> ContainerInfo {
        ContainerInfo(id: "id-" + name, name: name, image: "img", status: "Up",
                      ddevProject: ddev, composeProject: nil, portMap: [8080: 80])
    }

    private func containerEntry(_ info: ContainerInfo) -> PortEntry {
        PortEntry(port: 8080, address: "127.0.0.1", isIPv6: false, pid: 0,
                  command: "docker", user: "maksym", container: info)
    }

    @Test("Our own process can be signalled")
    func killsOwnProcess() {
        let action = process("node").releaseAction(ddevSiblings: [], currentUser: "maksym")
        #expect(action == .killProcess(pid: 500, name: "node"))
    }

    @Test("Another user's process is refused rather than attempted")
    func refusesOtherUsers() {
        let action = process("nginx", user: "root").releaseAction(ddevSiblings: [], currentUser: "maksym")
        guard case .notPermitted(let reason) = action else {
            Issue.record("expected notPermitted, got \(action)")
            return
        }
        #expect(reason.contains("root"))
        #expect(reason.contains("sudo"))
    }

    @Test("System processes are refused even when we own them", arguments: [
        "launchd", "WindowServer", "ControlCenter", "loginwindow", "rapportd",
    ])
    func refusesSystemProcesses(command: String) {
        let action = process(command).releaseAction(ddevSiblings: [], currentUser: "maksym")
        guard case .notPermitted = action else {
            Issue.record("\(command) should be protected, got \(action)")
            return
        }
    }

    @Test("A port with no identifiable owner is refused")
    func refusesUnknownOwner() {
        let orphan = PortEntry(port: 1234, address: "*", isIPv6: false, pid: 0, command: "?", user: "maksym")
        guard case .notPermitted = orphan.releaseAction(ddevSiblings: [], currentUser: "maksym") else {
            Issue.record("a pid-less, container-less entry must not be killable")
            return
        }
    }

    /// Killing the proxy process would not free the port, so container-backed
    /// ports must always resolve to a container stop.
    @Test("A container-backed port stops the container, never a process")
    func stopsContainer() {
        let info = container("viburnum-redis-1")
        let action = containerEntry(info).releaseAction(ddevSiblings: [], currentUser: "maksym")
        #expect(action == .stopContainer(id: "id-viburnum-redis-1", name: "viburnum-redis-1"))
    }

    @Test("A ddev port stops the whole project, not just one container")
    func stopsWholeDdevProject() {
        let web = container("ddev-shop-web", ddev: "shop")
        let db = container("ddev-shop-db", ddev: "shop")
        let action = containerEntry(web).releaseAction(ddevSiblings: [web, db], currentUser: "maksym")
        #expect(action == .stopDdevProject(name: "shop", containerIDs: ["id-ddev-shop-web", "id-ddev-shop-db"]))
    }

    @Test("A ddev container with no siblings still stops individually")
    func ddevWithoutSiblings() {
        let web = container("ddev-shop-web", ddev: "shop")
        let action = containerEntry(web).releaseAction(ddevSiblings: [], currentUser: "maksym")
        #expect(action == .stopContainer(id: "id-ddev-shop-web", name: "ddev-shop-web"))
    }

    @Test("Refusing to act reports a reason rather than failing silently")
    func refusalThrows() {
        #expect(throws: PortScanner.ReleaseError.self) {
            try PortScanner.release(.notPermitted(reason: "nope"), port: 3000)
        }
    }

    @Test("Confirmation titles name what is about to stop")
    func confirmationTitles() {
        #expect(ReleaseAction.killProcess(pid: 1, name: "node").confirmationTitle == "Quit node?")
        #expect(ReleaseAction.stopContainer(id: "x", name: "api").confirmationTitle == "Stop container api?")
        #expect(ReleaseAction.stopDdevProject(name: "shop", containerIDs: ["a", "b"]).confirmationTitle
                == "Stop ddev project shop (2 containers)?")
    }
}
