import Foundation

/// What the app shares with the widget: a snapshot of every week's board, as one JSON file in the
/// App Group container (the widget is sandboxed and cannot read ~/Documents). A file, not
/// UserDefaults: on macOS the preferences daemon keeps App Group suite writes of a locally signed
/// app in memory only. The app rewrites the snapshot after every change and reloads the widget.
enum SharedStore {
    static let appGroup = "R9KR5T3WZB.com.jashvantsewmangal.sprintboard"

    struct Snapshot: Codable {
        var updatedAt: Date
        var boards: [Board]

        func board(for week: WeekID) -> Board? { boards.first { $0.week == week } }
    }

    /// `~/Library/Group Containers/<group>/Library/Application Support/SprintBoard/`, or nil when
    /// this process has no access to the container.
    static var directory: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = base.appendingPathComponent("Library/Application Support/SprintBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var snapshotURL: URL? { directory?.appendingPathComponent("boards.json") }
    static var settingsURL: URL? { directory?.appendingPathComponent("settings.json") }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// `settings.json`: {"debugLogging": true} shows the diagnostics line in the app and the widget.
    static var debugLogging: Bool {
        get {
            guard let url = settingsURL, let data = try? Data(contentsOf: url),
                  let settings = try? JSONDecoder().decode([String: Bool].self, from: data) else { return false }
            return settings["debugLogging"] ?? false
        }
        set {
            guard let url = settingsURL, let data = try? JSONEncoder().encode(["debugLogging": newValue]) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The last error a snapshot write hit, for the diagnostics line.
    nonisolated(unsafe) static var lastError: String?

    static var diagnostics: String {
        guard let url = snapshotURL else { return "no group container" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int).map { "\($0) B" } ?? "missing"
        return "\(abbreviated(url.path)) · \(size)" + (lastError.map { " · write failed: \($0)" } ?? "")
    }

    static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func loadSnapshot() -> Snapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func saveSnapshot(_ boards: [Board]) {
        guard let url = snapshotURL else { lastError = "no group container"; return }
        let snapshot = Snapshot(updatedAt: Date(), boards: boards.sorted { $0.week < $1.week })
        do {
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
