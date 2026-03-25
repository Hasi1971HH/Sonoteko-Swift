import Foundation
import SQLite3

// SQLITE_TRANSIENT is a C macro not imported by Swift
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class LibraryDatabase {
    private var db: OpaquePointer?
    let dbPath: String

    static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = (home as NSString).appendingPathComponent(".sonoteko")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("library.db")
    }()

    init(path: String = LibraryDatabase.defaultPath) {
        self.dbPath = path
        openDatabase()
        createTables()
    }

    deinit { close() }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[DB] Cannot open: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    func close() {
        if let db = db { sqlite3_close(db); self.db = nil }
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<Int8>? = nil
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let e = err { print("[DB] \(String(cString: e))"); sqlite3_free(err) }
        }
    }

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS tracks (
                path TEXT PRIMARY KEY, title TEXT DEFAULT '', artist TEXT DEFAULT '',
                album TEXT DEFAULT '', albumartist TEXT DEFAULT '', year TEXT DEFAULT '',
                genre TEXT DEFAULT '', tracknumber TEXT DEFAULT '', discnumber TEXT DEFAULT '',
                composer TEXT DEFAULT '', comment TEXT DEFAULT '', bpm TEXT DEFAULT '',
                isrc TEXT DEFAULT '', duration REAL DEFAULT 0, bitrate INTEGER DEFAULT 0,
                samplerate INTEGER DEFAULT 0, channels INTEGER DEFAULT 0,
                format TEXT DEFAULT '', filesize INTEGER DEFAULT 0, has_cover INTEGER DEFAULT 0,
                replaygain_track_gain TEXT DEFAULT '', replaygain_track_peak TEXT DEFAULT '',
                replaygain_album_gain TEXT DEFAULT '', replaygain_album_peak TEXT DEFAULT '',
                date_added REAL DEFAULT 0, date_modified REAL DEFAULT 0,
                play_count INTEGER DEFAULT 0, rating INTEGER DEFAULT 0
            );
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS playlists (
                id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                description TEXT DEFAULT '', created_at REAL DEFAULT 0, updated_at REAL DEFAULT 0
            );
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS playlist_tracks (
                playlist_id INTEGER NOT NULL, track_path TEXT NOT NULL, position INTEGER NOT NULL,
                PRIMARY KEY (playlist_id, track_path)
            );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_artist ON tracks(artist);")
        exec("CREATE INDEX IF NOT EXISTS idx_album ON tracks(album);")
    }

    // MARK: - Upsert

    func upsertTrack(_ r: TrackRecord) {
        let sql = """
            INSERT INTO tracks (
                path,title,artist,album,albumartist,year,genre,tracknumber,discnumber,
                composer,comment,bpm,isrc,duration,bitrate,samplerate,channels,format,
                filesize,has_cover,replaygain_track_gain,replaygain_track_peak,
                replaygain_album_gain,replaygain_album_peak,date_added,date_modified,play_count,rating
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(path) DO UPDATE SET
                title=excluded.title,artist=excluded.artist,album=excluded.album,
                albumartist=excluded.albumartist,year=excluded.year,genre=excluded.genre,
                tracknumber=excluded.tracknumber,discnumber=excluded.discnumber,
                composer=excluded.composer,comment=excluded.comment,bpm=excluded.bpm,
                isrc=excluded.isrc,duration=excluded.duration,bitrate=excluded.bitrate,
                samplerate=excluded.samplerate,channels=excluded.channels,
                format=excluded.format,filesize=excluded.filesize,has_cover=excluded.has_cover,
                replaygain_track_gain=excluded.replaygain_track_gain,
                replaygain_track_peak=excluded.replaygain_track_peak,
                replaygain_album_gain=excluded.replaygain_album_gain,
                replaygain_album_peak=excluded.replaygain_album_peak,
                date_modified=excluded.date_modified
        """
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let T = SQLITE_TRANSIENT
        sqlite3_bind_text(stmt, 1, r.path, -1, T)
        sqlite3_bind_text(stmt, 2, r.title, -1, T)
        sqlite3_bind_text(stmt, 3, r.artist, -1, T)
        sqlite3_bind_text(stmt, 4, r.album, -1, T)
        sqlite3_bind_text(stmt, 5, r.albumartist, -1, T)
        sqlite3_bind_text(stmt, 6, r.year, -1, T)
        sqlite3_bind_text(stmt, 7, r.genre, -1, T)
        sqlite3_bind_text(stmt, 8, r.tracknumber, -1, T)
        sqlite3_bind_text(stmt, 9, r.discnumber, -1, T)
        sqlite3_bind_text(stmt, 10, r.composer, -1, T)
        sqlite3_bind_text(stmt, 11, r.comment, -1, T)
        sqlite3_bind_text(stmt, 12, r.bpm, -1, T)
        sqlite3_bind_text(stmt, 13, r.isrc, -1, T)
        sqlite3_bind_double(stmt, 14, r.duration)
        sqlite3_bind_int(stmt, 15, Int32(r.bitrate))
        sqlite3_bind_int(stmt, 16, Int32(r.samplerate))
        sqlite3_bind_int(stmt, 17, Int32(r.channels))
        sqlite3_bind_text(stmt, 18, r.format, -1, T)
        sqlite3_bind_int(stmt, 19, Int32(r.filesize))
        sqlite3_bind_int(stmt, 20, r.hasCover ? 1 : 0)
        sqlite3_bind_text(stmt, 21, r.replaygainTrackGain, -1, T)
        sqlite3_bind_text(stmt, 22, r.replaygainTrackPeak, -1, T)
        sqlite3_bind_text(stmt, 23, r.replaygainAlbumGain, -1, T)
        sqlite3_bind_text(stmt, 24, r.replaygainAlbumPeak, -1, T)
        sqlite3_bind_double(stmt, 25, r.dateAdded)
        sqlite3_bind_double(stmt, 26, r.dateModified)
        sqlite3_bind_int(stmt, 27, Int32(r.playCount))
        sqlite3_bind_int(stmt, 28, Int32(r.rating))
        sqlite3_step(stmt)
    }

    // MARK: - Queries

    func getAllTracks() -> [TrackRecord] {
        query("SELECT * FROM tracks ORDER BY artist,album,tracknumber")
    }

    func searchTracks(_ q: String) -> [TrackRecord] {
        let p = "%\(q)%"
        var stmt: OpaquePointer? = nil
        let sql = "SELECT * FROM tracks WHERE title LIKE ? OR artist LIKE ? OR album LIKE ? OR genre LIKE ? ORDER BY artist,album,tracknumber"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for i in 1...4 { sqlite3_bind_text(stmt, Int32(i), p, -1, SQLITE_TRANSIENT) }
        return rows(stmt)
    }

    func deleteTrack(path: String) {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, "DELETE FROM tracks WHERE path=?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func deleteMissingTracks() -> Int {
        let all = query("SELECT * FROM tracks")
        var removed = 0
        for t in all where !FileManager.default.fileExists(atPath: t.path) {
            deleteTrack(path: t.path); removed += 1
        }
        return removed
    }

    func updatePlayCount(path: String) {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, "UPDATE tracks SET play_count=play_count+1 WHERE path=?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func getStats() -> (tracks: Int, artists: Int, albums: Int, duration: Double) {
        var stmt: OpaquePointer? = nil
        let sql = "SELECT COUNT(*),COUNT(DISTINCT artist),COUNT(DISTINCT album),COALESCE(SUM(duration),0) FROM tracks"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (0,0,0,0) }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return (Int(sqlite3_column_int(stmt,0)), Int(sqlite3_column_int(stmt,1)),
                    Int(sqlite3_column_int(stmt,2)), sqlite3_column_double(stmt,3))
        }
        return (0,0,0,0)
    }

    // MARK: - Playlists

    func createPlaylist(name: String) -> Int {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, "INSERT INTO playlists (name,created_at,updated_at) VALUES (?,?,?)", -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        let now = Date().timeIntervalSince1970
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, now)
        sqlite3_bind_double(stmt, 3, now)
        sqlite3_step(stmt)
        return Int(sqlite3_last_insert_rowid(db))
    }

    func getAllPlaylists() -> [Playlist] {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, "SELECT id,name,description,created_at,updated_at FROM playlists ORDER BY name", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [Playlist] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(Playlist(
                id: Int(sqlite3_column_int(stmt, 0)),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                description: String(cString: sqlite3_column_text(stmt, 2)),
                createdAt: sqlite3_column_double(stmt, 3),
                updatedAt: sqlite3_column_double(stmt, 4)
            ))
        }
        return result
    }

    func deletePlaylist(id: Int) {
        exec("DELETE FROM playlist_tracks WHERE playlist_id=\(id)")
        exec("DELETE FROM playlists WHERE id=\(id)")
    }

    func addTrackToPlaylist(playlistId: Int, trackPath: String) {
        var stmt: OpaquePointer? = nil
        let sql = "INSERT OR IGNORE INTO playlist_tracks (playlist_id,track_path,position) SELECT ?,?,COALESCE(MAX(position),0)+1 FROM playlist_tracks WHERE playlist_id=?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(playlistId))
        sqlite3_bind_text(stmt, 2, trackPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, Int32(playlistId))
        sqlite3_step(stmt)
    }

    func getPlaylistTracks(playlistId: Int) -> [TrackRecord] {
        var stmt: OpaquePointer? = nil
        let sql = "SELECT t.* FROM tracks t JOIN playlist_tracks pt ON t.path=pt.track_path WHERE pt.playlist_id=? ORDER BY pt.position"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(playlistId))
        return rows(stmt)
    }

    // MARK: - Private helpers

    private func query(_ sql: String) -> [TrackRecord] {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        return rows(stmt)
    }

    private func rows(_ stmt: OpaquePointer?) -> [TrackRecord] {
        var result: [TrackRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard sqlite3_column_count(stmt) >= 28 else { continue }
            func s(_ i: Int32) -> String {
                guard let p = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: p)
            }
            var r = TrackRecord(path: s(0))
            r.title = s(1); r.artist = s(2); r.album = s(3); r.albumartist = s(4)
            r.year = s(5); r.genre = s(6); r.tracknumber = s(7); r.discnumber = s(8)
            r.composer = s(9); r.comment = s(10); r.bpm = s(11); r.isrc = s(12)
            r.duration = sqlite3_column_double(stmt, 13)
            r.bitrate = Int(sqlite3_column_int(stmt, 14))
            r.samplerate = Int(sqlite3_column_int(stmt, 15))
            r.channels = Int(sqlite3_column_int(stmt, 16))
            r.format = s(17)
            r.filesize = Int(sqlite3_column_int(stmt, 18))
            r.hasCover = sqlite3_column_int(stmt, 19) != 0
            r.replaygainTrackGain = s(20); r.replaygainTrackPeak = s(21)
            r.replaygainAlbumGain = s(22); r.replaygainAlbumPeak = s(23)
            r.dateAdded = sqlite3_column_double(stmt, 24)
            r.dateModified = sqlite3_column_double(stmt, 25)
            r.playCount = Int(sqlite3_column_int(stmt, 26))
            r.rating = Int(sqlite3_column_int(stmt, 27))
            result.append(r)
        }
        return result
    }
}
