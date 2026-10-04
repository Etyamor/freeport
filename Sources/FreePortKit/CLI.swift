import Foundation

/// `FreePort --list` and `FreePort --free <port>` run headless and exit.
/// Handy for scripting, and for checking what the menu bar is about to show.
public enum CLI {
    public static func handleIfNeeded() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first else { return }

        switch first {
        case "--list", "-l":
            list()
            exit(0)
        case "--free", "-f":
            guard let port = args.dropFirst().first.flatMap(Int.init) else {
                FileHandle.standardError.write(Data("usage: FreePort --free <port>\n".utf8))
                exit(2)
            }
            free(port)
        case "--version", "-v":
            let info = Bundle.main.infoDictionary
            print("FreePort \(info?["CFBundleShortVersionString"] as? String ?? "dev")")
            exit(0)
        case "--help", "-h":
            print("""
            FreePort — see and free busy ports.

              FreePort              launch the menu bar app
              FreePort --list       print all listening ports
              FreePort --free PORT  release whatever holds PORT
              FreePort --version    print the version
            """)
            exit(0)
        default:
            return
        }
    }

    private static func list() {
        let snapshot = PortScanner.scan()
        if let error = snapshot.dockerError {
            FileHandle.standardError.write(Data("docker: \(error)\n".utf8))
        }
        let rows = snapshot.entries.sorted { $0.port < $1.port }
        guard !rows.isEmpty else { print("No listening TCP ports."); return }

        let groupWidth = max(5, rows.map { $0.group.rawValue.count }.max() ?? 5)
        let nameWidth = min(34, max(4, rows.map { $0.title.count }.max() ?? 4))
        print("PORT   \("GROUP".padded(groupWidth))  \("OWNER".padded(nameWidth))  DETAIL")
        for row in rows {
            let detail = row.subtitle ?? ""
            print("\(String(row.port).padded(6)) \(row.group.rawValue.padded(groupWidth))  \(row.title.truncated(nameWidth).padded(nameWidth))  \(detail)")
        }
    }

    private static func free(_ port: Int) {
        let snapshot = PortScanner.scan()
        guard let entry = snapshot.entries.first(where: { $0.port == port }) else {
            print("Nothing is listening on :\(port).")
            exit(0)
        }
        let siblings = entry.container?.ddevProject
            .map { project in snapshot.containers.filter { $0.ddevProject == project } } ?? []

        do {
            print(try PortScanner.release(entry.releaseAction(ddevSiblings: siblings), port: port))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

private extension String {
    func padded(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
    func truncated(_ width: Int) -> String {
        count <= width ? self : String(prefix(width - 1)) + "…"
    }
}
