import SwiftUI
import AppKit

struct OnlineView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    @State private var selectedRelease: MBRelease?
    @State private var selectedTrackIdx: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Online-Daten")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            Picker("", selection: $selectedTab) {
                Text("MusicBrainz").tag(0)
                Text("Lyrics").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                musicBrainzTab
            } else {
                lyricsTab
            }
        }
        .frame(width: 700, height: 500)
    }

    private var musicBrainzTab: some View {
        HSplitView {
            // Results list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Suchergebnisse").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Suchen") { app.searchMusicBrainz() }
                        .disabled(app.mbLoading)
                    if app.mbLoading { ProgressView().scaleEffect(0.6) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List(app.mbResults, selection: $selectedRelease) { release in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(release.title).font(.system(size: 12, weight: .medium))
                        Text(release.artist).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            if !release.date.isEmpty {
                                Text(release.date).font(.caption2).foregroundStyle(.tertiary)
                            }
                            if !release.country.isEmpty {
                                Text(release.country).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .tag(release)
                }
            }
            .frame(minWidth: 240, maxWidth: 300)

            // Track list
            if let rel = selectedRelease {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rel.title).font(.headline)
                            Text(rel.artist).foregroundStyle(.secondary)
                            if !rel.label.isEmpty { Text(rel.label).font(.caption).foregroundStyle(.tertiary) }
                        }
                        Spacer()
                        Button("Alles übernehmen") {
                            app.applyMBRelease(rel)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)

                    Divider()

                    List(Array(rel.tracks.enumerated()), id: \.offset, selection: $selectedTrackIdx) { idx, track in
                        HStack {
                            Text(track.number)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                if !track.artist.isEmpty && track.artist != rel.artist {
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if track.length > 0 {
                                Text(formatMs(track.length)).monospacedDigit().font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tag(idx)
                    }

                    Divider()

                    HStack {
                        Spacer()
                        if let idx = selectedTrackIdx {
                            Button("Track übernehmen") { app.applyMBRelease(rel, trackIndex: idx) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Album übernehmen") { app.applyMBRelease(rel) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Release auswählen")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var lyricsTab: some View {
        VStack(spacing: 0) {
            HStack {
                if app.lyricsLoading { ProgressView().scaleEffect(0.7) }
                Button("Lyrics suchen") { app.fetchLyrics() }
                    .disabled(app.lyricsLoading)
                Spacer()
                if let r = app.lyricsResult {
                    Text("Quelle: \(r.source)").font(.caption).foregroundStyle(.secondary)
                    Button("In Tags speichern") {
                        app.editingTags.lyrics = r.plainLyrics
                        app.tagsDirty = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)

            Divider()

            if let r = app.lyricsResult {
                ScrollView {
                    Text(r.syncedLyrics.isEmpty ? r.plainLyrics : r.syncedLyrics)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Keine Lyrics geladen")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func formatMs(_ ms: Int) -> String {
        let s = ms/1000; return String(format: "%d:%02d", s/60, s%60)
    }
}
