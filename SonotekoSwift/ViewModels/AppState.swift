import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    // MARK: - Library
    @Published var tracks: [TrackRecord] = []
    @Published var filteredTracks: [TrackRecord] = []
    @Published var selectedTrackIDs: Set<String> = []
    @Published var searchQuery = "" { didSet { applyFilter() } }
    @Published var sortKey = "artist" { didSet { applyFilter() } }
    @Published var sortAscending = true { didSet { applyFilter() } }

    // MARK: - Tag Editor
    @Published var editingTags: AudioTags = AudioTags()
    @Published var tagsDirty = false
    @Published var showTagEditor = true

    // MARK: - Player
    let player = PlayerEngine.shared

    // MARK: - Scanning
    @Published var isScanning = false
    @Published var scanProgress: (current: Int, total: Int) = (0, 0)
    @Published var statusMessage = "Bereit"

    // MARK: - Online
    @Published var mbResults: [MBRelease] = []
    @Published var mbLoading = false
    @Published var lyricsResult: LyricsResult? = nil
    @Published var lyricsLoading = false
    @Published var showOnlinePanel = false

    // MARK: - ReplayGain
    @Published var replayGainRunning = false
    @Published var replayGainProgress: (current: Int, total: Int) = (0, 0)
    @Published var showReplayGainPanel = false

    // MARK: - Database
    let db = LibraryDatabase()

    init() {
        Task { await refreshLibrary() }
    }

    // MARK: - Library

    func refreshLibrary() async {
        tracks = await Task.detached { self.db.getAllTracks() }.value
        applyFilter()
        let s = db.getStats()
        statusMessage = "\(s.tracks) Tracks \u{2022} \(s.artists) Interpreten \u{2022} \(s.albums) Alben"
    }

    private func applyFilter() {
        var result = searchQuery.isEmpty ? tracks : tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.artist.localizedCaseInsensitiveContains(searchQuery) ||
            $0.album.localizedCaseInsensitiveContains(searchQuery) ||
            $0.genre.localizedCaseInsensitiveContains(searchQuery)
        }
        result.sort { a, b in
            let lhs: String
            let rhs: String
            switch sortKey {
            case "title":  lhs = a.title;  rhs = b.title
            case "album":  lhs = a.album;  rhs = b.album
            case "genre":  lhs = a.genre;  rhs = b.genre
            case "year":   lhs = a.year;   rhs = b.year
            case "format": lhs = a.format; rhs = b.format
            default:       lhs = a.artist; rhs = b.artist
            }
            return sortAscending ? lhs < rhs : lhs > rhs
        }
        filteredTracks = result
    }

    func cleanupMissing() async {
        let removed = await Task.detached { self.db.deleteMissingTracks() }.value
        await refreshLibrary()
        statusMessage = "\(removed) fehlende Tracks entfernt"
    }

    // MARK: - Import

    func openFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Ordner hinzufügen"
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map { $0.path }
        Task { await importPaths(paths) }
    }

    func openFilesDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.audio, UTType.mp3, UTType.mpeg4Audio]
        panel.prompt = "Hinzufügen"
        guard panel.runModal() == .OK else { return }
        Task { await importPaths(panel.urls.map { $0.path }) }
    }

    func importPaths(_ paths: [String]) async {
        isScanning = true
        scanProgress = (0, 0)
        statusMessage = "Scanne..."
        await Task.detached {
            await ScanService.shared.scanAndImport(paths: paths, db: self.db) { curr, total in
                Task { @MainActor in
                    self.scanProgress = (curr, total)
                    self.statusMessage = "Importiere \(curr)/\(total)..."
                }
            }
        }.value
        isScanning = false
        await refreshLibrary()
    }

    // MARK: - Tag Editor

    var selectedTracks: [TrackRecord] { filteredTracks.filter { selectedTrackIDs.contains($0.id) } }

    func loadTagsForSelection() {
        guard let first = selectedTracks.first else { editingTags = AudioTags(); return }
        Task {
            let tags = await TagHandler.shared.readTags(at: first.path)
            editingTags = tags
            tagsDirty = false
        }
    }

    func saveCurrentTags() {
        guard tagsDirty else { return }
        Task {
            for track in selectedTracks {
                try? await TagHandler.shared.writeTags(at: track.path, tags: editingTags)
            }
            tagsDirty = false
            await refreshLibrary()
            statusMessage = "Tags gespeichert"
        }
    }

    // MARK: - MusicBrainz

    func searchMusicBrainz() {
        guard let track = selectedTracks.first else { return }
        mbLoading = true
        mbResults = []
        Task {
            let results = await MusicBrainzService.shared.searchRelease(
                artist: editingTags.artist.isEmpty ? track.artist : editingTags.artist,
                album:  editingTags.album.isEmpty  ? track.album  : editingTags.album
            )
            mbResults = results
            mbLoading = false
        }
    }

    func applyMBRelease(_ release: MBRelease, trackIndex: Int? = nil) {
        editingTags.album       = release.title
        editingTags.albumartist = release.artist
        editingTags.date        = release.date
        if editingTags.artist.isEmpty { editingTags.artist = release.artist }
        if let idx = trackIndex, idx < release.tracks.count {
            let t = release.tracks[idx]
            editingTags.title       = t.title
            editingTags.tracknumber = t.number
            if !t.artist.isEmpty { editingTags.artist = t.artist }
        }
        tagsDirty = true
        Task {
            if let cover = await MusicBrainzService.shared.fetchCoverArt(mbid: release.id) {
                editingTags.coverData = cover
            }
        }
    }

    // MARK: - Lyrics

    func fetchLyrics() {
        guard let track = selectedTracks.first else { return }
        lyricsLoading = true
        Task {
            let result = await LyricsService.shared.search(
                artist: editingTags.artist.isEmpty ? track.artist : editingTags.artist,
                title:  editingTags.title.isEmpty  ? track.title  : editingTags.title,
                album:  editingTags.album.isEmpty  ? track.album  : editingTags.album,
                duration: track.duration
            )
            lyricsResult = result
            if let lyrics = result?.plainLyrics { editingTags.lyrics = lyrics; tagsDirty = true }
            lyricsLoading = false
        }
    }

    // MARK: - ReplayGain

    func runReplayGain(albumMode: Bool) {
        let sel = selectedTracks
        guard !sel.isEmpty else { return }
        replayGainRunning = true
        replayGainProgress = (0, sel.count)
        Task {
            let paths = sel.map { $0.path }
            let results = await ReplayGainService.shared.analyzeAlbum(paths: paths) { curr, total in
                Task { @MainActor in self.replayGainProgress = (curr, total) }
            }
            for track in sel {
                if let r = results[track.path] {
                    var t = track
                    t.replaygainTrackGain = r.trackGain
                    t.replaygainTrackPeak = r.trackPeak
                    if albumMode { t.replaygainAlbumGain = r.albumGain; t.replaygainAlbumPeak = r.albumPeak }
                    db.upsertTrack(t)
                    // Write to file
                    var tags = await TagHandler.shared.readTags(at: track.path)
                    tags.replaygainTrackGain = r.trackGain; tags.replaygainTrackPeak = r.trackPeak
                    if albumMode { tags.replaygainAlbumGain = r.albumGain; tags.replaygainAlbumPeak = r.albumPeak }
                    try? await TagHandler.shared.writeTags(at: track.path, tags: tags)
                }
            }
            replayGainRunning = false
            await refreshLibrary()
            statusMessage = "ReplayGain abgeschlossen"
        }
    }
}
