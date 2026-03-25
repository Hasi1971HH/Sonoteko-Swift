import Foundation
import AVFoundation
import CoreMedia

enum TagError: LocalizedError {
    case unsupportedFormat(String), fileNotFound, writeError(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let e): return "Format nicht unterstützt: \(e)"
        case .fileNotFound: return "Datei nicht gefunden"
        case .writeError(let m): return "Schreibfehler: \(m)"
        }
    }
}

actor TagHandler {
    static let shared = TagHandler()
    static let supportedExtensions: Set<String> = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff"]

    // MARK: - Read

    func readTags(at path: String) async -> AudioTags {
        var tags = AudioTags()
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard FileManager.default.fileExists(atPath: path) else { return tags }
        tags.format = ext.uppercased()
        tags.filesize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        switch ext {
        case "mp3":   readID3(path: path, into: &tags)
        case "flac":  readFLAC(path: path, into: &tags)
        case "ogg":   readOGG(path: path, into: &tags)
        default:      await readAVF(url: url, into: &tags)
        }
        await enrichAV(url: url, into: &tags)
        return tags
    }

    // MARK: - Write

    func writeTags(at path: String, tags: AudioTags) throws {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "mp3":  try writeID3(path: path, tags: tags)
        case "flac": try writeFLAC(path: path, tags: tags)
        case "ogg":  try writeOGG(path: path, tags: tags)
        default:     try writeViaFFmpeg(path: path, tags: tags)
        }
    }

    // MARK: - AVFoundation helpers

    private func enrichAV(url: URL, into tags: inout AudioTags) async {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        if let d = try? await asset.load(.duration), !d.seconds.isNaN, d.seconds > 0 {
            tags.duration = d.seconds
        }
        if let avTracks = try? await asset.load(.tracks) {
            for t in avTracks where t.mediaType == .audio {
                if let r = try? await t.load(.estimatedDataRate), r > 0 { tags.bitrate = Int(r / 1000) }
                if let descs = try? await t.load(.formatDescriptions), let desc = descs.first {
                    if let bd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                        if tags.samplerate == 0 { tags.samplerate = Int(bd.mSampleRate) }
                        if tags.channels == 0   { tags.channels   = Int(bd.mChannelsPerFrame) }
                    }
                }
            }
        }
    }

    private func readAVF(url: URL, into tags: inout AudioTags) async {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return }
        for item in metadata {
            guard let key = item.commonKey, let val = try? await item.load(.value) else { continue }
            switch key {
            case .commonKeyTitle:     tags.title  = val as? String ?? ""
            case .commonKeyArtist:    tags.artist = val as? String ?? ""
            case .commonKeyAlbumName: tags.album  = val as? String ?? ""
            case .commonKeyArtwork:   tags.coverData = val as? Data
            default: break
            }
        }
    }

    // MARK: - ID3v2 Reader

    private func readID3(path: String, into tags: inout AudioTags) {
        guard let data = FileManager.default.contents(atPath: path), data.count > 10 else { return }
        guard data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { return }
        let version = data[3]
        let tagSize = synchsafeInt(data, 6)
        var off = 10
        let end = min(10 + tagSize, data.count)
        while off < end - 10 {
            let fid = String(bytes: data[off..<off+4], encoding: .isoLatin1) ?? ""
            if fid.trimmingCharacters(in: .init(charactersIn: "\0")).isEmpty { break }
            let fsz = version >= 4 ? synchsafeInt(data, off+4) : beInt(data, off+4)
            let ds = off + 10, de = min(ds + fsz, data.count)
            guard fsz > 0, de > ds, de <= data.count else { off += 10 + fsz; continue }
            let fd = data[ds..<de]
            switch fid {
            case "TIT2": tags.title        = id3Text(fd)
            case "TPE1": tags.artist       = id3Text(fd)
            case "TALB": tags.album        = id3Text(fd)
            case "TPE2": tags.albumartist  = id3Text(fd)
            case "TDRC","TYER": tags.date  = id3Text(fd)
            case "TCON": tags.genre        = id3Genre(id3Text(fd))
            case "TRCK": tags.tracknumber  = id3Text(fd)
            case "TPOS": tags.discnumber   = id3Text(fd)
            case "TCOM": tags.composer     = id3Text(fd)
            case "TBPM": tags.bpm          = id3Text(fd)
            case "TSRC": tags.isrc         = id3Text(fd)
            case "TPUB": tags.publisher    = id3Text(fd)
            case "TCOP": tags.copyright    = id3Text(fd)
            case "TENC": tags.encoder      = id3Text(fd)
            case "TIT3": tags.subtitle     = id3Text(fd)
            case "TKEY": tags.key          = id3Text(fd)
            case "TMOO": tags.mood         = id3Text(fd)
            case "TEXT": tags.lyricist     = id3Text(fd)
            case "TOPE": tags.originalartist = id3Text(fd)
            case "TDOR": tags.originaldate = id3Text(fd)
            case "TMED": tags.media        = id3Text(fd)
            case "COMM": if fd.count > 4 { tags.comment = id3Text(Data(fd.dropFirst(4))) }
            case "USLT": if fd.count > 4 { tags.lyrics  = id3Text(Data(fd.dropFirst(4))) }
            case "APIC": tags.coverData   = parseAPIC(fd)
            case "TXXX":
                let (k, v) = parseTXXX(fd)
                switch k.lowercased() {
                case "replaygain_track_gain": tags.replaygainTrackGain = v
                case "replaygain_track_peak": tags.replaygainTrackPeak = v
                case "replaygain_album_gain": tags.replaygainAlbumGain = v
                case "replaygain_album_peak": tags.replaygainAlbumPeak = v
                default: break
                }
            default: break
            }
            off += 10 + fsz
        }
    }

    // MARK: - FLAC Reader

    private func readFLAC(path: String, into tags: inout AudioTags) {
        guard let data = FileManager.default.contents(atPath: path), data.count > 42 else { return }
        guard data[0]==0x66,data[1]==0x4C,data[2]==0x61,data[3]==0x43 else { return }
        var off = 4, last = false
        while !last, off + 4 <= data.count {
            let hdr = data[off]; last = (hdr & 0x80) != 0
            let btype = hdr & 0x7F
            let bsz = Int(data[off+1])<<16 | Int(data[off+2])<<8 | Int(data[off+3])
            off += 4
            guard off + bsz <= data.count else { break }
            let slice = data[off..<off+bsz]
            switch btype {
            case 0:
                if bsz >= 18 {
                    let sr = (Int(slice[slice.startIndex+10])<<12) | (Int(slice[slice.startIndex+11])<<4) | (Int(slice[slice.startIndex+12])>>4)
                    tags.samplerate = sr
                    tags.channels   = ((Int(slice[slice.startIndex+12]) >> 1) & 0x07) + 1
                    let si = slice.startIndex
                    let ts = (Int64(slice[si+13] & 0x0F)<<32) | (Int64(slice[si+14])<<24) | (Int64(slice[si+15])<<16) | (Int64(slice[si+16])<<8) | Int64(slice[si+17])
                    if sr > 0, ts > 0 { tags.duration = Double(ts) / Double(sr) }
                }
            case 4: parseVorbisBlock(slice, into: &tags)
            case 6: tags.coverData = parseFLACPic(slice)
            default: break
            }
            off += bsz
        }
        if tags.bitrate == 0, tags.duration > 0, tags.filesize > 0 {
            tags.bitrate = Int(Double(tags.filesize * 8) / tags.duration / 1000)
        }
    }

    // MARK: - OGG Reader

    private func readOGG(path: String, into tags: inout AudioTags) {
        guard let data = FileManager.default.contents(atPath: path), data.count > 200 else { return }
        let marker: [UInt8] = [0x03,0x76,0x6F,0x72,0x62,0x69,0x73]
        for i in 0..<(data.count - 50) {
            if data[i] == 0x03 {
                let slice = data[i..<min(i+7, data.count)]
                if Array(slice) == marker {
                    parseVorbisBlock(data[(i+7)...], into: &tags); break
                }
            }
        }
    }

    // MARK: - Vorbis Comment parser

    private func parseVorbisBlock(_ data: some DataProtocol, into tags: inout AudioTags) {
        let d = Data(data)
        var off = 0
        guard off + 4 <= d.count else { return }
        let vlen = leInt(d, off); off += 4 + vlen
        guard off + 4 <= d.count else { return }
        let count = leInt(d, off); off += 4
        for _ in 0..<count {
            guard off + 4 <= d.count else { break }
            let len = leInt(d, off); off += 4
            guard off + len <= d.count else { break }
            if let s = String(data: d[off..<off+len], encoding: .utf8) { applyVorbis(s, to: &tags) }
            off += len
        }
    }

    private func applyVorbis(_ s: String, to tags: inout AudioTags) {
        let parts = s.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return }
        let k = String(parts[0]).uppercased(), v = String(parts[1])
        switch k {
        case "TITLE":             tags.title = v
        case "ARTIST":            tags.artist = v
        case "ALBUM":             tags.album = v
        case "ALBUMARTIST":       tags.albumartist = v
        case "DATE","YEAR":       tags.date = v
        case "GENRE":             tags.genre = v
        case "TRACKNUMBER":       tags.tracknumber = v
        case "DISCNUMBER":        tags.discnumber = v
        case "COMPOSER":          tags.composer = v
        case "COMMENT":           tags.comment = v
        case "BPM":               tags.bpm = v
        case "ISRC":              tags.isrc = v
        case "PUBLISHER":         tags.publisher = v
        case "COPYRIGHT":         tags.copyright = v
        case "SUBTITLE":          tags.subtitle = v
        case "INITIALKEY":        tags.key = v
        case "MOOD":              tags.mood = v
        case "LYRICIST":          tags.lyricist = v
        case "ORIGINALARTIST":    tags.originalartist = v
        case "ORIGINALDATE":      tags.originaldate = v
        case "MEDIA":             tags.media = v
        case "LYRICS","UNSYNCEDLYRICS": tags.lyrics = v
        case "REPLAYGAIN_TRACK_GAIN": tags.replaygainTrackGain = v
        case "REPLAYGAIN_TRACK_PEAK": tags.replaygainTrackPeak = v
        case "REPLAYGAIN_ALBUM_GAIN": tags.replaygainAlbumGain = v
        case "REPLAYGAIN_ALBUM_PEAK": tags.replaygainAlbumPeak = v
        default: break
        }
    }

    // MARK: - ID3v2 Writer

    private func writeID3(path: String, tags: AudioTags) throws {
        guard var data = FileManager.default.contents(atPath: path) else { throw TagError.fileNotFound }
        var audioStart = 0
        if data.count > 10, data[0]==0x49, data[1]==0x44, data[2]==0x33 {
            audioStart = 10 + synchsafeInt(data, 6)
        }
        var frames = Data()
        func txt(_ id: String, _ val: String) {
            guard !val.isEmpty, let enc = val.data(using: .utf8) else { return }
            var fd = Data([0x03]); fd.append(enc)
            frames.append(contentsOf: id.utf8)
            let sz = fd.count
            frames.append(contentsOf: [UInt8((sz>>24)&0xFF),UInt8((sz>>16)&0xFF),UInt8((sz>>8)&0xFF),UInt8(sz&0xFF),0,0])
            frames.append(fd)
        }
        txt("TIT2",tags.title); txt("TPE1",tags.artist); txt("TALB",tags.album)
        txt("TPE2",tags.albumartist); txt("TDRC",tags.date); txt("TCON",tags.genre)
        txt("TRCK",tags.tracknumber); txt("TPOS",tags.discnumber); txt("TCOM",tags.composer)
        txt("TBPM",tags.bpm); txt("TSRC",tags.isrc); txt("TPUB",tags.publisher)
        txt("TCOP",tags.copyright); txt("TENC",tags.encoder); txt("TIT3",tags.subtitle)
        txt("TKEY",tags.key); txt("TMOO",tags.mood); txt("TEXT",tags.lyricist)
        txt("TOPE",tags.originalartist); txt("TDOR",tags.originaldate); txt("TMED",tags.media)
        func comm(_ id: String, _ val: String) {
            guard !val.isEmpty else { return }
            var fd = Data([0x03,0x65,0x6E,0x67,0x00])
            fd.append(contentsOf: val.utf8)
            frames.append(contentsOf: id.utf8)
            let sz = fd.count
            frames.append(contentsOf: [UInt8((sz>>24)&0xFF),UInt8((sz>>16)&0xFF),UInt8((sz>>8)&0xFF),UInt8(sz&0xFF),0,0])
            frames.append(fd)
        }
        comm("COMM", tags.comment); comm("USLT", tags.lyrics)
        func txxx(_ desc: String, _ val: String) {
            guard !val.isEmpty else { return }
            var fd = Data([0x03]); fd.append(contentsOf: desc.utf8); fd.append(0)
            fd.append(contentsOf: val.utf8)
            frames.append(contentsOf: "TXXX".utf8)
            let sz = fd.count
            frames.append(contentsOf: [UInt8((sz>>24)&0xFF),UInt8((sz>>16)&0xFF),UInt8((sz>>8)&0xFF),UInt8(sz&0xFF),0,0])
            frames.append(fd)
        }
        txxx("REPLAYGAIN_TRACK_GAIN",tags.replaygainTrackGain)
        txxx("REPLAYGAIN_TRACK_PEAK",tags.replaygainTrackPeak)
        txxx("REPLAYGAIN_ALBUM_GAIN",tags.replaygainAlbumGain)
        txxx("REPLAYGAIN_ALBUM_PEAK",tags.replaygainAlbumPeak)
        if let cd = tags.coverData, !cd.isEmpty {
            let mime = tags.coverMime.isEmpty ? "image/jpeg" : tags.coverMime
            var fd = Data([0x00]); fd.append(contentsOf: mime.utf8); fd.append(0); fd.append(0x03); fd.append(0)
            fd.append(cd)
            frames.append(contentsOf: "APIC".utf8)
            let sz = fd.count
            frames.append(contentsOf: [UInt8((sz>>24)&0xFF),UInt8((sz>>16)&0xFF),UInt8((sz>>8)&0xFF),UInt8(sz&0xFF),0,0])
            frames.append(fd)
        }
        let pad = Data(repeating: 0, count: 2048)
        let total = frames.count + pad.count
        var hdr = Data([0x49,0x44,0x33,0x03,0x00,0x00])
        hdr.append(contentsOf: synchsafeBytes(total))
        var out = hdr; out.append(frames); out.append(pad)
        if audioStart < data.count { out.append(data[audioStart...]) }
        try out.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - FLAC Writer

    private func writeFLAC(path: String, tags: AudioTags) throws {
        guard var data = FileManager.default.contents(atPath: path) else { throw TagError.fileNotFound }
        guard data.count > 42, data[0]==0x66,data[1]==0x4C,data[2]==0x61,data[3]==0x43 else {
            throw TagError.writeError("Keine gültige FLAC-Datei")
        }
        struct Block { var type: UInt8; var data: Data }
        var blocks: [Block] = []; var off = 4; var last = false; var audioOff = 0
        while !last, off + 4 <= data.count {
            let hdr = data[off]; last = (hdr & 0x80) != 0
            let btype = hdr & 0x7F
            let bsz = Int(data[off+1])<<16 | Int(data[off+2])<<8 | Int(data[off+3])
            off += 4
            guard off + bsz <= data.count else { break }
            blocks.append(Block(type: btype, data: Data(data[off..<off+bsz])))
            off += bsz
            if last { audioOff = off }
        }
        var vc = Data()
        func le32(_ n: Int) { vc.append(contentsOf: [UInt8(n&0xFF),UInt8((n>>8)&0xFF),UInt8((n>>16)&0xFF),UInt8((n>>24)&0xFF)]) }
        let vendor = "Sonoteko 1.0".data(using: .utf8)!
        le32(vendor.count); vc.append(vendor)
        var comments: [String] = []
        func add(_ k: String, _ v: String) { if !v.isEmpty { comments.append("\(k)=\(v)") } }
        add("TITLE",tags.title); add("ARTIST",tags.artist); add("ALBUM",tags.album)
        add("ALBUMARTIST",tags.albumartist); add("DATE",tags.date); add("GENRE",tags.genre)
        add("TRACKNUMBER",tags.tracknumber); add("DISCNUMBER",tags.discnumber)
        add("COMPOSER",tags.composer); add("COMMENT",tags.comment); add("BPM",tags.bpm)
        add("ISRC",tags.isrc); add("PUBLISHER",tags.publisher); add("COPYRIGHT",tags.copyright)
        add("SUBTITLE",tags.subtitle); add("INITIALKEY",tags.key); add("MOOD",tags.mood)
        add("LYRICIST",tags.lyricist); add("ORIGINALARTIST",tags.originalartist)
        add("ORIGINALDATE",tags.originaldate); add("MEDIA",tags.media); add("LYRICS",tags.lyrics)
        add("REPLAYGAIN_TRACK_GAIN",tags.replaygainTrackGain)
        add("REPLAYGAIN_TRACK_PEAK",tags.replaygainTrackPeak)
        add("REPLAYGAIN_ALBUM_GAIN",tags.replaygainAlbumGain)
        add("REPLAYGAIN_ALBUM_PEAK",tags.replaygainAlbumPeak)
        le32(comments.count)
        for c in comments { let cd = c.data(using: .utf8)!; le32(cd.count); vc.append(cd) }
        var newBlocks = blocks.filter { $0.type != 4 && $0.type != 6 }
        newBlocks.append(Block(type: 4, data: vc))
        if let cd = tags.coverData, !cd.isEmpty {
            newBlocks.append(Block(type: 6, data: buildFLACPic(cd, mime: tags.coverMime)))
        }
        var out = Data([0x66,0x4C,0x61,0x43])
        for (i, b) in newBlocks.enumerated() {
            var t = b.type; if i == newBlocks.count-1 { t |= 0x80 }
            out.append(t)
            let sz = b.data.count
            out.append(contentsOf: [UInt8((sz>>16)&0xFF),UInt8((sz>>8)&0xFF),UInt8(sz&0xFF)])
            out.append(b.data)
        }
        if audioOff < data.count { out.append(data[audioOff...]) }
        try out.write(to: URL(fileURLWithPath: path))
    }

    private func buildFLACPic(_ img: Data, mime: String) -> Data {
        let m = mime.isEmpty ? "image/jpeg" : mime
        var d = Data()
        func be32(_ n: Int) { d.append(contentsOf: [UInt8((n>>24)&0xFF),UInt8((n>>16)&0xFF),UInt8((n>>8)&0xFF),UInt8(n&0xFF)]) }
        be32(3); let md = m.data(using: .utf8)!; be32(md.count); d.append(md)
        be32(0); be32(0); be32(0); be32(0); be32(0); be32(img.count); d.append(img)
        return d
    }

    private func writeOGG(path: String, tags: AudioTags) throws {
        try writeViaFFmpeg(path: path, tags: tags)
    }

    // MARK: - ffmpeg fallback

    private func writeViaFFmpeg(path: String, tags: AudioTags) throws {
        let tmp = path + ".snktmp"
        var args = ["-i", path, "-y"]
        func m(_ k: String, _ v: String) { if !v.isEmpty { args += ["-metadata", "\(k)=\(v)"] } }
        m("title",tags.title); m("artist",tags.artist); m("album",tags.album)
        m("album_artist",tags.albumartist); m("date",tags.date); m("genre",tags.genre)
        m("track",tags.tracknumber); m("disc",tags.discnumber); m("composer",tags.composer)
        m("comment",tags.comment); m("bpm",tags.bpm); m("isrc",tags.isrc)
        m("REPLAYGAIN_TRACK_GAIN",tags.replaygainTrackGain)
        m("REPLAYGAIN_TRACK_PEAK",tags.replaygainTrackPeak)
        m("REPLAYGAIN_ALBUM_GAIN",tags.replaygainAlbumGain)
        m("REPLAYGAIN_ALBUM_PEAK",tags.replaygainAlbumPeak)
        args += ["-c","copy",tmp]
        let (code, _, err) = runProc("ffmpeg", args)
        if code == 0 {
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        } else {
            try? FileManager.default.removeItem(atPath: tmp)
            throw TagError.writeError(err)
        }
    }

    // MARK: - File rename

    func renameFile(at path: String, template: String, tags: AudioTags) throws -> String {
        let url = URL(fileURLWithPath: path)
        var name = template
            .replacingOccurrences(of: "%title%",      with: tags.title)
            .replacingOccurrences(of: "%artist%",     with: tags.artist)
            .replacingOccurrences(of: "%album%",      with: tags.album)
            .replacingOccurrences(of: "%year%",       with: tags.date)
            .replacingOccurrences(of: "%genre%",      with: tags.genre)
            .replacingOccurrences(of: "%track%",      with: tags.tracknumber)
            .replacingOccurrences(of: "%disc%",       with: tags.discnumber)
            .replacingOccurrences(of: "%albumartist%",with: tags.albumartist)
        name = name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "_")
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return path }
        let newPath = url.deletingLastPathComponent().appendingPathComponent(name + "." + url.pathExtension).path
        if newPath == path { return path }
        try FileManager.default.moveItem(atPath: path, toPath: newPath)
        return newPath
    }

    // MARK: - Binary helpers

    private func synchsafeInt(_ d: Data, _ off: Int) -> Int {
        Int(d[off])<<21 | Int(d[off+1])<<14 | Int(d[off+2])<<7 | Int(d[off+3])
    }
    private func beInt(_ d: Data, _ off: Int) -> Int {
        Int(d[off])<<24 | Int(d[off+1])<<16 | Int(d[off+2])<<8 | Int(d[off+3])
    }
    private func leInt(_ d: Data, _ off: Int) -> Int {
        Int(d[off]) | Int(d[off+1])<<8 | Int(d[off+2])<<16 | Int(d[off+3])<<24
    }
    private func synchsafeBytes(_ n: Int) -> [UInt8] {
        [UInt8((n>>21)&0x7F),UInt8((n>>14)&0x7F),UInt8((n>>7)&0x7F),UInt8(n&0x7F)]
    }

    private func id3Text(_ d: Data) -> String {
        guard !d.isEmpty else { return "" }
        let enc = d[0]; let rest = d.dropFirst()
        var clean = Data(rest)
        switch enc {
        case 0: return String(bytes: clean, encoding: .isoLatin1)?.trimmingCharacters(in: .controlCharacters) ?? ""
        case 1:
            while clean.count >= 2, clean.suffix(2) == Data([0,0]) { clean = clean.dropLast(2) }
            return String(data: clean, encoding: .utf16)?.trimmingCharacters(in: .controlCharacters) ?? ""
        case 3:
            while clean.last == 0 { clean = clean.dropLast() }
            return String(data: clean, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        default:
            while clean.last == 0 { clean = clean.dropLast() }
            return String(data: clean, encoding: .utf8) ?? ""
        }
    }

    private func id3Genre(_ raw: String) -> String {
        if raw.hasPrefix("("), let end = raw.firstIndex(of: ")") {
            let n = String(raw[raw.index(after: raw.startIndex)..<end])
            if let i = Int(n), i < id3Genres.count { return id3Genres[i] }
        }
        if let i = Int(raw), i < id3Genres.count { return id3Genres[i] }
        return raw
    }

    private func parseAPIC(_ d: Data) -> Data? {
        guard d.count > 5 else { return nil }
        let enc = d[0]; var off = 1
        while off < d.count, d[off] != 0 { off += 1 }; off += 1
        off += 1 // picture type
        if enc == 1 || enc == 2 {
            while off + 1 < d.count, !(d[off] == 0 && d[off+1] == 0) { off += 2 }; off += 2
        } else {
            while off < d.count, d[off] != 0 { off += 1 }; off += 1
        }
        guard off < d.count else { return nil }
        return Data(d[off...])
    }

    private func parseTXXX(_ d: Data) -> (String, String) {
        guard d.count > 1 else { return ("","") }
        let rest = d.dropFirst()
        if let sep = rest.firstIndex(of: 0) {
            let desc = id3Text(Data([d[0]]) + Data(rest[rest.startIndex..<sep]))
            let val  = id3Text(Data([d[0]]) + Data(rest[rest.index(after: sep)...]))
            return (desc, val)
        }
        return ("", id3Text(d))
    }

    private func parseFLACPic(_ d: Data.SubSequence) -> Data? {
        let data = Data(d)
        guard data.count > 32 else { return nil }
        var off = 4
        let mlen = beInt(data, off); off += 4 + mlen
        guard off + 4 <= data.count else { return nil }
        let dlen = beInt(data, off); off += 4 + dlen
        guard off + 20 <= data.count else { return nil }
        off += 16
        let ilen = beInt(data, off); off += 4
        guard off + ilen <= data.count else { return nil }
        return Data(data[off..<off+ilen])
    }

    private func runProc(_ exe: String, _ args: [String]) -> (Int32, String, String) {
        let task = Process()
        let out = Pipe(), err = Pipe()
        let paths = ["/opt/homebrew/bin/","/usr/local/bin/","/usr/bin/"]
        for p in paths {
            if FileManager.default.fileExists(atPath: p+exe) {
                task.executableURL = URL(fileURLWithPath: p+exe); break
            }
        }
        if task.executableURL == nil {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = [exe] + args
        } else { task.arguments = args }
        task.standardOutput = out; task.standardError = err
        try? task.run(); task.waitUntilExit()
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (task.terminationStatus, o, e)
    }

    private let id3Genres = ["Blues","Classic Rock","Country","Dance","Disco","Funk","Grunge","Hip-Hop","Jazz","Metal","New Age","Oldies","Other","Pop","R&B","Rap","Reggae","Rock","Techno","Industrial","Alternative","Ska","Death Metal","Pranks","Soundtrack","Euro-Techno","Ambient","Trip-Hop","Vocal","Jazz+Funk","Fusion","Trance","Classical","Instrumental","Acid","House","Game","Sound Clip","Gospel","Noise","AlternRock","Bass","Soul","Punk","Space","Meditative","Instrumental Pop","Instrumental Rock","Ethnic","Gothic","Darkwave","Techno-Industrial","Electronic","Pop-Folk","Eurodance","Dream","Southern Rock","Comedy","Cult","Gangsta Rap","Top 40","Christian Rap","Pop/Funk","Jungle","Native US","Cabaret","New Wave","Psychadelic","Rave","Showtunes","Trailer","Lo-Fi","Tribal","Acid Punk","Acid Jazz","Polka","Retro","Musical","Rock & Roll","Hard Rock"]
}
