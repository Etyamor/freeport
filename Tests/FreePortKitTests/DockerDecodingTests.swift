import Testing
import Foundation
@testable import FreePortKit

/// Payloads are trimmed from a real `GET /v1.41/containers/json` response.
@Suite("Docker API decoding")
struct DockerDecodingTests {

    private func decode(_ json: String) throws -> [ContainerInfo] {
        try DockerClient.decodeContainers(Data(json.utf8))
    }

    @Test("Decodes name, image and published ports")
    func decodesContainer() throws {
        let containers = try decode("""
        [{"Id":"abc123def456","Names":["/viburnum-postgres-1"],"Image":"postgres:16-alpine",
          "Status":"Up 2 hours","Labels":{},
          "Ports":[{"IP":"0.0.0.0","PrivatePort":5432,"PublicPort":5432,"Type":"tcp"}]}]
        """)

        #expect(containers.count == 1)
        #expect(containers[0].name == "viburnum-postgres-1")
        #expect(containers[0].image == "postgres:16-alpine")
        #expect(containers[0].portMap == [5432: 5432])
    }

    @Test("Reads the ddev project label")
    func decodesDdevLabel() throws {
        let containers = try decode("""
        [{"Id":"a","Names":["/ddev-wp-to-sanity-web"],"Image":"ddev/ddev-webserver:v1.25.2",
          "Status":"Up","Labels":{"com.ddev.site-name":"wp-to-sanity"},
          "Ports":[{"IP":"127.0.0.1","PrivatePort":80,"PublicPort":32768,"Type":"tcp"}]}]
        """)

        #expect(containers[0].ddevProject == "wp-to-sanity")
        #expect(containers[0].shortRole == "web")
    }

    /// ddev's shared services set the label to an empty string. Treating that
    /// as a project name produced the " · ddev-router" title in v0.
    @Test("An empty ddev label is treated as absent")
    func emptyDdevLabelIsNil() throws {
        let containers = try decode("""
        [{"Id":"b","Names":["/ddev-router"],"Image":"ddev/ddev-traefik-router:v1.25.2",
          "Status":"Up","Labels":{"com.ddev.site-name":""},"Ports":[]}]
        """)

        #expect(containers[0].ddevProject == nil)
        #expect(containers[0].shortRole == "ddev-router")
    }

    @Test("Unpublished container ports are ignored")
    func skipsUnpublishedPorts() throws {
        let containers = try decode("""
        [{"Id":"c","Names":["/internal"],"Image":"redis","Status":"Up",
          "Labels":{},"Ports":[{"PrivatePort":6379,"Type":"tcp"}]}]
        """)

        #expect(containers[0].portMap.isEmpty)
    }

    @Test("Survives missing optional fields")
    func toleratesSparsePayload() throws {
        let containers = try decode("""
        [{"Id":"0123456789abcdef"}]
        """)

        #expect(containers[0].name == "0123456789ab")
        #expect(containers[0].image == "unknown")
        #expect(containers[0].portMap.isEmpty)
    }

    @Test("An empty list is not an error")
    func decodesEmptyList() throws {
        #expect(try decode("[]").isEmpty)
    }

    @Test("Malformed JSON throws rather than returning nonsense")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            try DockerClient.decodeContainers(Data("not json".utf8))
        }
    }

    @Test("Socket candidates cover the common Docker runtimes")
    func socketCandidates() {
        let paths = DockerClient.candidateSockets.joined(separator: " ")
        #expect(paths.contains("orbstack"))
        #expect(paths.contains("/var/run/docker.sock"))
        #expect(paths.contains("colima"))
    }
}
