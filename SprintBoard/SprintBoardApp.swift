import SwiftUI
import WidgetKit

@main
struct SprintBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Card…") { NotificationCenter.default.post(name: .newCardRequested, object: nil) }
                    .keyboardShortcut("n")
            }
            CommandMenu("Board") {
                Button("This Week") { NotificationCenter.default.post(name: .goToThisWeek, object: nil) }
                    .keyboardShortcut("t")
                Divider()
                Button("Import Boards Files") { NotificationCenter.default.post(name: .importRequested, object: nil) }
                Button("Reveal Boards Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.root])
                }
            }
        }
        Settings {
            SettingsView()
        }
    }
}

/// The app's Settings window (Cmd+,). "Debug logging" shows the snapshot's path, size and last
/// write error at the bottom of the board and of the widget.
struct SettingsView: View {
    @State private var debugLogging = SharedStore.debugLogging

    var body: some View {
        Form {
            Toggle("Debug logging", isOn: $debugLogging)
                .onChange(of: debugLogging) { _, on in
                    SharedStore.debugLogging = on
                    NotificationCenter.default.post(name: .debugLoggingChanged, object: nil)
                    WidgetCenter.shared.reloadAllTimelines()
                }
            Text("Shows where the week files and the widget's snapshot are and whether the last save worked, in the app and the widget.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 400)
    }
}

extension Notification.Name {
    static let debugLoggingChanged = Notification.Name("debugLoggingChanged")
    static let newCardRequested = Notification.Name("newCardRequested")
    static let goToThisWeek = Notification.Name("goToThisWeek")
    static let importRequested = Notification.Name("importRequested")
}

/// Closing the window quits the app, like the system widgets' companion apps.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
