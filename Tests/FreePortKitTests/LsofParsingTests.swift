import Testing
import Foundation
@testable import FreePortKit

/// Fixtures are trimmed from real `lsof -F` output on a machine running
/// OrbStack, ddev, Node and PhpStorm.
@Suite("lsof field-mode parsing")
struct LsofParsingTests {

    @Test("Parses one process with IPv4 and IPv6 sockets")
    func parsesProcessBlock() {
        let output = """
        p945
        crapportd
        Lmaksym
        f15
        tIPv4
        n*:61352
        f16
        tIPv6
        n*:61352
        """
        let entries = PortScanner.parseListening(output, excluding: 1)

        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.port == 61352 })
        #expect(entries.allSatisfy { $0.command == "rapportd" })
        #expect(entries.allSatisfy { $0.user == "maksym" })
        #expect(entries.map(\.isIPv6) == [false, true])
    }

    @Test("Carries command and user across multiple processes")
    func separatesProcesses() {
        let output = """
        p100
        cnode
        Lmaksym
        f7
        tIPv4
        n127.0.0.1:3000
        p200
        cpostgres
        Lroot
        f9
        tIPv4
        n*:5432
        """
        let entries = PortScanner.parseListening(output, excluding: 1)

        #expect(entries.count == 2)
        #expect(entries[0].command == "node")
        #expect(entries[0].user == "maksym")
        #expect(entries[1].command == "postgres")
        #expect(entries[1].user == "root")
    }

    /// A process with no `L` field must not inherit the previous one's user,
    /// or we'd offer to kill something we don't own.
    @Test("A missing user field does not leak from the previous process")
    func doesNotLeakUserBetweenProcesses() {
        let output = """
        p100
        cmine
        Lmaksym
        f7
        tIPv4
        n127.0.0.1:3000
        p200
        ctheirs
        f9
        tIPv4
        n127.0.0.1:4000
        """
        let entries = PortScanner.parseListening(output, excluding: 1)

        #expect(entries[1].command == "theirs")
        #expect(entries[1].user == "")
        #expect(entries[1].releaseAction(ddevSiblings: [], currentUser: "maksym")
                == .notPermitted(reason: "Owned by . Releasing it would need sudo."))
    }

    @Test("Excludes our own process so the app can't list itself")
    func excludesSelf() {
        let output = """
        p4242
        cFreePort
        Lmaksym
        f3
        tIPv4
        n127.0.0.1:9999
        """
        #expect(PortScanner.parseListening(output, excluding: 4242).isEmpty)
    }

    @Test("Ignores empty output")
    func handlesEmptyOutput() {
        #expect(PortScanner.parseListening("", excluding: 1).isEmpty)
    }

    @Test("Address forms", arguments: [
        ("*:8080",               "*",            8080),
        ("127.0.0.1:3000",       "127.0.0.1",    3000),
        ("[::1]:32222",          "::1",          32222),
        ("[fe80::1%lo0]:123",    "fe80::1%lo0",  123),
        ("192.168.0.105:443",    "192.168.0.105", 443),
    ])
    func parsesAddresses(raw: String, address: String, port: Int) {
        let parsed = PortScanner.parseAddress(raw)
        #expect(parsed?.address == address)
        #expect(parsed?.port == port)
    }

    @Test("Rejects malformed or out-of-range addresses", arguments: [
        "no-colon", "127.0.0.1:", "127.0.0.1:notaport", "*:0", "*:70000", "",
    ])
    func rejectsBadAddresses(raw: String) {
        #expect(PortScanner.parseAddress(raw) == nil)
    }

    @Test("Reads working directories from lsof -d cwd")
    func parsesWorkingDirectories() {
        let output = """
        p100
        fcwd
        n/Users/maksym/Work/shop
        p200
        fcwd
        n/
        """
        let map = PortScanner.parseWorkingDirectories(output)
        #expect(map[100] == "/Users/maksym/Work/shop")
        #expect(map[200] == "/")
    }

    @Test("Reads full command lines from ps, including arguments with spaces")
    func parsesCommandLines() {
        let output = """
          100 /usr/local/bin/node /Users/maksym/Work/My Shop/server.js --port 3000
         2000 /Applications/OrbStack.app/Contents/MacOS/OrbStack
        """
        let map = PortScanner.parseCommandLines(output)
        #expect(map[100] == "/usr/local/bin/node /Users/maksym/Work/My Shop/server.js --port 3000")
        #expect(map[2000] == "/Applications/OrbStack.app/Contents/MacOS/OrbStack")
    }
}
