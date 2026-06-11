import AppKit
import Network

private let sessionPath = NSString(string: "~/.coincoding/session.json").expandingTildeInPath

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let githubUsername: String
    let githubAvatar: String?
    let expiresAt: Double
}

final class SupabaseAuth {
    static let shared = SupabaseAuth()
    let baseUrl = "https://kfvhqxxpqwetsnvavico.supabase.co"
    let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtmdmhxeHhwcXdldHNudmF2aWNvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMzY0OTcsImV4cCI6MjA5NjcxMjQ5N30.3XMcTMEUqNw3uBhx2hcoCLU13U_6DN_1a9i57QcqhY8"

    private(set) var session: AuthSession?
    var onChange: ((AuthSession?) -> Void)?
    private var server: CallbackServer?
    var isLoggedIn: Bool { session != nil }

    private init() { loadSession() }

    // MARK: - Public

    func login() {
        let s = CallbackServer()
        server = s
        s.start { [weak self] at, rt in
            self?.server = nil
            self?.fetchUser(at: at, rt: rt)
        }
        let url = "\(baseUrl)/auth/v1/authorize?provider=github&redirect_to=http://localhost:17778/callback"
        NSWorkspace.shared.open(URL(string: url)!)
    }

    func logout() {
        if let token = session?.accessToken {
            var r = URLRequest(url: URL(string: "\(baseUrl)/auth/v1/logout")!)
            r.httpMethod = "POST"
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.setValue(anonKey, forHTTPHeaderField: "apikey")
            URLSession.shared.dataTask(with: r).resume()
        }
        session = nil
        try? FileManager.default.removeItem(atPath: sessionPath)
        DispatchQueue.main.async { self.onChange?(nil) }
    }

    // MARK: - Private

    private func loadSession() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sessionPath)),
              let s = try? JSONDecoder().decode(AuthSession.self, from: data) else { return }
        if s.expiresAt > Date().timeIntervalSince1970 + 300 {
            session = s
        } else {
            refresh(s.refreshToken)
        }
    }

    private func save() {
        guard let s = session, let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: URL(fileURLWithPath: sessionPath))
    }

    func fetchUser(at: String, rt: String) {
        var r = URLRequest(url: URL(string: "\(baseUrl)/auth/v1/user")!)
        r.setValue("Bearer \(at)", forHTTPHeaderField: "Authorization")
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String,
                  let meta = json["user_metadata"] as? [String: Any],
                  let name = meta["user_name"] as? String else { return }
            let avatar = meta["avatar_url"] as? String
            let exp = self.jwtExp(at) ?? (Date().timeIntervalSince1970 + 3600)
            let s = AuthSession(accessToken: at, refreshToken: rt, userId: id,
                                githubUsername: name, githubAvatar: avatar, expiresAt: exp)
            DispatchQueue.main.async { self.session = s; self.save(); self.onChange?(s) }
        }.resume()
    }

    private func refresh(_ rt: String) {
        var r = URLRequest(url: URL(string: "\(baseUrl)/auth/v1/token?grant_type=refresh_token")!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let at = json["access_token"] as? String,
                  let newRt = json["refresh_token"] as? String else { return }
            DispatchQueue.main.async { self?.fetchUser(at: at, rt: newRt) }
        }.resume()
    }

    private func jwtExp(_ token: String) -> Double? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return exp
    }
}

// MARK: - OAuth callback server（监听 localhost:17778）

final class CallbackServer {
    private var listener: NWListener?
    private var onToken: ((String, String) -> Void)?

    func start(completion: @escaping (String, String) -> Void) {
        onToken = completion
        guard let listener = try? NWListener(using: .tcp, on: 17778) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] c in self?.handle(c) }
        listener.start(queue: .global(qos: .utility))
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: .global(qos: .utility))
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let data, let req = String(data: data, encoding: .utf8) else { return }
            let line = req.components(separatedBy: "\r\n").first ?? ""
            if line.contains("/callback") && !line.contains("/token") {
                // 返回一个页面，JS 从 URL fragment 里提取 token 再 POST 给 /token
                let html = """
                <!doctype html><html><body><p style="font-family:monospace">logging in…</p><script>
                const p=new URLSearchParams(location.hash.slice(1));
                const at=p.get('access_token'),rt=p.get('refresh_token');
                if(at){fetch('/token?at='+encodeURIComponent(at)+'&rt='+encodeURIComponent(rt))
                  .then(()=>{document.body.innerHTML='<h2 style="font-family:monospace">✓ logged in — close this tab</h2>';});}
                else{document.body.innerHTML='<p style="font-family:monospace">error: no token</p>';}
                </script></body></html>
                """
                self?.respond(c, 200, "text/html", html)
            } else if line.contains("/token?") {
                let qs = line.components(separatedBy: "/token?").last?
                    .components(separatedBy: " ").first ?? ""
                let params = qs.components(separatedBy: "&").reduce(into: [String: String]()) {
                    let kv = $1.components(separatedBy: "=")
                    if kv.count == 2 { $0[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
                }
                if let at = params["at"], let rt = params["rt"], !at.isEmpty {
                    self?.respond(c, 200, "text/plain", "ok")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.listener?.cancel()
                        self?.onToken?(at, rt)
                    }
                }
            }
        }
    }

    private func respond(_ c: NWConnection, _ status: Int, _ ct: String, _ body: String) {
        let r = "HTTP/1.1 \(status) OK\r\nContent-Type: \(ct); charset=utf-8\r\n" +
                "Access-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\n" +
                "Connection: close\r\n\r\n\(body)"
        c.send(content: r.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
    }
}
