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
            var dict: [String: Any] = [
                "project": s.projectName,
                "cwd": s.session.cwd,
                "agent": s.session.agentType.rawValue,
                "status": statusString(s.status),
                "terminal": s.terminalName,
                "tool": s.currentTool ?? "",
                "toolCalls": s.toolCallCount,
                "errors": s.errorCount,
                "compacts": s.compactCount,
                "permissionRequests": s.permissionRequestCount,
                "elapsed": s.session.elapsed,
                "startedAt": s.session.startedAt,
                "subagents": s.activeSubagents.map { ["type": $0.agentType, "id": $0.id] },
                "alive": s.isAlive,
                "pid": s.pid,
                "topTools": s.topTools.map { ["name": $0.name, "count": $0.count] },
                "activeFiles": Array(s.activeFiles),
            ]
            if let mode = s.permissionModeOverride {
                dict["permissionMode"] = mode.rawValue
            }
            return dict
        }

        // Group by project for the API
        let projects = Dictionary(grouping: appState.sessions) { $0.session.cwd }
        let projectSummaries: [[String: Any]] = projects.map { cwd, sessions in
            [
                "project": (cwd as NSString).lastPathComponent,
                "cwd": cwd,
                "sessionCount": sessions.count,
                "totalToolCalls": sessions.reduce(0) { $0 + $1.toolCallCount },
                "totalErrors": sessions.reduce(0) { $0 + $1.errorCount },
                "agents": sessions.map { $0.session.agentType.rawValue },
            ]
        }

        let json: [String: Any] = [
            "sessions": sessions,
            "projects": projectSummaries,
            "totalSessions": appState.sessions.count,
            "aliveSessions": appState.sessions.filter(\.isAlive).count,
            "pendingPermissions": appState.pendingPermissions.count,
            "pendingQuestions": appState.pendingQuestions.count,
            "theme": appState.appTheme.rawValue,
            "permissionMode": appState.permissionMode.rawValue,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let body = String(data: data, encoding: .utf8) else { return }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        _ = response.withCString { write(fd, $0, strlen($0)) }
    }

    private func sendDashboardHTML(_ fd: Int32) {
        let html = Self.dashboardHTML
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
        _ = response.withCString { write(fd, $0, strlen($0)) }
    }

    // MARK: - Dashboard HTML

    private static let dashboardHTML: String = ##"""
    <!DOCTYPE html>
    <html lang="en"><head>
    <meta charset="utf-8">
    <title>Code Island Dashboard</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
    @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;700&display=swap');

    *{margin:0;padding:0;box-sizing:border-box}

    :root{
      --bg:#0a0a0a;--panel:#111;--card:#1a1a1a;--border:#333;
      --text:#e5e5e5;--text2:#888;--muted:#555;
      --cyan:#06b6d4;--green:#22c55e;--orange:#d97757;--red:#ef4444;
      --purple:#a855f7;--amber:#f59e0b;--blue:#3b82f6;
    }

    body{
      background:var(--bg);color:var(--text);
      font-family:'JetBrains Mono','Courier New',monospace;
      min-height:100vh;overflow-x:hidden;
    }

    /* Scanline overlay */
    body::after{
      content:'';position:fixed;inset:0;pointer-events:none;z-index:9999;
      background:repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(0,0,0,.03) 2px,rgba(0,0,0,.03) 4px);
    }

    /* Header */
    .header{
      background:var(--panel);border-bottom:1px solid var(--border);
      padding:16px 24px;display:flex;align-items:center;gap:16px;
      position:sticky;top:0;z-index:100;backdrop-filter:blur(10px);
    }
    .logo{
      font-size:20px;font-weight:700;color:var(--cyan);
      text-shadow:0 0 10px rgba(6,182,212,.4),0 0 20px rgba(6,182,212,.2);
      letter-spacing:2px;
    }
    .logo span{opacity:.5}
    .header-stats{display:flex;gap:16px;margin-left:auto;align-items:center}
    .header-stat{
      font-size:11px;color:var(--text2);display:flex;align-items:center;gap:4px;
    }
    .header-stat .val{font-weight:700;font-size:13px}
    .pulse-dot{
      width:8px;height:8px;border-radius:50%;background:var(--green);
      animation:pulse 2s ease-in-out infinite;
    }
    @keyframes pulse{0%,100%{opacity:.4;transform:scale(.8)}50%{opacity:1;transform:scale(1.2)}}

    .live-badge{
      font-size:9px;font-weight:700;color:var(--green);
      border:1px solid rgba(34,197,94,.3);background:rgba(34,197,94,.08);
      padding:2px 8px;border-radius:3px;letter-spacing:1px;
      display:flex;align-items:center;gap:6px;
    }

    /* Alert banner */
    .alert{
      margin:16px 24px 0;padding:12px 16px;border-radius:6px;
      border:1px solid var(--orange);background:rgba(217,119,87,.06);
      color:var(--orange);font-size:12px;font-weight:500;
      display:flex;align-items:center;gap:8px;
      animation:alertPulse 3s ease-in-out infinite;
    }
    @keyframes alertPulse{0%,100%{border-color:rgba(217,119,87,.4)}50%{border-color:var(--orange)}}
    .alert-icon{font-size:16px}
    .alert.hidden{display:none}

    /* Content */
    .content{padding:20px 24px;display:flex;gap:20px}

    /* Sidebar - project summary */
    .sidebar{width:260px;flex-shrink:0}
    .sidebar-card{
      background:var(--panel);border:1px solid var(--border);border-radius:8px;
      padding:14px;margin-bottom:12px;
    }
    .sidebar-title{
      font-size:9px;font-weight:700;color:var(--muted);
      letter-spacing:2px;margin-bottom:10px;
    }
    .project-item{
      display:flex;align-items:center;gap:8px;padding:6px 8px;
      border-radius:4px;margin-bottom:2px;cursor:pointer;transition:background .15s;
    }
    .project-item:hover{background:rgba(255,255,255,.03)}
    .project-item.active{background:rgba(6,182,212,.06);border-left:2px solid var(--cyan)}
    .project-dot{width:6px;height:6px;border-radius:50%;flex-shrink:0}
    .project-name{font-size:12px;font-weight:500;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .project-count{font-size:10px;color:var(--muted);font-weight:700}

    /* Stats grid */
    .stats-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}
    .stat-box{
      background:var(--card);border:1px solid var(--border);border-radius:6px;
      padding:10px;text-align:center;
    }
    .stat-val{font-size:18px;font-weight:700;line-height:1}
    .stat-label{font-size:8px;color:var(--muted);letter-spacing:1px;margin-top:4px}

    /* Main panel */
    .main{flex:1;min-width:0}

    /* Session card */
    .session{
      background:var(--card);border:1px solid var(--border);border-radius:8px;
      padding:14px 16px;margin-bottom:10px;transition:all .2s;position:relative;
      overflow:hidden;
    }
    .session::before{
      content:'';position:absolute;left:0;top:0;bottom:0;width:3px;
      border-radius:8px 0 0 8px;
    }
    .session.st-running::before{background:var(--cyan)}
    .session.st-thinking::before{background:var(--cyan);animation:pulse 2s ease-in-out infinite}
    .session.st-waiting::before{background:var(--orange);animation:pulse 1.5s ease-in-out infinite}
    .session.st-idle::before{background:var(--muted)}
    .session:hover{border-color:rgba(255,255,255,.1);transform:translateY(-1px)}
    .session.dead{opacity:.45}

    .session-header{display:flex;align-items:center;gap:8px;margin-bottom:8px}
    .agent-badge{
      font-size:9px;font-weight:700;padding:2px 6px;border-radius:3px;letter-spacing:1px;
      flex-shrink:0;
    }
    .agent-cc{color:var(--cyan);background:rgba(6,182,212,.12);border:1px solid rgba(6,182,212,.2)}
    .agent-cx{color:var(--green);background:rgba(34,197,94,.12);border:1px solid rgba(34,197,94,.2)}
    .agent-dr{color:var(--purple);background:rgba(168,85,247,.12);border:1px solid rgba(168,85,247,.2)}

    .session-project{font-size:14px;font-weight:700;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .session-status{
      font-size:10px;font-weight:600;padding:3px 8px;border-radius:3px;letter-spacing:1px;
    }
    .status-running{color:var(--cyan);background:rgba(6,182,212,.1)}
    .status-thinking{color:var(--cyan);background:rgba(6,182,212,.08)}
    .status-waiting{color:var(--orange);background:rgba(217,119,87,.1);animation:alertPulse 2s infinite}
    .status-idle{color:var(--muted);background:rgba(85,85,85,.1)}

    .session-meta{display:flex;align-items:center;gap:12px;font-size:11px;color:var(--text2);flex-wrap:wrap}
    .meta-item{display:flex;align-items:center;gap:4px}
    .meta-icon{opacity:.5;font-size:10px}
    .meta-sep{color:var(--border)}

    /* Tool bar */
    .tool-bar{
      display:flex;gap:4px;margin-top:8px;flex-wrap:wrap;
    }
    .tool-chip{
      font-size:9px;padding:2px 6px;border-radius:3px;
      background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.06);
      color:var(--text2);display:flex;align-items:center;gap:3px;
    }
    .tool-chip .count{font-weight:700;color:var(--text)}
    .tool-chip.current{border-color:rgba(6,182,212,.3);color:var(--cyan);background:rgba(6,182,212,.06)}

    /* Subagents */
    .subagents{display:flex;gap:4px;margin-top:6px;flex-wrap:wrap}
    .subagent{
      font-size:9px;padding:2px 6px;border-radius:3px;
      background:rgba(6,182,212,.06);border:1px solid rgba(6,182,212,.15);
      color:var(--cyan);display:flex;align-items:center;gap:4px;
    }
    .subagent-dot{width:4px;height:4px;border-radius:50%;background:var(--cyan);animation:pulse 2s infinite}

    /* Active files */
    .files{margin-top:6px;display:flex;gap:4px;flex-wrap:wrap}
    .file-chip{
      font-size:9px;padding:2px 6px;border-radius:3px;
      background:rgba(245,158,11,.06);border:1px solid rgba(245,158,11,.15);
      color:var(--amber);
    }

    /* Progress bar for analytics */
    .analytics-row{display:flex;gap:16px;margin-top:8px;align-items:center}
    .mini-stat{font-size:10px;display:flex;align-items:center;gap:3px}
    .mini-stat .n{font-weight:700}
    .mini-stat .l{color:var(--muted)}

    /* Empty state */
    .empty{
      text-align:center;padding:60px 20px;color:var(--muted);
    }
    .empty-icon{font-size:48px;margin-bottom:12px;opacity:.3}
    .empty-text{font-size:13px}

    /* Footer */
    .footer{
      text-align:center;padding:20px;font-size:9px;color:var(--muted);
      letter-spacing:1px;border-top:1px solid var(--border);margin-top:20px;
    }

    /* Responsive */
    @media(max-width:800px){
      .content{flex-direction:column}
      .sidebar{width:100%}
    }

    /* Refresh indicator */
    .refresh-bar{
      position:fixed;top:0;left:0;height:2px;background:var(--cyan);z-index:9998;
      transition:width .3s ease;opacity:0;
    }
    .refresh-bar.active{opacity:1}
    </style>
    </head><body>
    <div class="refresh-bar" id="refreshBar"></div>

    <div class="header">
      <div class="logo">&#x2726; CODE<span>:</span>ISLAND</div>
      <div class="header-stats">
        <div class="header-stat"><span class="val" id="hSessions">-</span> sessions</div>
        <div class="header-stat"><span class="val" id="hAlive">-</span> alive</div>
        <div class="header-stat"><span class="val" id="hPerms">-</span> pending</div>
        <div class="live-badge"><div class="pulse-dot"></div>LIVE</div>
      </div>
    </div>

    <div class="alert hidden" id="alert">
      <span class="alert-icon">&#x26A0;</span>
      <span id="alertText"></span>
    </div>

    <div class="content">
      <div class="sidebar">
        <div class="sidebar-card">
          <div class="sidebar-title">PROJECTS</div>
          <div id="projectList"></div>
        </div>
        <div class="sidebar-card">
          <div class="sidebar-title">OVERVIEW</div>
          <div class="stats-grid">
            <div class="stat-box"><div class="stat-val" id="sTotalCalls" style="color:var(--cyan)">0</div><div class="stat-label">TOOL CALLS</div></div>
            <div class="stat-box"><div class="stat-val" id="sTotalErrors" style="color:var(--red)">0</div><div class="stat-label">ERRORS</div></div>
            <div class="stat-box"><div class="stat-val" id="sTotalCompacts" style="color:var(--orange)">0</div><div class="stat-label">COMPACTS</div></div>
            <div class="stat-box"><div class="stat-val" id="sTotalPerms" style="color:var(--amber)">0</div><div class="stat-label">PERM REQS</div></div>
          </div>
        </div>
        <div class="sidebar-card">
          <div class="sidebar-title">SYSTEM</div>
          <div style="font-size:10px;color:var(--text2);line-height:1.8">
            <div>Theme: <span id="sTheme" style="color:var(--cyan)">-</span></div>
            <div>Mode: <span id="sMode" style="color:var(--green)">-</span></div>
            <div>Port: <span style="color:var(--muted)">23456</span></div>
          </div>
        </div>
      </div>

      <div class="main" id="sessionList"></div>
    </div>

    <div class="footer">CODE ISLAND DASHBOARD &middot; AUTO-REFRESH 3S &middot; http://localhost:23456</div>

    <script>
    let data=null, filter=null;

    function agentCls(a){return a==='codex'?'cx':a==='droid'?'dr':'cc'}
    function statusCls(s){return s==='waiting'?'status-waiting':s==='idle'?'status-idle':s==='thinking'?'status-thinking':'status-running'}
    function statusCardCls(s){return s==='waiting'?'st-waiting':s==='idle'?'st-idle':s==='thinking'?'st-thinking':'st-running'}
    function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}

    function renderProjects(d){
      const el=document.getElementById('projectList');
      if(!d.projects||!d.projects.length){el.innerHTML='<div style="color:var(--muted);font-size:10px;padding:8px">No projects</div>';return}
      const colors=['var(--cyan)','var(--green)','var(--purple)','var(--amber)','var(--blue)','var(--orange)'];
      el.innerHTML=d.projects.sort((a,b)=>b.sessionCount-a.sessionCount).map((p,i)=>{
        const c=colors[i%colors.length];
        const active=filter===p.cwd?' active':'';
        return `<div class="project-item${active}" onclick="toggleFilter('${esc(p.cwd)}')">
          <div class="project-dot" style="background:${c}"></div>
          <div class="project-name">${esc(p.project)}</div>
          <div class="project-count">${p.sessionCount}</div>
        </div>`;
      }).join('');
    }

    function renderSessions(d){
      const el=document.getElementById('sessionList');
      let sessions=d.sessions||[];
      if(filter)sessions=sessions.filter(s=>s.cwd===filter);

      if(!sessions.length){
        el.innerHTML='<div class="empty"><div class="empty-icon">&#x2726;</div><div class="empty-text">'
          +(filter?'No sessions in this project':'No active sessions')+'</div></div>';
        return;
      }

      // Sort: alive first, then by status priority (waiting > running > idle), then by elapsed
      const pri={waiting:0,running:1,thinking:1,idle:2};
      sessions.sort((a,b)=>{
        if(a.alive!==b.alive)return a.alive?-1:1;
        const pa=pri[a.status]??2, pb=pri[b.status]??2;
        if(pa!==pb)return pa-pb;
        return 0;
      });

      el.innerHTML=sessions.map(s=>{
        const ac=agentCls(s.agent);
        const sc=statusCls(s.status);
        const scc=statusCardCls(s.status);
        const dead=s.alive?'':'dead';

        let toolBar='';
        if(s.topTools&&s.topTools.length){
          toolBar='<div class="tool-bar">'+s.topTools.map(t=>
            `<div class="tool-chip${s.tool&&t.name===s.tool?' current':''}"><span class="count">${t.count}</span>${esc(t.name)}</div>`
          ).join('')+'</div>';
        }

        let subagents='';
        if(s.subagents&&s.subagents.length){
          subagents='<div class="subagents">'+s.subagents.map(a=>
            `<div class="subagent"><div class="subagent-dot"></div>${esc(a.type)}</div>`
          ).join('')+'</div>';
        }

        let files='';
        if(s.activeFiles&&s.activeFiles.length){
          files='<div class="files">'+s.activeFiles.map(f=>{
            const name=f.split('/').pop();
            return `<div class="file-chip">${esc(name)}</div>`;
          }).join('')+'</div>';
        }

        let analytics='';
        if(s.toolCalls>0){
          analytics=`<div class="analytics-row">
            <div class="mini-stat"><span class="n" style="color:var(--cyan)">${s.toolCalls}</span><span class="l">calls</span></div>
            ${s.errors>0?`<div class="mini-stat"><span class="n" style="color:var(--red)">${s.errors}</span><span class="l">errors</span></div>`:''}
            ${s.compacts>0?`<div class="mini-stat"><span class="n" style="color:var(--orange)">${s.compacts}</span><span class="l">compacts</span></div>`:''}
            ${s.permissionRequests>0?`<div class="mini-stat"><span class="n" style="color:var(--amber)">${s.permissionRequests}</span><span class="l">perms</span></div>`:''}
          </div>`;
        }

        const modeStr=s.permissionMode?`<span class="meta-sep">&middot;</span><span style="color:var(--amber)">${esc(s.permissionMode)}</span>`:'';

        return `<div class="session ${scc} ${dead}">
          <div class="session-header">
            <span class="agent-badge agent-${ac}">${s.agent.toUpperCase()}</span>
            <span class="session-project">${esc(s.project)}</span>
            <span class="session-status ${sc}">${s.status.toUpperCase()}${s.tool?' &middot; '+esc(s.tool):''}</span>
          </div>
          <div class="session-meta">
            <span class="meta-item"><span class="meta-icon">&#x25B6;</span>${esc(s.terminal)}</span>
            <span class="meta-sep">&middot;</span>
            <span class="meta-item">${esc(s.elapsed)}</span>
            ${s.pid>0?`<span class="meta-sep">&middot;</span><span class="meta-item" style="color:var(--muted)">PID ${s.pid}</span>`:''}
            ${modeStr}
            ${!s.alive?'<span class="meta-sep">&middot;</span><span style="color:var(--red);font-weight:700">DEAD</span>':''}
          </div>
          ${analytics}${toolBar}${subagents}${files}
        </div>`;
      }).join('');
    }

    function renderStats(d){
      document.getElementById('hSessions').textContent=d.totalSessions;
      document.getElementById('hAlive').textContent=d.aliveSessions;
      document.getElementById('hPerms').textContent=d.pendingPermissions||0;
      document.getElementById('sTheme').textContent=d.theme;
      document.getElementById('sMode').textContent=d.permissionMode;

      const ss=d.sessions||[];
      document.getElementById('sTotalCalls').textContent=ss.reduce((a,s)=>a+s.toolCalls,0);
      document.getElementById('sTotalErrors').textContent=ss.reduce((a,s)=>a+s.errors,0);
      document.getElementById('sTotalCompacts').textContent=ss.reduce((a,s)=>a+(s.compacts||0),0);
      document.getElementById('sTotalPerms').textContent=ss.reduce((a,s)=>a+(s.permissionRequests||0),0);

      const alert=document.getElementById('alert');
      const pending=(d.pendingPermissions||0)+(d.pendingQuestions||0);
      if(pending>0){
        alert.classList.remove('hidden');
        document.getElementById('alertText').textContent=`${pending} PERMISSION REQUEST${pending>1?'S':''} PENDING — Check Code Island`;
      }else{
        alert.classList.add('hidden');
      }
    }

    function toggleFilter(cwd){
      filter=filter===cwd?null:cwd;
      if(data){renderProjects(data);renderSessions(data);}
    }

    async function refresh(){
      const bar=document.getElementById('refreshBar');
      bar.style.width='0%';bar.classList.add('active');
      bar.style.width='30%';
      try{
        const r=await fetch('/status');
        bar.style.width='70%';
        data=await r.json();
        bar.style.width='100%';
        renderStats(data);renderProjects(data);renderSessions(data);
      }catch(e){
        document.getElementById('sessionList').innerHTML='<div class="empty"><div class="empty-icon" style="color:var(--red)">&#x2717;</div><div class="empty-text" style="color:var(--red)">Connection lost</div></div>';
      }
      setTimeout(()=>{bar.classList.remove('active');bar.style.width='0%'},500);
    }

    refresh();setInterval(refresh,3000);
    </script>
    </body></html>
    """##

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
