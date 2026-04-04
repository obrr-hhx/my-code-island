import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Unix domain socket server that listens for bridge connections.
final class SocketServer {
    @MainActor static let shared = SocketServer()

    /// The server fd — accessed from multiple threads, protected by being set once before the accept thread starts.
    private var serverFd: Int32 = -1
    private var isRunning = false

    /// Callback invoked on the main thread when an event arrives.
    /// Set by HookEventRouter. Accessed from the accept thread via `shared`.
    /// Callback: (payload, source, replyHandler)
    @MainActor
    var onEvent: (@Sendable (HookEventPayload, String?, @escaping @Sendable (BridgeResponse) -> Void) -> Void)?

    @MainActor
    private init() {}

    /// Start listening on the Unix domain socket.
    @MainActor
    func start() {
        guard !isRunning else { return }

        unlink(CodeIslandConstants.socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            print("[SocketServer] Failed to create socket: \(errno)")
            return
        }

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
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFd, sockaddrPtr, addrLen)
            }
        }

        guard bindResult == 0 else {
            print("[SocketServer] Failed to bind: \(errno)")
            close(serverFd)
            serverFd = -1
            return
        }

        guard listen(serverFd, 16) == 0 else {
            print("[SocketServer] Failed to listen: \(errno)")
            close(serverFd)
            serverFd = -1
            return
        }

        isRunning = true
        print("[SocketServer] Listening on \(CodeIslandConstants.socketPath)")

        let fd = serverFd

        let thread = Thread {
            SocketServer.acceptLoop(serverFd: fd)
        }
        thread.name = "SocketServer.accept"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    @MainActor
    func stop() {
        isRunning = false
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(CodeIslandConstants.socketPath)
    }

    // MARK: - Static (nonisolated) handlers

    private nonisolated static func acceptLoop(serverFd: Int32) {
        while true {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else {
                if errno == EBADF || errno == EINVAL { break }
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async {
                handleConnection(clientFd)
            }
        }
    }

    private nonisolated static func handleConnection(_ fd: Int32) {
        defer { close(fd) }

        guard let data = SocketProtocol.readMessage(fd: fd),
              let message = try? JSONDecoder().decode(BridgeMessage.self, from: data) else {
            _ = SocketProtocol.writeMessage(fd: fd, value: BridgeResponse.ack())
            return
        }

        let event = message.event
        let source = message.source

        // Events that may need to block for a user decision
        let blockingEvents = ["PreToolUse", "PermissionRequest"]
        if let name = event.hook_event_name, blockingEvents.contains(name) {
            print("[SocketServer] blocking event: \(name)")
            let semaphore = DispatchSemaphore(value: 0)
            let box = ResponseBox()

            DispatchQueue.main.async {
                let handler = SocketServer.shared.onEvent
                handler?(event, source) { decision in
                    print("[SocketServer] replyHandler called: decision=\(decision.decision ?? "nil")")
                    box.response = decision
                    semaphore.signal()
                }
                if handler == nil {
                    semaphore.signal()
                }
            }

            // Wait for user response. Safety timeout prevents thread leak if bridge hangs.
            let waitResult = semaphore.wait(timeout: .now() + CodeIslandConstants.permissionTimeout)
            if waitResult == .timedOut {
                print("[SocketServer] Safety timeout (\(Int(CodeIslandConstants.permissionTimeout))s)")
                box.response = BridgeResponse.ack()
            } else {
                print("[SocketServer] Response: decision=\(box.response.decision ?? "nil")")
            }

            let writeOk = SocketProtocol.writeMessage(fd: fd, value: box.response)
            print("[SocketServer] wrote response back to bridge: \(writeOk)")
        } else {
            // Fire-and-forget: fetch CURRENT handler, send ACK immediately
            DispatchQueue.main.async {
                let handler = SocketServer.shared.onEvent
                handler?(event, source) { _ in }
            }
            _ = SocketProtocol.writeMessage(fd: fd, value: BridgeResponse.ack())
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    var response: BridgeResponse = BridgeResponse.ack()
}
