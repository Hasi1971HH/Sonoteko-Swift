import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var sortOrder = [KeyPathComparator(\TrackRecord.artist)]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button { app.openFolderDialog() } label: {
                    Label("Ordner", systemImage: "folder.badge.plus")
                }
                Button { app.openFilesDialog() } label: {
                    Label("Dateien", systemImage: "plus")
                }
                Divider().frame(height: 20)
                Button {
                    Task { await app.refreshLibrary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Neu laden")
                Button { app.showOnlinePanel = true } label: {
                    Label("Online", systemImage: "globe")
                }
                .disabled(app.selectedTrackIDs.isEmpty)
                Button { app.showReplayGainPanel = true } label: {
                    Label("ReplayGain", systemImage: "waveform")
                }
                .disabled(app.selectedTrackIDs.isEmpty)
                Spacer()
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Suchen...", text: $app.searchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            Table(app.filteredTracks, selection: $app.selectedTrackIDs, sortOrder: $sortOrder) {
                TableColumn("Titel", value: \.title)
                    .width(min: 120, ideal: 200)
                TableColumn("Interpret", value: \.artist)
                    .width(min: 100, ideal: 150)
                TableColumn("Album", value: \.album)
                    .width(min: 100, ideal: 150)
                TableColumn("Jahr", value: \.year)
                    .width(min: 40, ideal: 55, max: 65)
                TableColumn("Genre", value: \.genre)
                    .width(min: 70, ideal: 100)
                TableColumn("Zeit") { r in
                    Text(r.formattedDuration).monospacedDigit()
                }
                .width(min: 40, ideal: 55, max: 65)
                TableColumn("Format", value: \.format)
                    .width(min: 40, ideal: 50, max: 60)
                TableColumn("BR") { r in
                    Text(r.bitrate > 0 ? "\(r.bitrate)" : "-").monospacedDigit()
                }
                .width(min: 35, ideal: 45, max: 55)
            }
            .onChange(of: sortOrder) { order in
                app.filteredTracks.sort(using: order)
            }
            .onChange(of: app.selectedTrackIDs) { _ in
                app.loadTagsForSelection()
            }
            .contextMenu {
                Button("In Finder zeigen") {
                    if let track = app.selectedTracks.first {
                        NSWorkspace.shared.selectFile(track.path, inFileViewerRootedAtPath: "")
                    }
                }
                Button("Abspielen") {
                    app.player.setQueue(app.selectedTracks)
                }
                Divider()
                Button("Aus Library entfernen", role: .destructive) {
                    for t in app.selectedTracks { app.db.deleteTrack(path: t.path) }
                    Task { await app.refreshLibrary() }
                }
            }
        }
        .onDeleteCommand {
            for t in app.selectedTracks { app.db.deleteTrack(path: t.path) }
            Task { await app.refreshLibrary() }
        }
    }
}
