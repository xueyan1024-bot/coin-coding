import AppKit

struct LeaderboardEntry: Decodable {
    let githubUsername: String
    let githubAvatar: String?
    let coinName: String
    let coinImageUrl: String?
    let totalCoins: Int
    enum CodingKeys: String, CodingKey {
        case githubUsername = "github_username"
        case githubAvatar   = "github_avatar"
        case coinName       = "coin_name"
        case coinImageUrl   = "coin_image_url"
        case totalCoins     = "total_coins"
    }
}

struct ProfileData: Decodable {
    let totalCoins: Int
    let coinName: String
    let coinImageUrl: String?
    enum CodingKeys: String, CodingKey {
        case totalCoins    = "total_coins"
        case coinName      = "coin_name"
        case coinImageUrl  = "coin_image_url"
    }
}

final class SupabaseAPI {
    static let shared = SupabaseAPI()
    private var auth: SupabaseAuth { .shared }
    private init() {}

    // MARK: - Coins

    func submitCoins(start: Date, end: Date, earned: Int, clicks: [Double],
                     completion: @escaping (Bool) -> Void) {
        guard let token = auth.session?.accessToken, earned > 0 else { completion(false); return }
        var req = make("/functions/v1/submit-coins", "POST", token)
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "session_start": iso(start), "session_end": iso(end),
            "coins_earned": earned,
            "click_timestamps": clicks.map { Int($0 * 1000) }
        ])
        run(req) { _, resp, _ in completion((resp as? HTTPURLResponse)?.statusCode == 200) }
    }

    // MARK: - Profile

    func fetchProfile(completion: @escaping (ProfileData?) -> Void) {
        guard let token = auth.session?.accessToken,
              let uid = auth.session?.userId else { completion(nil); return }
        var req = make("/rest/v1/profiles?id=eq.\(uid)&select=total_coins,coin_name,coin_image_url",
                       "GET", token)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        run(req) { data, _, _ in
            completion(data.flatMap { try? JSONDecoder().decode([ProfileData].self, from: $0) }?.first)
        }
    }

    func updateProfile(coinName: String? = nil, coinImageUrl: String? = nil,
                       completion: ((Bool) -> Void)? = nil) {
        guard let token = auth.session?.accessToken,
              let uid = auth.session?.userId else { return }
        var body: [String: Any] = [:]
        if let n = coinName      { body["coin_name"]      = n }
        if let u = coinImageUrl  { body["coin_image_url"] = u.isEmpty ? NSNull() : u }   // 空串=清除
        guard !body.isEmpty else { return }
        var req = make("/rest/v1/profiles?id=eq.\(uid)", "PATCH", token)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        run(req) { _, resp, _ in completion?((resp as? HTTPURLResponse)?.statusCode == 204) }
    }

    func uploadCoinImage(_ data: Data, completion: @escaping (String?) -> Void) {
        guard let token = auth.session?.accessToken,
              let uid = auth.session?.userId else { completion(nil); return }
        var req = URLRequest(url: URL(string:
            "\(auth.baseUrl)/storage/v1/object/coin-images/\(uid)/coin.png")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(auth.anonKey,       forHTTPHeaderField: "apikey")
        req.setValue("image/png",        forHTTPHeaderField: "Content-Type")
        req.setValue("true",             forHTTPHeaderField: "x-upsert")
        req.httpBody = data
        run(req) { [weak self] _, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { completion(nil); return }
            let url = "\(self?.auth.baseUrl ?? "")/storage/v1/object/public/coin-images/\(uid)/coin.png"
            self?.updateProfile(coinImageUrl: url)
            completion(url)
        }
    }

    // MARK: - Leaderboard

    func fetchLeaderboard(completion: @escaping ([LeaderboardEntry]) -> Void) {
        var req = make(
            "/rest/v1/profiles?select=github_username,github_avatar,coin_name,coin_image_url,total_coins" +
            "&order=total_coins.desc&limit=20&total_coins=gt.0",
            "GET", auth.session?.accessToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        run(req) { data, _, _ in
            completion(data.flatMap {
                try? JSONDecoder().decode([LeaderboardEntry].self, from: $0)
            } ?? [])
        }
    }

    // 自己的真实名次：数一下比我分高的有几个人，名次 = 那个数 + 1
    func fetchMyRank(completion: @escaping (Int?) -> Void) {
        guard let token = auth.session?.accessToken else { completion(nil); return }
        fetchProfile { [weak self] profile in
            guard let self, let p = profile, p.totalCoins > 0 else { completion(nil); return }
            var req = self.make("/rest/v1/profiles?select=id&total_coins=gt.\(p.totalCoins)", "GET", token)
            req.setValue("count=exact", forHTTPHeaderField: "Prefer")
            req.setValue("0-0", forHTTPHeaderField: "Range")
            self.run(req) { _, resp, _ in
                guard let http = resp as? HTTPURLResponse,
                      let cr = http.value(forHTTPHeaderField: "Content-Range"),
                      let total = cr.components(separatedBy: "/").last,
                      let n = Int(total) else { completion(nil); return }
                completion(n + 1)
            }
        }
    }

    // MARK: - Helpers

    private func make(_ path: String, _ method: String, _ token: String?) -> URLRequest {
        var r = URLRequest(url: URL(string: "\(auth.baseUrl)\(path)")!)
        r.httpMethod = method
        r.setValue(auth.anonKey,        forHTTPHeaderField: "apikey")
        r.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func run(_ req: URLRequest,
                     completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        URLSession.shared.dataTask(with: req) { d, r, e in
            DispatchQueue.main.async { completion(d, r, e) }
        }.resume()
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
