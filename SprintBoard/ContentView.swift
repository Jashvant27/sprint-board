import SwiftUI

/// Sidebar of years → quarters → weeks with "This week" on top; the selected week's board as detail.
struct ContentView: View {
    @Environment(BoardStore.self) private var store
    @State private var selection: WeekID? = .current
    @State private var collapsed: Set<String> = []
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            BoardView(week: selection ?? .current) { selection = $0 }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            store.reload()
            let imported = store.importBoards()
            if imported > 0 { message = "Imported \(imported) week\(imported == 1 ? "" : "s") from the Boards files." }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if loaded { store.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goToThisWeek)) { _ in selection = .current }
        .onReceive(NotificationCenter.default.publisher(for: .importRequested)) { _ in runImport() }
        .onOpenURL(perform: handle)
        .alert("Sprint Board", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Label("This week", systemImage: "calendar")
                .tag(WeekID.current)
            ForEach(store.years, id: \.self) { year in
                Section(String(year)) {
                    ForEach(store.quarters(in: year), id: \.self) { quarter in
                        DisclosureGroup(isExpanded: expansion("\(year)/Q\(quarter)")) {
                            ForEach(store.weeks(in: year, quarter: quarter)) { week in
                                weekRow(week).tag(week)
                            }
                        } label: {
                            Text("Q\(quarter)")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(key) },
                set: { open in if open { collapsed.remove(key) } else { collapsed.insert(key) } })
    }

    private func weekRow(_ week: WeekID) -> some View {
        let board = store.board(for: week)
        return HStack {
            Text(week.title)
            Spacer()
            Text("\(board.doneCount)/\(board.totalCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func runImport() {
        let imported = store.importBoards()
        message = imported == 0
            ? "Nothing to import: every Boards file already has a week file."
            : "Imported \(imported) week\(imported == 1 ? "" : "s") from the Boards files."
    }

    // MARK: URL scheme

    /// sprintboard://week/<year>/<quarter>/<week>                       show a week
    /// sprintboard://set?id=<uuid>|q=<match>&lane=<lane>[&week=y/Qq/k]  move a card (Scripts/set-status.sh)
    /// sprintboard://add?title=…[&jira=…][&lane=…][&week=…]             add a card (Scripts/add-card.sh)
    /// sprintboard://spill?id=<uuid>|q=<match>[&week=…]                 spill a card over (Scripts/spill-over.sh)
    /// sprintboard://import                                             import Boards files without a week file
    private func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        let week = param("week").flatMap { WeekID(string: $0) } ?? .current
        func card() -> Card? {
            if let id = param("id").flatMap(UUID.init(uuidString:)) { return store.board(for: week).card(id: id) }
            if let q = param("q") {
                let matches = store.find(q, in: week)
                if matches.count == 1 { return matches[0] }
                message = matches.isEmpty ? "No card matches \"\(q)\" in \(week.label)." : "\(matches.count) cards match \"\(q)\" in \(week.label)."
            }
            return nil
        }
        switch url.host {
        case "week":
            let path = url.pathComponents.dropFirst().joined(separator: "/")
            if let target = WeekID(string: path) { selection = target }
        case "set":
            guard let lane = param("lane").flatMap(Lane.init(rawValue:)), let card = card() else { return }
            store.move(card.id, to: lane, in: week)
            selection = week
        case "add":
            guard let title = param("title") else { return }
            store.addCard(title: title, jiraKey: param("jira"), lane: param("lane").flatMap(Lane.init(rawValue:)) ?? .todo, in: week)
            selection = week
        case "spill":
            guard let card = card() else { return }
            store.spillOver(card.id, in: week)
            selection = week
        case "import":
            runImport()
        default:
            break
        }
    }
}
