import Foundation
import Observation
import WidgetKit

/// The app's store: the week files under `~/Documents/Sprint Boards/<year>/Q<n>/Week <k>.json`,
/// written atomically, mirrored to the App Group snapshot the widget reads after every change.
@MainActor
@Observable
final class BoardStore {
    let root: URL
    /// Weeks that have a file, ascending.
    private(set) var weeks: [WeekID] = []
    private(set) var boards: [WeekID: Board] = [:]
    private(set) var lastError: String?

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Sprint Boards", isDirectory: true)) {
        self.root = root
    }

    func url(for week: WeekID) -> URL { root.appendingPathComponent(week.relativePath) }
    func hasFile(_ week: WeekID) -> Bool { boards[week] != nil }

    var years: [Int] { Array(Set(weeks.map(\.year))).sorted(by: >) }
    func quarters(in year: Int) -> [Int] { Array(Set(weeks.filter { $0.year == year }.map(\.quarter))).sorted(by: >) }
    func weeks(in year: Int, quarter: Int) -> [WeekID] { weeks.filter { $0.year == year && $0.quarter == quarter }.sorted(by: >) }

    /// The board of a week; an empty one when the week has no file yet.
    func board(for week: WeekID) -> Board { boards[week] ?? Board(week: week) }

    // MARK: Files

    /// Rereads every week file. Cheap: a few KB per week.
    func reload() {
        var loaded: [WeekID: Board] = [:]
        for week in scan(suffix: ".json") {
            if let board = read(week) { loaded[week] = board }
        }
        boards = loaded
        weeks = loaded.keys.sorted()
        mirror()
    }

    private func read(_ week: WeekID) -> Board? {
        do {
            let data = try Data(contentsOf: url(for: week))
            var board = try SharedStore.decoder.decode(Board.self, from: data)
            board.week = week
            return board
        } catch {
            lastError = "\(week.label): \(error.localizedDescription)"
            return nil
        }
    }

    /// Weeks that have a `Week <k><suffix>` file under `<year>/Q<n>/`.
    func scan(suffix: String) -> [WeekID] {
        let fm = FileManager.default
        var found: [WeekID] = []
        for y in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            guard let year = Int(y) else { continue }
            let yearURL = root.appendingPathComponent(y)
            for q in (try? fm.contentsOfDirectory(atPath: yearURL.path)) ?? [] {
                guard q.hasPrefix("Q"), let quarter = Int(q.dropFirst()) else { continue }
                for f in (try? fm.contentsOfDirectory(atPath: yearURL.appendingPathComponent(q).path)) ?? [] {
                    guard f.hasPrefix("Week "), f.hasSuffix(suffix),
                          let week = Int(f.dropFirst(5).dropLast(suffix.count)) else { continue }
                    found.append(WeekID(year: year, quarter: quarter, week: week))
                }
            }
        }
        return found.sorted()
    }

    /// Writes one board atomically (folders created as needed), then refreshes the widget.
    func save(_ board: Board) {
        var board = board
        board.normalize()
        let url = self.url(for: board.week)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SharedStore.encoder.encode(board).write(to: url, options: .atomic)
            lastError = nil
        } catch {
            lastError = "\(board.week.label): \(error.localizedDescription)"
        }
        boards[board.week] = board
        if !weeks.contains(board.week) { weeks = (weeks + [board.week]).sorted() }
        mirror()
    }

    private func mirror() {
        SharedStore.saveSnapshot(Array(boards.values))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Cards

    @discardableResult
    func addCard(title: String, jiraKey: String?, lane: Lane, in week: WeekID) -> Card {
        var board = board(for: week)
        let card = Card(title: title.trimmingCharacters(in: .whitespacesAndNewlines), jiraKey: jiraKey?.trimmingCharacters(in: .whitespaces), lane: lane)
        board.append(card)
        save(board)
        return card
    }

    func update(_ id: UUID, title: String, jiraKey: String?, in week: WeekID) {
        var board = board(for: week)
        guard var card = board.card(id: id), !card.isSpilled else { return }
        card.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = jiraKey?.trimmingCharacters(in: .whitespaces) ?? ""
        card.jiraKey = key.isEmpty ? nil : key
        card.updatedAt = Date()
        board.replace(card)
        save(board)
    }

    func delete(_ id: UUID, in week: WeekID) {
        var board = board(for: week)
        guard board.remove(id: id) != nil else { return }
        save(board)
    }

    func move(_ id: UUID, to lane: Lane, placement: Board.Placement = .end, in week: WeekID) {
        var board = board(for: week)
        guard let card = board.card(id: id), !card.isSpilled else { return }
        board.move(id: id, to: lane, placement: placement)
        save(board)
    }

    /// "Spill over to next week": the card stays in its lane here, marked moved, and a copy with
    /// `movedFrom` set goes to the same lane of next week (file and folders created if missing).
    @discardableResult
    func spillOver(_ id: UUID, in week: WeekID) -> WeekID? {
        var board = board(for: week)
        guard var card = board.card(id: id), !card.isSpilled else { return nil }
        let next = week.next
        var nextBoard = self.board(for: next)
        let copy = Card(title: card.title, jiraKey: card.jiraKey, lane: card.lane, movedFrom: week)
        nextBoard.append(copy)
        card.movedTo = next
        card.updatedAt = Date()
        board.replace(card)
        save(nextBoard)
        save(board)
        return next
    }

    /// Cards whose Jira key equals the query (first) or whose title or key contains it.
    func find(_ query: String, in week: WeekID, includeSpilled: Bool = false) -> [Card] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let cards = board(for: week).allCards.filter { includeSpilled || !$0.isSpilled }
        let exact = cards.filter { ($0.jiraKey ?? "").lowercased() == q }
        if !exact.isEmpty { return exact }
        return cards.filter { $0.title.lowercased().contains(q) || ($0.jiraKey ?? "").lowercased().contains(q) }
    }

    // MARK: Import of the Boards app's files

    /// Imports every `.boards` file that has no `.json` yet. Returns how many weeks were imported.
    /// To Do → todo, Doing → prog, Blocked → block, Done → done; a card in the old Spillover list
    /// stays in todo marked moved to the next week and a copy goes to next week's todo, unless
    /// that week already has a card with the same title (the user had often copied it by hand).
    @discardableResult
    func importBoards() -> Int {
        let missing = scan(suffix: ".boards").filter { boards[$0] == nil }
        guard !missing.isEmpty else { return 0 }
        var pending: [WeekID: Board] = [:]
        var spilled: [(from: WeekID, titles: [String])] = []
        for week in missing {
            let file = root.appendingPathComponent("\(week.year)/Q\(week.quarter)/Week \(week.week).boards")
            do {
                let lists = try BoardsImporter.read(file)
                let date = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? Date()
                let result = BoardsImporter.board(from: lists, week: week, date: date)
                pending[week] = result.board
                if !result.spilled.isEmpty { spilled.append((week, result.spilled)) }
            } catch {
                lastError = "Import of \(week.label) failed: \(error.localizedDescription)"
            }
        }
        for item in spilled {
            let next = item.from.next
            var target = pending[next] ?? boards[next] ?? Board(week: next)
            for title in item.titles where !target.contains(title: title) {
                target.append(Card(title: title, lane: .todo, movedFrom: item.from))
            }
            pending[next] = target
        }
        for week in pending.keys.sorted() { save(pending[week]!) }
        return missing.count
    }
}
