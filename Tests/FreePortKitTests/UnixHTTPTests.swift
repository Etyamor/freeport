import Testing
import Foundation
@testable import FreePortKit

/// URLSession can't speak to a Unix socket, so this little HTTP reader is
/// hand-rolled — which makes it exactly the sort of code worth testing.
@Suite("HTTP response parsing")
struct UnixHTTPTests {

    @Test("Reads status and body from a content-length response")
    func parsesSimpleResponse() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n[]".utf8)
        let response = try UnixHTTP.parse(raw)

        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == "[]")
    }

    @Test("Reads a 204 with no body, as returned by container stop")
    func parsesNoContent() throws {
        let response = try UnixHTTP.parse(Data("HTTP/1.1 204 No Content\r\n\r\n".utf8))

        #expect(response.status == 204)
        #expect(response.body.isEmpty)
    }

    @Test("Reassembles a chunked body")
    func parsesChunkedResponse() throws {
        let raw = Data("""
        HTTP/1.1 200 OK\r
        Transfer-Encoding: chunked\r
        \r
        4\r
        [{\"a\r
        5\r
        \":1}]\r
        0\r
        \r

        """.utf8)
        let response = try UnixHTTP.parse(raw)

        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == "[{\"a\":1}]")
    }

    @Test("Handles a chunk-size line with extensions")
    func parsesChunkExtensions() {
        let body = Data("3;name=value\r\nabc\r\n0\r\n\r\n".utf8)
        #expect(String(decoding: UnixHTTP.dechunk(body[...]), as: UTF8.self) == "abc")
    }

    @Test("Case-insensitive transfer-encoding header")
    func caseInsensitiveHeader() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nTRANSFER-ENCODING: Chunked\r\n\r\n2\r\nhi\r\n0\r\n\r\n".utf8)
        #expect(String(decoding: try UnixHTTP.parse(raw).body, as: UTF8.self) == "hi")
    }

    @Test("Surfaces an error status instead of pretending it worked")
    func parsesErrorStatus() throws {
        let raw = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nno such c".utf8)
        #expect(try UnixHTTP.parse(raw).status == 404)
    }

    @Test("A response with no header terminator is rejected")
    func rejectsTruncatedResponse() {
        #expect(throws: UnixHTTP.Failure.self) {
            try UnixHTTP.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 2".utf8))
        }
    }
}
