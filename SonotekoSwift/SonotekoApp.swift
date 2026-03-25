import SwiftUI

@main
struct SonotekoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Sonoteko") {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Datei") {
                Button("Ordner hinzufügen\u{2026}") { appState.openFolderDialog() }
                    .keyboardShortcut("O", modifiers: [.command, .shift])
                Button("Dateien öffnen\u{2026}") { appState.openFilesDialog() }
                    .keyboardShortcut("O")
                Divider()
                Button("Tags speichern") { appState.saveCurrentTags() }
                    .keyboardShortcut("S")
            }
            CommandMenu("Library") {
                Button("Neu laden") { Task { await appState.refreshLibrary() } }
                    .keyboardShortcut("R")
                Button("Fehlende Tracks bereinigen") {
                    Task { await appState.cleanupMissing() }
                }
            }
        }
    }
}
