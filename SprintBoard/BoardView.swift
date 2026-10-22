import SwiftUI

/// One week as four columns: TO DO, IN PROGRESS, BLOCKED, DONE.
struct BoardView: View {
    @Environment(BoardStore.self) private var store
    let week: WeekID
    let navigate: (WeekID) -> Void

    @State private var editor: CardEditor.Target?
    @State private var pendingDelete: Card?
    @State private var debugLogging = SharedStore.debugLogging

    var body: some View {
        let board = store.board(for: week)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Lane.allCases) { lane in
                    LaneColumn(week: week, lane: lane, cards: board.cards(in: lane),
                               onAdd: { editor = .new(lane) },
                               onEdit: { editor = .edit($0) },
                               onDelete: { pendingDelete = $0 },
                               navigate: navigate)
                }
            }
            .padding(16)
            if debugLogging {
                Divider()
                Text("\(SharedStore.abbreviated(store.url(for: week).path)) · \(store.hasFile(week) ? "exists" : "not created yet") · snapshot \(SharedStore.diagnostics)" + (store.lastError.map { " · \($0)" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(week.label)
        .navigationSubtitle(subtitle(board))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigate(week.previous) } label: { Image(systemName: "chevron.left") }
                    .help("Previous week")
                Button { navigate(week.next) } label: { Image(systemName: "chevron.right") }
                    .help("Next week")
                if !week.isCurrent {
                    Button("This week") { navigate(.current) }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { editor = .new(.todo) } label: { Label("Add card", systemImage: "plus") }
                    .help("Add a card to To do (Cmd+N)")
            }
        }
        .sheet(item: $editor) { target in
            CardEditor(target: target) { title, jiraKey in
                switch target {
                case .new(let lane): store.addCard(title: title, jiraKey: jiraKey, lane: lane, in: week)
                case .edit(let card): store.update(card.id, title: title, jiraKey: jiraKey, in: week)
                }
            }
        }
        .alert("Delete this card?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { card in
            Button("Delete", role: .destructive) { store.delete(card.id, in: week) }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text(card.title)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCardRequested)) { _ in editor = .new(.todo) }
        .onReceive(NotificationCenter.default.publisher(for: .debugLoggingChanged)) { _ in debugLogging = SharedStore.debugLogging }
    }

    private func subtitle(_ board: Board) -> String {
        var text = week.dateRange
        if week.isCurrent { text += " · this week" }
        if !store.hasFile(week) { text += " · no board yet, add a card to create it" }
        else { text += " · \(board.doneCount) of \(board.totalCount) done" }
        return text
    }
}

/// One lane: a coloured column with its dark cards; a drop target for cards dragged from other lanes.
struct LaneColumn: View {
    @Environment(BoardStore.self) private var store
    let week: WeekID
    let lane: Lane
    let cards: [Card]
    let onAdd: () -> Void
    let onEdit: (Card) -> Void
    let onDelete: (Card) -> Void
    let navigate: (WeekID) -> Void

