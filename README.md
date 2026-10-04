<h1 align="center">FreePort</h1>

<p align="center">
  <strong>See which app is using which port on macOS — and free it in one click.</strong><br>
  A tiny menu bar app that understands Docker, OrbStack, DDEV, Node, Bun and PHP.
</p>

<p align="center">
  <a href="https://github.com/Etyamor/freeport/actions/workflows/ci.yml"><img src="https://github.com/Etyamor/freeport/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Etyamor/freeport/releases/latest"><img src="https://img.shields.io/github/v/release/Etyamor/freeport?label=download" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple" alt="macOS 13+">
</p>

<p align="center"><a href="https://etyamor.github.io/freeport/"><strong>freeport website →</strong></a></p>

---

## Why

`lsof -i :3000` tells you a port is taken by **OrbStack**. That is true and useless —
you still don't know which of your eight containers it is, or how to stop it.

FreePort resolves the real owner:

| What `lsof` says | What FreePort says |
| --- | --- |
| `OrbStack` on `:32768` | `wp-to-sanity · web` — ddev/ddev-webserver → :80 |
| `OrbStack` on `:5433` | `cooknotes-db-1` — postgres:17-alpine → :5432 |
| `node` on `:3000` | `node` — ~/Work/CookNotes |
| `node` on `:7265` | `node` — Raycast Backend |

Then it frees the port the correct way for whatever owns it.

## Features

- **Container-aware.** Ports held by the Docker proxy are matched to the real
  container through the Docker socket. Works with Docker Desktop, OrbStack,
  Colima and Rancher Desktop.
- **DDEV-aware.** Containers are grouped by `com.ddev.site-name`, and freeing one
  stops the whole project — web *and* db — instead of leaving half a site running.
- **Project paths.** Node and Bun processes show their working directory, so two
  `node` rows are actually distinguishable.
- **Frees correctly, not bluntly.** A process gets `SIGTERM`, 1.5s to exit, then
  `SIGKILL`. A container is stopped through the Docker API, because killing the
  proxy process would not release the port.
- **Safe by default.** Only processes you own can be signalled. System daemons are
  refused outright, and shared infrastructure like `ddev-router` asks first.
- **Fast.** Native Swift, no Electron, under 1 MB, idles at a 20-second poll.
- **Also a CLI.** The same binary runs headless.

## Install

Download the latest release, unzip, drag to Applications:

**[⬇ Download FreePort](https://github.com/Etyamor/freeport/releases/latest)**

The app is ad-hoc signed rather than notarized (notarization requires a paid Apple
Developer account, and this is free software). macOS will therefore quarantine it on
first launch. Clear that once:

```bash
xattr -dr com.apple.quarantine /Applications/FreePort.app
```

Or build it yourself, which avoids the quarantine entirely:

```bash
git clone https://github.com/Etyamor/freeport.git
cd freeport
./build.sh --install
```

Requires macOS 13 or later. Xcode command line tools are enough to build.

## Using it

| Action | How |
| --- | --- |
| Free a port | Click the ✕ on its row |
| Free a port by number | Type the number in the search field, press ⏎ |
| Filter | Type anything — port, app name, container, or path |
| Open it | Right-click a row → Open in browser |
| Reveal the project | Right-click a row → Reveal … |
| Collapse a group | Click the group header |

Refresh interval, menu bar count, hiding other users' ports and launch-at-login all
live behind the gear icon.

### Command line

```bash
FreePort --list          # print every listening port
FreePort --free 3000     # release whatever holds :3000
```

Worth aliasing:

```bash
alias ports='/Applications/FreePort.app/Contents/MacOS/FreePort --list'
alias freeport='/Applications/FreePort.app/Contents/MacOS/FreePort --free'
```

## Limits

- Ports owned by **root or another user** are listed but cannot be freed. That needs
  `sudo`, which a menu bar app has no business holding.
- **UDP is not shown.** Dev servers are effectively always TCP.
- Docker enrichment needs a reachable socket. Without one, containers still appear —
  just under their proxy process name.
- **Launch at login** requires the app to be in `/Applications`; `SMAppService`
  refuses to register a bundle from an arbitrary location.

## Development

```bash
swift build          # build
swift test           # run the test suite
./build.sh           # assemble FreePort.app
./build.sh --universal   # Apple Silicon + Intel
```

The package splits in two so the logic is testable without a UI:

| Target | Contents |
| --- | --- |
| `FreePortKit` | `PortScanner` (lsof/ps parsing, release logic), `DockerClient`, `UnixHTTP`, models, CLI |
| `FreePort` | SwiftUI views, `PortStore`, the status item |

Every parsing step is a pure function over command output, so the fiddly parts —
`lsof -F` field mode, chunked HTTP over a Unix socket, ddev's empty label —
are covered by tests rather than by a particular machine's process list.

## License

MIT — see [LICENSE](LICENSE).
