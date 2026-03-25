import SwiftUI
import AppKit

struct PlayerView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var player = PlayerEngine.shared
    @State private var isDragging = false
    @State private var dragTime: Double = 0

    var body: some View {
        HStack(spacing: 16) {
            // Cover
            coverThumb

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title.nilIfEmpty ?? player.currentTrack?.filename ?? "Kein Track")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(player.currentTrack?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 140, maxWidth: 200)

            Spacer()

            // Transport controls
            HStack(spacing: 4) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                .font(.title3)

                Button {
                    if player.currentTrack != nil { player.toggle() }
                    else if let first = app.filteredTracks.first {
                        player.setQueue(app.filteredTracks, startAt: 0)
                    }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .frame(width: 32)

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .font(.title3)
            }

            Spacer()

            // Progress
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { isDragging ? dragTime : player.currentTime },
                        set: { v in dragTime = v }
                    ),
                    in: 0...max(1, player.duration),
                    onEditingChanged: { editing in
                        isDragging = editing
                        if !editing { player.seek(to: dragTime) }
                    }
                )
                .frame(width: 200)
                HStack {
                    Text(formatTime(player.currentTime)).monospacedDigit()
                    Spacer()
                    Text(formatTime(player.duration)).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 200)
            }

            // Volume
            HStack(spacing: 4) {
                Image(systemName: player.volume < 0.01 ? "speaker.slash.fill" : (player.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 80)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 60)
    }

    private var coverThumb: some View {
        Group {
            if let data = app.editingTags.coverData, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func formatTime(_ s: Double) -> String {
        let i = max(0, Int(s)); return String(format: "%d:%02d", i/60, i%60)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
