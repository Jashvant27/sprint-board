import SwiftUI

/// A week in the user's quarter-relative numbering: Q3 Week 13 is followed by Q4 Week 1.
/// The date arithmetic (ISO weeks, Monday start) is in `WeekRule.swift`.
struct WeekID: Codable, Hashable, Comparable, Identifiable {
    var year: Int
    var quarter: Int
    var week: Int

    var id: String { "\(year)/Q\(quarter)/\(week)" }

    static func < (lhs: WeekID, rhs: WeekID) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.quarter != rhs.quarter { return lhs.quarter < rhs.quarter }
        return lhs.week < rhs.week
    }

    var title: String { "Week \(week)" }
    var label: String { "Week \(week) · Q\(quarter) \(year)" }
    /// `2026/Q4/Week 4.json`, relative to the Sprint Boards folder.
    var relativePath: String { "\(year)/Q\(quarter)/Week \(week).json" }
    /// The URL form used by the widget and the scripts: `2026/Q4/4`.
    var urlPath: String { "\(year)/Q\(quarter)/\(week)" }
}

/// The four lanes, in board order. The raw values are the lane names in the JSON files and the
/// scripts' `<todo|prog|block|done>` argument.
enum Lane: String, Codable, CaseIterable, Identifiable {
    case todo, prog, block, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "TO DO"
        case .prog: "IN PROGRESS"
        case .block: "BLOCKED"
        case .done: "DONE"
        }
    }

    var shortTitle: String {
        switch self {
        case .todo: "To do"
        case .prog: "In progress"
        case .block: "Blocked"
        case .done: "Done"
        }
    }

    /// The column colours of the user's old Boards app: blue, yellow, red, green.
    var color: Color {
        switch self {
        case .todo: Color(red: 0.24, green: 0.47, blue: 0.86)
        case .prog: Color(red: 0.84, green: 0.64, blue: 0.14)
        case .block: Color(red: 0.80, green: 0.26, blue: 0.20)
        case .done: Color(red: 0.24, green: 0.62, blue: 0.32)
        }
    }
}

struct Card: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var jiraKey: String?
    var lane: Lane
    var createdAt: Date
    var updatedAt: Date
    /// Set by "Spill over to next week": the card stays here, struck through, and a copy lives in
    /// that week. A spilled card can only be deleted.
    var movedTo: WeekID?
    /// On the copy: the week it was spilled over from.
    var movedFrom: WeekID?

    var isSpilled: Bool { movedTo != nil }

    init(id: UUID = UUID(), title: String, jiraKey: String? = nil, lane: Lane,
         createdAt: Date = Date(), updatedAt: Date = Date(), movedTo: WeekID? = nil, movedFrom: WeekID? = nil) {
        self.id = id
        self.title = title
        self.jiraKey = jiraKey.flatMap { $0.isEmpty ? nil : $0 }
        self.lane = lane
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.movedTo = movedTo
        self.movedFrom = movedFrom
    }
}

struct LaneCards: Codable, Hashable {
    var lane: Lane
    var cards: [Card]
}

/// One week's board: the four lanes in order, each with its cards in board order.
struct Board: Codable, Hashable {
    var version: Int
    var week: WeekID
    var lanes: [LaneCards]

    init(week: WeekID) {
        version = 1
        self.week = week
        lanes = Lane.allCases.map { LaneCards(lane: $0, cards: []) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        week = try c.decode(WeekID.self, forKey: .week)
        lanes = try c.decodeIfPresent([LaneCards].self, forKey: .lanes) ?? []
        normalize()
    }

    /// Every lane present once, in order; each card's `lane` field matches the lane it sits in;
    /// spilled cards sink to the bottom of their lane, in their own order.
    mutating func normalize() {
        var byLane: [Lane: [Card]] = [:]
        for group in lanes {
            for var card in group.cards {
                card.lane = group.lane
                byLane[group.lane, default: []].append(card)
            }
        }
        lanes = Lane.allCases.map { lane in
            let cards = byLane[lane] ?? []
            return LaneCards(lane: lane, cards: cards.filter { !$0.isSpilled } + cards.filter(\.isSpilled))
        }
    }

    func cards(in lane: Lane) -> [Card] { lanes.first { $0.lane == lane }?.cards ?? [] }
    var allCards: [Card] { lanes.flatMap(\.cards) }
    var isEmpty: Bool { allCards.isEmpty }
    func card(id: UUID) -> Card? { allCards.first { $0.id == id } }
    func count(in lane: Lane) -> Int { cards(in: lane).count }
    var doneCount: Int { count(in: .done) }
    var totalCount: Int { allCards.count }

    private func laneIndex(_ lane: Lane) -> Int {
        lanes.firstIndex { $0.lane == lane } ?? 0
    }

    mutating func append(_ card: Card) {
        if lanes.isEmpty { normalize() }
        lanes[laneIndex(card.lane)].cards.append(card)
    }

    @discardableResult
    mutating func remove(id: UUID) -> Card? {
        for i in lanes.indices {
            if let j = lanes[i].cards.firstIndex(where: { $0.id == id }) {
                return lanes[i].cards.remove(at: j)
            }
        }
        return nil
    }

    /// Replaces the card with the same id. It keeps its place when the lane is unchanged and
    /// goes to the end of the new lane otherwise.
    mutating func replace(_ card: Card) {
        guard let old = self.card(id: card.id) else { append(card); return }
        if old.lane == card.lane {
            let i = laneIndex(card.lane)
            if let j = lanes[i].cards.firstIndex(where: { $0.id == card.id }) { lanes[i].cards[j] = card }
        } else {
            remove(id: card.id)
            append(card)
        }
    }

    /// Where a moved card lands in its lane. Dragging within a lane reorders it: the top of the
    /// To do lane is the highest priority.
    enum Placement: Hashable {
        case end, start
        case before(UUID), after(UUID)
    }

    /// Moves a card to a lane (the same one to reorder it) at `placement`.
    mutating func move(id: UUID, to lane: Lane, placement: Placement = .end) {
        switch placement {
        case .before(let target) where target == id, .after(let target) where target == id: return
        default: break
        }
        guard var card = remove(id: id) else { return }
        card.lane = lane
        card.updatedAt = Date()
        let i = laneIndex(lane)
        let index: Int
        switch placement {
        case .end: index = lanes[i].cards.count
        case .start: index = 0
        case .before(let target): index = lanes[i].cards.firstIndex { $0.id == target } ?? lanes[i].cards.count
        case .after(let target): index = lanes[i].cards.firstIndex { $0.id == target }.map { $0 + 1 } ?? lanes[i].cards.count
        }
        lanes[i].cards.insert(card, at: index)
    }

    func contains(title: String) -> Bool {
        let wanted = Board.normalized(title)
        return allCards.contains { Board.normalized($0.title) == wanted }
    }

    static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
