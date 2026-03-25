import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                LibraryView()
                    .frame(minWidth: 500)
                if app.showTagEditor {
                    TagEditorView()
                        .frame(minWidth: 320, maxWidth: 420)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlayerView()
                .background(.regularMaterial)

            // Status bar
            HStack {
                if app.isScanning {
                    ProgressView(value: Double(app.scanProgress.current),
                                 total: max(1, Double(app.scanProgress.total)))
                        .frame(width: 120)
                        .progressViewStyle(.linear)
                }
                Text(app.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    app.showTagEditor.toggle()
                } label: {
                    Image(systemName: app.showTagEditor ? "sidebar.right" : "sidebar.right")
                }
                .buttonStyle(.plain)
                .help("Tag-Editor umschalten")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .sheet(isPresented: $app.showOnlinePanel) { OnlineView() }
        .sheet(isPresented: $app.showReplayGainPanel) { ReplayGainView() }
    }
}
