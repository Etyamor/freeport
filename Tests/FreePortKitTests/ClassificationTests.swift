import Testing
import Foundation
@testable import FreePortKit

@Suite("Grouping and labelling")
struct ClassificationTests {

    private func process(_ command: String, cwd: String? = nil, argv: String? = nil) -> PortEntry {
        PortEntry(port: 3000, address: "*", isIPv6: false, pid: 1,
                  command: command, user: "maksym", cwd: cwd, fullCommand: argv)
    }

    private func containerEntry(name: String, image: String, ddev: String? = nil) -> PortEntry {
        PortEntry(port: 8080, address: "127.0.0.1", isIPv6: false, pid: 0, command: "docker", user: "maksym",
                  container: ContainerInfo(id: "abc", name: name, image: image, status: "Up",
                                           ddevProject: ddev, composeProject: nil, portMap: [8080: 80]))
    }

    @Test("Runtimes are grouped by exact command name", arguments: [
        ("node", PortGroup.node), ("bun", .node), ("deno", .node), ("vite", .node),
        ("php", .php), ("php-fpm", .php), ("frankenphp", .php),
        ("postgres", .database), ("redis-server", .database),
        ("rapportd", .other), ("dbeaver", .other),
    ])
    func groupsByCommand(command: String, expected: PortGroup) {
        #expect(process(command).group == expected)
    }

    /// The first version filed PhpStorm under PHP because it substring-matched
    /// "php" — an IDE is not a PHP runtime.
    @Test("An IDE whose name contains a runtime name is not that runtime")
    func phpstormIsNotPHP() {
        #expect(process("phpstorm").group == .other)
        #expect(process("PhpStorm").group == .other)
    }

    @Test("ddev containers group by their project label")
    func ddevGrouping() {
        let entry = containerEntry(name: "ddev-wp-to-sanity-web",
                                   image: "ddev/ddev-webserver:v1.25.2",
                                   ddev: "wp-to-sanity")
        #expect(entry.group == .ddev)
        #expect(entry.title == "wp-to-sanity · web")
    }

    /// The router and ssh-agent carry an *empty* site-name label, so they fall
    /// back to a name check rather than landing in the generic Docker bucket.
    @Test("Shared ddev services group as ddev by name")
    func ddevRouterGrouping() {
        let entry = containerEntry(name: "ddev-router", image: "ddev/ddev-traefik-router:v1.25.2")
        #expect(entry.group == .ddev)
        #expect(entry.title == "ddev-router")
    }

    @Test("A database image outranks the plain Docker bucket")
    func databaseImageGrouping() {
        #expect(containerEntry(name: "pg", image: "postgres:16-alpine").group == .database)
        #expect(containerEntry(name: "web", image: "nginx:alpine").group == .docker)
    }

    @Test("Local servers show their project directory, relative to home")
    func showsWorkingDirectory() {
        let entry = process("node", cwd: NSHomeDirectory() + "/Work/shop")
        #expect(entry.subtitle == "~/Work/shop")
    }

    @Test("Falls back to argv when there is no useful working directory")
    func fallsBackToArgv() {
        #expect(process("node", cwd: "/", argv: "node /opt/raycast/backend.js").subtitle == "node /opt/raycast/backend.js")
        #expect(process("node").subtitle == nil)
    }

    @Test("Home directory is abbreviated to a tilde")
    func abbreviatesHome() {
        #expect(PortEntry.abbreviate("/Users/maksym/Work/shop", home: "/Users/maksym") == "~/Work/shop")
        #expect(PortEntry.abbreviate("/usr/libexec/rapportd", home: "/Users/maksym") == "/usr/libexec/rapportd")
    }

    @Test("Group order puts dev tooling above system noise")
    func groupOrder() {
        #expect(PortGroup.ddev.rank < PortGroup.other.rank)
        #expect(PortGroup.node.rank < PortGroup.other.rank)
        #expect(PortGroup.allCases.last == .other)
    }
}
