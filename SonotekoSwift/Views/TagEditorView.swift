import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TagEditorView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedTab = 0
    @State private var showRenameSheet = false
    @State private var renameTemplate = "%track% - %title%"

    var body: some View {
        VStack(spacing: 0) {
            // Cover art
            coverArtView

            Divider()

            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Tags").tag(0)
                Text("Info").tag(1)
                Text("Erweitert").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                Group {
                    if selectedTab == 0 { basicTagsForm }
                    else if selectedTab == 1 { infoForm }
                    else { extendedTagsForm }
                }
                .padding(12)
            }

            Divider()

            // Action buttons
            HStack {
                Button("Umbenennen") { showRenameSheet = true }
                    .help("%title%, %artist%, %album%, %track%, %year%")
                Spacer()
                if app.tagsDirty {
                    Button("Verwerfen") { app.loadTagsForSelection() }
                        .foregroundStyle(.red)
                }
                Button("Speichern") { app.saveCurrentTags() }
                    .keyboardShortcut("S")
                    .buttonStyle(.borderedProminent)
                    .disabled(!app.tagsDirty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(template: $renameTemplate)
        }
    }

    private var coverArtView: some View {
        ZStack {
            if let data = app.editingTags.coverData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .bottomTrailing) {
                        Button { app.editingTags.coverData = nil; app.tagsDirty = true } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("Cover ziehen oder klicken")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { pickCoverArt() }
        .onDrop(of: [UTType.image], isTargeted: nil) { providers in
            providers.first?.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data = data { Task { @MainActor in
                    app.editingTags.coverData = data
                    app.tagsDirty = true
                }}
            }
            return true
        }
    }

    private func pickCoverArt() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.jpeg, UTType.png, UTType.bmp]
        panel.prompt = "Cover auswählen"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        app.editingTags.coverData = data
        app.editingTags.coverMime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        app.tagsDirty = true
    }

    private var basicTagsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Titel",       $app.editingTags.title)
            field("Interpret",  $app.editingTags.artist)
            field("Album",      $app.editingTags.album)
            field("Album-Interpret", $app.editingTags.albumartist)
            HStack(spacing: 8) {
                fieldSmall("Jahr", $app.editingTags.date)
                fieldSmall("Track #", $app.editingTags.tracknumber)
                fieldSmall("Disc #", $app.editingTags.discnumber)
            }
            field("Genre",      $app.editingTags.genre)
            field("Komponist",  $app.editingTags.composer)
            field("Kommentar",  $app.editingTags.comment)
        }
    }

    private var extendedTagsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("BPM",           $app.editingTags.bpm)
            field("ISRC",          $app.editingTags.isrc)
            field("Tonart",        $app.editingTags.key)
            field("Stimmung",      $app.editingTags.mood)
            field("Texter",        $app.editingTags.lyricist)
            field("Verlag",        $app.editingTags.publisher)
            field("Copyright",     $app.editingTags.copyright)
            field("Untertitel",    $app.editingTags.subtitle)
            field("Originalinterpret", $app.editingTags.originalartist)
            Divider()
            Text("ReplayGain").font(.caption).foregroundStyle(.secondary)
            field("Track Gain",  $app.editingTags.replaygainTrackGain)
            field("Track Peak",  $app.editingTags.replaygainTrackPeak)
            field("Album Gain",  $app.editingTags.replaygainAlbumGain)
            field("Album Peak",  $app.editingTags.replaygainAlbumPeak)
            Divider()
            Text("Lyrics").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $app.editingTags.lyrics)
                .font(.system(size: 12))
                .frame(minHeight: 120)
                .border(.separator)
                .onChange(of: app.editingTags.lyrics) { _ in app.tagsDirty = true }
        }
    }

    private var infoForm: some View {
        let t = app.editingTags
        return VStack(alignment: .leading, spacing: 8) {
            infoRow("Format",     t.format)
            infoRow("Bitrate",    t.bitrate > 0 ? "\(t.bitrate) kbps" : "-")
            infoRow("Samplerate", t.samplerate > 0 ? "\(t.samplerate) Hz" : "-")
            infoRow("Kanäle",   t.channels > 0 ? "\(t.channels)" : "-")
            infoRow("Dauer",      t.duration > 0 ? formatDuration(t.duration) : "-")
            infoRow("Dateigröße",t.filesize > 0 ? formatSize(t.filesize) : "-")
            if let track = app.selectedTracks.first {
                Divider()
                infoRow("Pfad", track.path)
                infoRow("Abgespielt", "\(track.playCount)\u{00D7}")
                Button("Im Finder öffnen") {
                    NSWorkspace.shared.selectFile(track.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: Binding(
                get: { binding.wrappedValue },
                set: { binding.wrappedValue = $0; app.tagsDirty = true }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func fieldSmall(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: Binding(
                get: { binding.wrappedValue },
                set: { binding.wrappedValue = $0; app.tagsDirty = true }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.caption).textSelection(.enabled)
            Spacer()
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let i = Int(s); let h = i/3600; let m = (i%3600)/60; let sec = i%60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        else if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes)/1024) }
        else { return String(format: "%.1f MB", Double(bytes)/1_048_576) }
    }
}

struct RenameSheet: View {
    @EnvironmentObject var app: AppState
    @Binding var template: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dateien umbenennen").font(.headline)
            Text("Verfügbare Platzhalter: %title%, %artist%, %album%, %track%, %disc%, %year%, %albumartist%")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Vorlage", text: $template)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Umbenennen") {
                    for track in app.selectedTracks {
                        let tags = app.editingTags
                        Task {
                            let newPath = try? await TagHandler.shared.renameFile(
                                at: track.path, template: template, tags: tags)
                            if let p = newPath, p != track.path {
                                app.db.deleteTrack(path: track.path)
                                var updated = track; updated.path = p
                                app.db.upsertTrack(updated)
                            }
                        }
                    }
                    Task { await app.refreshLibrary() }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