    @State private var targeted = false
    @State private var headerTargeted = false
    @State private var targetedCard: UUID?
    @State private var heights: [UUID: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
                // A drop on the header puts the card at the top of the lane.
                .dropDestination(for: String.self) { items, _ in
                    drop(items, placement: .start)
                } isTargeted: { headerTargeted = $0 }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        cell(card)
                    }
                }
                .padding(10)
                .onPreferenceChange(CardHeightKey.self) { heights.merge($0) { $1 } }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(lane.color.opacity(targeted ? 0.35 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lane.color.opacity(targeted ? 0.9 : 0.35), lineWidth: 1))
        // A drop on the lane's empty space puts the card at the bottom.
        .dropDestination(for: String.self) { items, _ in
            drop(items, placement: .end)
        } isTargeted: { targeted = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(lane.title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
            Text("\(cards.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.25))
                .clipShape(Capsule())
            Spacer()
            Button(action: onAdd) { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .help("Add a card to \(lane.shortTitle)")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(lane.color.opacity(headerTargeted ? 0.7 : 1))
        .overlay(alignment: .bottom) {
            if headerTargeted { Rectangle().fill(.white).frame(height: 2) }
        }
    }

    @ViewBuilder
    private func cell(_ card: Card) -> some View {
        let view = CardView(card: card)
            .background(GeometryReader { geo in
                Color.clear.preference(key: CardHeightKey.self, value: [card.id: geo.size.height])
            })
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(targetedCard == card.id ? 0.8 : 0), lineWidth: 2))
            .contextMenu { menu(card) }
            // The upper half of a card means "before it", the lower half "after it": dragging a
            // card up or down its own lane reorders it.
            .dropDestination(for: String.self) { items, location in
                let height = heights[card.id] ?? 0
                let after = height > 0 && location.y > height / 2
                return drop(items, placement: after ? .after(card.id) : .before(card.id))
            } isTargeted: { targetedCard = $0 ? card.id : (targetedCard == card.id ? nil : targetedCard) }
        if card.isSpilled {
            view
        } else {
            view.draggable(card.id.uuidString)
        }
    }

    @ViewBuilder
    private func menu(_ card: Card) -> some View {
        if let to = card.movedTo {
            Button("Go to \(to.label)") { navigate(to) }
            Divider()
            Button("Delete", role: .destructive) { onDelete(card) }
        } else {
            Button("Edit…") { onEdit(card) }
            Menu("Move to") {
                ForEach(Lane.allCases.filter { $0 != lane }) { other in
                    Button(other.shortTitle) { store.move(card.id, to: other, in: week) }
                }
            }
            Button("Move to top") { store.move(card.id, to: lane, placement: .start, in: week) }
                .disabled(cards.first?.id == card.id)
            Button("Move to bottom") { store.move(card.id, to: lane, placement: .end, in: week) }
                .disabled(cards.last?.id == card.id)
            Button("Spill over to next week") { store.spillOver(card.id, in: week) }
            Divider()
            Button("Delete", role: .destructive) { onDelete(card) }
        }
    }

    private func drop(_ items: [String], placement: Board.Placement) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        store.move(id, to: lane, placement: placement, in: week)
        return true
    }
}

/// Card heights by id, so a drop knows whether it hit the upper or the lower half of a card.
private struct CardHeightKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A dark card like the Boards app's: Jira key in a muted mono chip next to the title; spilled
/// cards are struck through with "moved to Week k · Qn year" underneath.
struct CardView: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let key = card.jiraKey {
                    Text(key)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.75))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(card.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(card.isSpilled ? Color(white: 0.55) : .white)
                    .strikethrough(card.isSpilled, color: Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let to = card.movedTo {
                Text("moved to \(to.label)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.5))
            } else if let from = card.movedFrom {
                Text("from \(from.label)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.17, green: 0.18, blue: 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The add/edit sheet: title and optional Jira key.
struct CardEditor: View {
    enum Target: Identifiable {
        case new(Lane)
        case edit(Card)

        var id: String {
            switch self {
            case .new(let lane): "new-\(lane.rawValue)"
            case .edit(let card): card.id.uuidString
            }
        }
    }

    let target: Target
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var jiraKey: String

    init(target: Target, onSave: @escaping (String, String?) -> Void) {
        self.target = target
        self.onSave = onSave
        switch target {
        case .new:
            _title = State(initialValue: "")
            _jiraKey = State(initialValue: "")
        case .edit(let card):
            _title = State(initialValue: card.title)
            _jiraKey = State(initialValue: card.jiraKey ?? "")
        }
    }

    private var heading: String {
        switch target {
        case .new(let lane): "New card in \(lane.shortTitle)"
        case .edit: "Edit card"
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading).font(.headline)
            TextField("Title", text: $title, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
            TextField("Jira key (optional), e.g. BT-985", text: $jiraKey)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    let key = jiraKey.trimmingCharacters(in: .whitespaces)
                    onSave(trimmedTitle, key.isEmpty ? nil : key)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }
}
