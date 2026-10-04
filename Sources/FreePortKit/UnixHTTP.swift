import Foundation

/// Minimal HTTP/1.1 client over a Unix domain socket.
/// Docker's API is only reachable this way, and URLSession can't do AF_UNIX.
public enum UnixHTTP {
    public struct Response: Equatable {
        public let status: Int
        public let body: Data
    }

    public enum Failure: LocalizedError, Equatable {
        case socket(String)
        case malformedResponse

        public var errorDescription: String? {
            switch self {
            case .socket(let m): return m
            case .malformedResponse: return "Malformed HTTP response from the Docker socket."
            }
        }
    }

    public static func send(socketPath: String,
                     method: String,
                     path: String,
                     timeout: TimeInterval = 4) throws -> Response {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket("socket() failed: \(errno)") }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < capacity else { throw Failure.socket("Socket path too long.") }
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                _ = strncpy(dst, socketPath, capacity - 1)
            }
        }

        let connected = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw Failure.socket("Can't reach \(socketPath) (errno \(errno)). Is Docker running?")
        }

        let request = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
        try request.withCString { cstr in
            var remaining = strlen(cstr)
            var cursor = cstr
            while remaining > 0 {
                let written = write(fd, cursor, remaining)
                guard written > 0 else { throw Failure.socket("write() failed: \(errno)") }
                cursor += written
                remaining -= written
            }
        }

        var raw = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 { raw.append(contentsOf: buffer[0..<n]) } else { break }
        }

        return try parse(raw)
    }

    static func parse(_ raw: Data) throws -> Response {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = raw.range(of: separator) else { throw Failure.malformedResponse }
        let headerText = String(decoding: raw[raw.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var body = raw[headerEnd.upperBound...]

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: true)
        guard let statusLine = lines.first else { throw Failure.malformedResponse }
        let status = statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0

        let chunked = lines.dropFirst().contains {
            $0.lowercased().hasPrefix("transfer-encoding:") && $0.lowercased().contains("chunked")
        }
        if chunked { body = dechunk(body)[...] }

        return Response(status: status, body: Data(body))
    }

    static func dechunk(_ data: Data.SubSequence) -> Data {
        var out = Data()
        var rest = Data(data)
        let crlf = Data("\r\n".utf8)
        while let lineEnd = rest.range(of: crlf) {
            let sizeLine = String(decoding: rest[rest.startIndex..<lineEnd.lowerBound], as: UTF8.self)
            let hex = sizeLine.split(separator: ";").first.map(String.init) ?? sizeLine
            guard let size = Int(hex.trimmingCharacters(in: .whitespaces), radix: 16), size > 0 else { break }
            let chunkStart = lineEnd.upperBound
            let chunkEnd = rest.index(chunkStart, offsetBy: size, limitedBy: rest.endIndex) ?? rest.endIndex
            out.append(rest[chunkStart..<chunkEnd])
            let next = rest.index(chunkEnd, offsetBy: 2, limitedBy: rest.endIndex) ?? rest.endIndex
            rest = Data(rest[next...])
        }
        return out
    }
}
