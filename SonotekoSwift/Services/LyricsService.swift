import Foundation

struct LyricsResult {
    var plainLyrics: String
    var syncedLyrics: String
    var source: String
}

actor LyricsService {
    static let shared = LyricsService()

    func search(artist: String, title: String, album: String = "", duration: Double = 0) async -> LyricsResult? {
        // LRClib
        if let r = await searchLRClib(artist: artist, title: title, album: album, duration: duration) {
            return r
        }
        return nil
    }

    private func searchLRClib(artist: String, title: String, album: String, duration: Double) async -> LyricsResult? {
        var comps = URLComponents(string: "https://lrclib.net/api/search")
        var items: [URLQueryItem] = [
            .init(name: "artist_name", value: artist),
            .init(name: "track_name", value: title)
        ]
        if !album.isEmpty { items.append(.init(name: "album_name", value: album)) }
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Sonoteko/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first else { return nil }
        let plain  = first["plainLyrics"]  as? String ?? ""
        let synced = first["syncedLyrics"] as? String ?? ""
        if plain.isEmpty && synced.isEmpty { return nil }
        return LyricsResult(plainLyrics: plain, syncedLyrics: synced, source: "LRClib")
    }

    func fetchDirect(artist: String, title: String, album: String, duration: Double) async -> LyricsResult? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        comps?.queryItems = [
            .init(name: "artist_name",  value: artist),
            .init(name: "track_name",   value: title),
            .init(name: "album_name",   value: album),
            .init(name: "duration",     value: String(Int(duration)))
        ]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Sonoteko/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let plain  = json["plainLyrics"]  as? String ?? ""
        let synced = json["syncedLyrics"] as? String ?? ""
        if plain.isEmpty && synced.isEmpty { return nil }
        return LyricsResult(plainLyrics: plain, syncedLyrics: synced, source: "LRClib")
    }
}
