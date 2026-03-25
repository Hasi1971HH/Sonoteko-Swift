import Foundation

actor ScanService {
    static let shared = ScanService()
    static let audioExtensions: Set<String> = ["mp3","flac","ogg","m4a","aac","wav","aiff","opus"]

    func scanDirectory(_ path: String) -> [String] {
        var results: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if ScanService.audioExtensions.contains(url.pathExtension.lowercased()) {
                results.append(url.path)
            }
        }
        return results
    }

    func scanAndImport(paths: [String], db: LibraryDatabase, progress: @escaping (Int, Int) -> Void) async {
        var allFiles: [String] = []
        for path in paths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {
                    allFiles.append(contentsOf: await scanDirectory(path))
                } else if ScanService.audioExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
                    allFiles.append(path)
                }
            }
        }
        let total = allFiles.count
        for (i, file) in allFiles.enumerated() {
            let tags = await TagHandler.shared.readTags(at: file)
            let attrs = try? FileManager.default.attributesOfItem(atPath: file)
            let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            var r = TrackRecord(path: file)
            r.title = tags.title; r.artist = tags.artist; r.album = tags.album
            r.albumartist = tags.albumartist; r.year = tags.date; r.genre = tags.genre
            r.tracknumber = tags.tracknumber; r.discnumber = tags.discnumber
            r.composer = tags.composer; r.comment = tags.comment; r.bpm = tags.bpm
            r.isrc = tags.isrc; r.duration = tags.duration; r.bitrate = tags.bitrate
            r.samplerate = tags.samplerate; r.channels = tags.channels
            r.format = URL(fileURLWithPath: file).pathExtension.uppercased()
            r.filesize = tags.filesize; r.hasCover = tags.coverData != nil
            r.replaygainTrackGain = tags.replaygainTrackGain
            r.replaygainTrackPeak = tags.replaygainTrackPeak
            r.replaygainAlbumGain = tags.replaygainAlbumGain
            r.replaygainAlbumPeak = tags.replaygainAlbumPeak
            r.dateModified = modDate
            db.upsertTrack(r)
            progress(i + 1, total)
        }
    }
}
