import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Bridge Binary

/// Log to stderr only when --verbose is passed.
let verbose = CommandLine.arguments.contains("--verbose")
func log(_ msg: String) {
    guard verbose else { return }
    FileHandle.standardError.write("[bridge] \(msg)\n".data(using: .utf8)!)
}

/// Read all data from stdin until EOF.
func readStdin() -> Data {
    FileHandle.standardInput.readDataToEndOfFile()
}

/// Connect to the Unix domain socket. Returns fd or -1.
func connectToSocket() -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let path = CodeIslandConstants.socketPath
    withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
        path.withCString { cString in
            let len = min(strlen(cString), MemoryLayout.size(ofValue: sunPathPtr.pointee) - 1)
            memcpy(sunPathPtr, cString, len)
        }
    }

    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            connect(fd, sockaddrPtr, addrLen)
        }
    }

    if result < 0 {
        close(fd)
        return -1
    }

    return fd
}

// MARK: - Main

let stdinData = readStdin()
log("read \(stdinData.count) bytes from stdin")

guard !stdinData.isEmpty,
      let event = try? JSONDecoder().decode(HookEventPayload.self, from: stdinData) else {
    log("failed to parse stdin, exiting")
    exit(0)
}

log("event: \(event.hook_event_name ?? "nil")")

let fd = connectToSocket()
guard fd >= 0 else {
    log("failed to connect to socket, exiting")
    exit(0)
}

defer { close(fd) }

// Parse --source flag (e.g., --source codex)
var source: String? = nil
if let idx = CommandLine.arguments.firstIndex(of: "--source"),
   idx + 1 < CommandLine.arguments.count {
    source = CommandLine.arguments[idx + 1]
}

let message = BridgeMessage(event: event, source: source)
guard SocketProtocol.writeMessage(fd: fd, value: message) else {
    log("failed to write message to socket, exiting")
    exit(0)
}

log("sent event, waiting for response...")

guard let response = SocketProtocol.readMessage(fd: fd, as: BridgeResponse.self) else {
    log("failed to read response from socket, exiting")
    exit(0)
}

log("got response: type=\(response.type) decision=\(response.decision ?? "nil")")

// Output the permission decision in the format each hook type expects
if let decision = response.decision {
    let jsonData: Data?
    switch event.hook_event_name {
    case "PreToolUse":
        jsonData = try? JSONEncoder().encode(
            PreToolUseHookOutput(decision: decision, reason: response.reason, updatedInput: response.updatedInput)
        )
    case "PermissionRequest":
        jsonData = try? JSONEncoder().encode(
            PermissionRequestHookOutput(behavior: decision, message: response.reason)
        )
    default:
        jsonData = nil
    }
    if let data = jsonData {
        log("writing to stdout: \(String(data: data, encoding: .utf8) ?? "nil")")
        FileHandle.standardOutput.write(data)
    } else {
        log("no output for event type \(event.hook_event_name ?? "nil")")
    }
} else {
    log("no decision in response, not writing output")
}

log("exiting 0")
exit(0)
