import SwiftUI

struct ReplayGainView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var albumMode = true

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("ReplayGain").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            if !ReplayGainService.shared.isFFmpegAvailable() {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text("ffmpeg nicht gefunden").font(.headline)
                    Text("Bitte ffmpeg installieren (z.B. mit Homebrew: brew install ffmpeg)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(app.selectedTracks.count) Track(s) ausgewählt")
                        .foregroundStyle(.secondary)

                    Toggle("Album-Modus (gemeinsamer Album-Gain)", isOn: $albumMode)

                    if app.replayGainRunning {
                        VStack(spacing: 8) {
                            ProgressView(
                                value: Double(app.replayGainProgress.current),
                                total: max(1, Double(app.replayGainProgress.total))
                            )
                            .progressViewStyle(.linear)
                            Text("Analysiere \(app.replayGainProgress.current) / \(app.replayGainProgress.total)...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("Abbrechen") { dismiss() }
                    Button("Analysieren & Tags schreiben") {
                        app.runReplayGain(albumMode: albumMode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.replayGainRunning || app.selectedTracks.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 260)
    }
}
