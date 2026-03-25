import Foundation

struct TrackRecord: Identifiable, Hashable, Equatable {
    var id: String { path }

    var path: String
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var albumartist: String = ""
    var year: String = ""
    var genre: String = ""
    var tracknumber: String = ""
    var discnumber: String = ""
    var composer: String = ""
    var comment: String = ""
    var bpm: String = ""
    var isrc: String = ""
    var duration: Double = 0
    var bitrate: Int = 0
    var samplerate: Int = 0
    var channels: Int = 0
    var format: String = ""
    var filesize: Int = 0
    var hasCover: Bool = false
    var replaygainTrackGain: String = ""
    var replaygainTrackPeak: String = ""
    var replaygainAlbumGain: String = ""
    var replaygainAlbumPeak: String = ""
    var dateAdded: Double = Date().timeIntervalSince1970
    var dateModified: Double = 0
    var playCount: Int = 0
    var rating: Int = 0

    var formattedDuration: String {
        let s = Int(duration)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    var filename: String { URL(fileURLWithPath: path).lastPathComponent }
    var fileExtension: String { URL(fileURLWithPath: path).pathExtension.uppercased() }
}

struct AudioTags {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var albumartist: String = ""
    var date: String = ""
    var genre: String = ""
    var tracknumber: String = ""
    var discnumber: String = ""
    var composer: String = ""
    var comment: String = ""
    var bpm: String = ""
    var publisher: String = ""
    var copyright: String = ""
    var encoder: String = ""
    var isrc: String = ""
    var key: String = ""
    var mood: String = ""
    var lyricist: String = ""
    var originalartist: String = ""
    var subtitle: String = ""
    var originaldate: String = ""
    var media: String = ""
    var lyrics: String = ""
    var replaygainTrackGain: String = ""
    var replaygainTrackPeak: String = ""
    var replaygainAlbumGain: String = ""
    var replaygainAlbumPeak: String = ""
    var coverData: Data? = nil
    var coverMime: String = "image/jpeg"
    var duration: Double = 0
    var bitrate: Int = 0
    var samplerate: Int = 0
    var channels: Int = 0
    var format: String = ""
    var filesize: Int = 0
}

struct Playlist: Identifiable {
    var id: Int
    var name: String
    var description: String = ""
    var createdAt: Double = Date().timeIntervalSince1970
    var updatedAt: Double = Date().timeIntervalSince1970
}
