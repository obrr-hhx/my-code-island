import Foundation

/// Lightweight HTTP server serving session status as JSON.
/// Enables team visibility via `curl http://localhost:23456/status`
/// or a browser dashboard.
@MainActor
final class DashboardServer {
    static let shared = DashboardServer()
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private weak var appState: AppState?

    static let port: UInt16 = 23456

    private init() {}

    func start(appState: AppState) {
        guard !isRunning else { return }
        self.appState = appState

        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[DashboardServer] Failed to create socket")
            return
        }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            print("[DashboardServer] Failed to bind on port \(Self.port)")
            close(serverSocket)
            return
        }

        listen(serverSocket, 5)
        isRunning = true
        print("[DashboardServer] Listening on http://localhost:\(Self.port)/status")

        // Accept connections on a background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self, self.isRunning {
                let clientFd = accept(self.serverSocket, nil, nil)
                guard clientFd >= 0 else { continue }
                Task { @MainActor in
                    self.handleClient(clientFd)
                }
            }
        }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    // MARK: - HTTP Handling

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        // Read request (we only need the first line)
        var buffer = [UInt8](repeating: 0, count: 2048)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { return }

        let request = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""
        let firstLine = request.split(separator: "\r\n").first ?? ""

        if firstLine.contains("/status") {
            sendJSON(fd)
        } else if firstLine.contains("/ ") || firstLine.contains("/dashboard") {
            sendDashboardHTML(fd)
        } else {
            send404(fd)
        }
    }

    private func sendJSON(_ fd: Int32) {
        guard let appState else { return }

        let sessions: [[String: Any]] = appState.sessions.map { s in
            [
                "project": s.projectName,
                "agent": s.session.agentType.rawValue,
                "status": statusString(s.status),
                "terminal": s.terminalName,
                "tool": s.currentTool ?? "",
                "toolCalls": s.toolCallCount,
                "errors": s.errorCount,
                "elapsed": s.session.elapsed,
                "subagents": s.activeSubagents.map { ["type": $0.agentType, "id": $0.id] },
                "alive": s.isAlive,
            ]
        }

        let json: [String: Any] = [
            "sessions": sessions,
            "totalSessions": appState.sessions.count,
            "pendingPermissions": appState.pendingPermissions.count,
            "theme": appState.appTheme.rawValue,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let body = String(data: data, encoding: .utf8) else { return }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        _ = response.withCString { write(fd, $0, strlen($0)) }
    }

    private func sendDashboardHTML(_ fd: Int32) {
        let html = """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8"><title>Code Island Dashboard</title>
        <meta http-equiv="refresh" content="5">
        <style>
        body{background:#0a0a0a;color:#e5e5e5;font-family:'Courier New',monospace;padding:20px;margin:0}
        h1{color:#06b6d4;font-size:18px;border-bottom:1px solid #333;padding-bottom:8px}
        .session{background:#1a1a1a;border:1px solid #333;border-radius:6px;padding:12px;margin:8px 0}
        .active{border-color:#06b6d4}
        .project{color:#e5e5e5;font-weight:bold;font-size:14px}
        .status{display:inline-block;padding:2px 6px;border-radius:3px;font-size:11px;margin-left:8px}
        .running{background:#06b6d422;color:#06b6d4}
        .idle{background:#55555522;color:#555}
        .waiting{background:#d9775722;color:#d97757}
        .badge{display:inline-block;padding:1px 4px;border-radius:2px;font-size:10px;margin-right:4px}
        .cc{background:#06b6d422;color:#06b6d4}
        .cx{background:#22c55e22;color:#22c55e}
        .dr{background:#a855f722;color:#a855f7}
        .stats{color:#888;font-size:11px;margin-top:4px}
        .subagent{display:inline-block;background:#06b6d411;border:1px solid #06b6d433;padding:1px 5px;border-radius:3px;font-size:10px;color:#06b6d4;margin:2px}
        </style>
        </head><body>
        <h1>&#x2726; CODE ISLAND DASHBOARD</h1>
        <div id="content">Loading...</div>
        <script>
        async function refresh(){
          try{
            const r=await fetch('/status');
            const d=await r.json();
            let h='';
            if(d.pendingPermissions>0)h+='<div style="color:#d97757;padding:8px;border:1px solid #d97757;border-radius:4px;margin-bottom:8px">⚠ '+d.pendingPermissions+' PERMISSION REQUEST(S) PENDING</div>';
            for(const s of d.sessions){
              const cls=s.status==='idle'?'':'active';
              const st=s.status==='idle'?'idle':s.status==='waiting'?'waiting':'running';
              const agentCls=s.agent==='codex'?'cx':s.agent==='droid'?'dr':'cc';
              h+='<div class="session '+cls+'">';
              h+='<span class="badge '+agentCls+'">'+s.agent.toUpperCase()+'</span>';
              h+='<span class="project">'+s.project+'</span>';
              h+='<span class="status '+st+'">'+s.status.toUpperCase()+(s.tool?' · '+s.tool:'')+'</span>';
              h+='<span style="float:right;color:#555">'+s.terminal+' · '+s.elapsed+'</span>';
              if(s.toolCalls>0)h+='<div class="stats">'+s.toolCalls+' calls'+(s.errors>0?' · '+s.errors+' errors':'')+'</div>';
              if(s.subagents&&s.subagents.length>0){h+='<div>';s.subagents.forEach(a=>{h+='<span class="subagent">'+a.type+'</span>'});h+='</div>'}
              h+='</div>';
            }
            if(d.sessions.length===0)h='<div style="color:#555;text-align:center;padding:40px">No active sessions</div>';
            document.getElementById('content').innerHTML=h;
          }catch(e){document.getElementById('content').innerHTML='<div style="color:red">Connection error</div>'}
        }
        refresh();setInterval(refresh,5000);
        </script>
        </body></html>
        """
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
        _ = response.withCString { write(fd, $0, strlen($0)) }
    }

    private func send404(_ fd: Int32) {
        let body = "Not Found"
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
        _ = response.withCString { write(fd, $0, strlen($0)) }
    }

    private func statusString(_ status: SessionStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .running(let tool): return tool != nil ? "running" : "thinking"
        case .waitingPermission: return "waiting"
        }
    }
}
