import Foundation

struct MBRelease: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var date: String
    var tracks: [MBTrack]
    var country: String
    var label: String
    var coverURL: String?
}

struct MBTrack: Identifiable, Hashable {
    var id: String
    var number: String
    var title: String
    var length: Int
    var artist: String
}

actor MusicBrainzService {
    static let shared = MusicBrainzService()
    private let baseURL = "https://musicbrainz.org/ws/2"
    private let coverArtURL = "https://coverartarchive.org/release"
    private var lastRequest: Date = .distantPast
    private let rateLimit: TimeInterval = 1.0

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < rateLimit {
            try? await Task.sleep(nanoseconds: UInt64((rateLimit - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()
    }

    func searchRelease(artist: String, album: String) async -> [MBRelease] {
        await throttle()
        let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(baseURL)/release/?query=\(q)&fmt=json&limit=10") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Sonoteko/1.0 (music library app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releases = json["releases"] as? [[String: Any]] else { return [] }
        return releases.compactMap { parseRelease($0) }
    }

    func searchRecording(artist: String, title: String) async -> [MBRelease] {
        await throttle()
        let q = "artist:\(artist) AND recording:\(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(baseURL)/recording/?query=\(q)&fmt=json&limit=10&inc=releases") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Sonoteko/1.0 (music library app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordings = json["recordings"] as? [[String: Any]] else { return [] }
        var results: [MBRelease] = []
        for rec in recordings {
            let releases = (rec["releases"] as? [[String: Any]]) ?? []
            results += releases.compactMap { parseRelease($0) }
        }
        return results
    }

    func fetchRelease(mbid: String) async -> MBRelease? {
        await throttle()
        guard let url = URL(string: "\(baseURL)/release/\(mbid)?inc=recordings+artists+labels&fmt=json") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Sonoteko/1.0 (music library app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseRelease(json)
    }

    func fetchCoverArt(mbid: String) async -> Data? {
        guard let url = URL(string: "\(coverArtURL)/\(mbid)/front") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func parseRelease(_ j: [String: Any]) -> MBRelease? {
        guard let id = j["id"] as? String, let title = j["title"] as? String else { return nil }
        let artist: String
        if let ac = j["artist-credit"] as? [[String: Any]], let first = ac.first,
           let a = first["artist"] as? [String: Any], let n = a["name"] as? String {
            artist = n
        } else { artist = "" }
        let date = j["date"] as? String ?? ""
        let country = j["country"] as? String ?? ""
        var label = ""
        if let li = (j["label-info"] as? [[String: Any]])?.first,
           let l = li["label"] as? [String: Any], let ln = l["name"] as? String { label = ln }
        var tracks: [MBTrack] = []
        if let media = j["media"] as? [[String: Any]] {
            for (di, disc) in media.enumerated() {
                let discNum = di + 1
                for t in (disc["tracks"] as? [[String: Any]]) ?? [] {
                    let tid = t["id"] as? String ?? UUID().uuidString
                    let tnum = t["number"] as? String ?? "\(discNum)-\(tracks.count+1)"
                    let ttitle = t["title"] as? String ?? ""
                    let tlen = t["length"] as? Int ?? 0
                    var tartist = ""
                    if let ac = t["artist-credit"] as? [[String: Any]], let f = ac.first,
                       let a = f["artist"] as? [String: Any], let n = a["name"] as? String { tartist = n }
                    tracks.append(MBTrack(id: tid, number: tnum, title: ttitle, length: tlen, artist: tartist))
                }
            }
        }
        return MBRelease(id: id, title: title, artist: artist, date: date, tracks: tracks, country: country, label: label)
    }
}
