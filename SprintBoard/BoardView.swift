import SwiftUI
import UniformTypeIdentifiers

/// One week as four columns: TO DO, IN PROGRESS, BLOCKED, DONE.
struct BoardView: View {
    @Environment(BoardStore.self) private var store
    let week: WeekID
    let navigate: (WeekID) -> Void

    @State private var addingFromToolbar = false
    @State private var pendingDelete: Card?
    @State private var debugLogging = SharedStore.debugLogging
    /// The clicked card: white border; Delete asks to delete it, Escape deselects.
    @State private var selected: UUID?
    @FocusState private var boardFocused: Bool

    var body: some View {
        let board = store.board(for: week)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Lane.allCases) { lane in
                    LaneColumn(week: week, lane: lane, cards: board.cards(in: lane),
                               selected: $selected,
                               onSelect: { selected = $0; boardFocused = true },
                               onDelete: { pendingDelete = $0 },
                               navigate: navigate)
                }
            }
            .padding(16)
            // Every change of the board (a move, a reorder, add, delete, spill, also from the
            // scripts) animates: cards slide to their new place, appear and disappear softly.
            .animation(.snappy(duration: 0.35), value: board)
            // Keyboard: the board takes focus when a card is clicked, so Delete and Escape reach
            // it; a focused text field (the editor popover) keeps those keys for itself.
            .focusable()
            .focusEffectDisabled()
            .focused($boardFocused)
            .onDeleteCommand {
                if let id = selected, let card = board.card(id: id) { pendingDelete = card }
            }
            .onExitCommand { selected = nil }
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
                Button { addingFromToolbar = true } label: { Label("Add card", systemImage: "plus") }
                    .help("Add a card to To do (Cmd+N)")
                    .popover(isPresented: $addingFromToolbar, arrowEdge: .bottom) {
                        CardEditor(target: .new(.todo)) { title, jiraKey in
                            store.addCard(title: title, jiraKey: jiraKey, lane: .todo, in: week)
                        }
                    }
            }
        }
        .alert("Delete this card?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { card in
            Button("Delete", role: .destructive) {
                store.delete(card.id, in: week)
                if selected == card.id { selected = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text(card.title)
        }
        .onChange(of: week) { _, _ in selected = nil }
        .onReceive(NotificationCenter.default.publisher(for: .newCardRequested)) { _ in addingFromToolbar = true }
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

/// One lane: a coloured column with its dark cards. Cards are dragged between and within lanes;
/// while a drag hovers the column a white line shows where the card will land. Double-clicking a
/// card (or Edit… in its menu) opens the editor as a popover on the card; the "+" in the header
/// opens it for a new card.
struct LaneColumn: View {
    @Environment(BoardStore.self) private var store
    let week: WeekID
    let lane: Lane
    let cards: [Card]
    @Binding var selected: UUID?
    let onSelect: (UUID) -> Void
    let onDelete: (Card) -> Void
    let navigate: (WeekID) -> Void

    @State private var targeted = false
    /// Card frames in the lane's coordinate space, read only while a drag hovers. A plain object,
    /// not state or a preference: measuring must never re-render the lane.
    @State private var frames = FrameRegistry()
    /// Insertion index shown by the drop line while a drag hovers; `cards.count` is "after the last".
    @State private var indicator: Int?
    @State private var editing: UUID?
    @State private var adding = false
    private let session = DragSession.shared

    private var space: String { "lane-\(lane.rawValue)" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        cell(card)
                            .overlay(alignment: .top) {
                                if session.active, indicator == index { dropLine.offset(y: -5.5) }
                            }
                            .overlay(alignment: .bottom) {
                                if session.active, index == cards.count - 1, indicator == cards.count { dropLine.offset(y: 5.5) }
                            }
                    }
                    if session.active, cards.isEmpty, indicator != nil { dropLine }
                }
                .padding(10)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A click on the lane outside a card deselects (the card's own tap gesture wins inside).
        .contentShape(Rectangle())
        .onTapGesture { selected = nil }
        .coordinateSpace(name: space)
        .background(lane.color.opacity(session.active && targeted ? 0.3 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lane.color.opacity(session.active && targeted ? 0.9 : 0.35), lineWidth: 1))
        .onDrop(of: [.utf8PlainText, .plainText, .text], delegate: LaneDropDelegate(
            insertionIndex: insertionIndex(at:), indicator: $indicator, targeted: $targeted,
            dragEntered: { DragSession.shared.begin() }, perform: perform(id:at:)))
        // Whenever a drag starts or ends, forget the hover state; the delegate sets it afresh.
        .onChange(of: session.active) { _, _ in
            if indicator != nil { indicator = nil }
            if targeted { targeted = false }
        }
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
            Button { adding = true } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .help("Add a card to \(lane.shortTitle)")
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    CardEditor(target: .new(lane)) { title, jiraKey in
                        store.addCard(title: title, jiraKey: jiraKey, lane: lane, in: week)
                    }
                }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(lane.color)
    }

    private var dropLine: some View {
        Capsule()
            .fill(.white)
            .frame(height: 3)
            .shadow(color: .black.opacity(0.5), radius: 1.5)
    }

    @ViewBuilder
    private func cell(_ card: Card) -> some View {
        let view = CardView(card: card, selected: selected == card.id)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .background(GeometryReader { geo in
                let frame = geo.frame(in: .named(space))
                Color.clear
                    .onAppear { frames.rects[card.id] = frame }
                    .onChange(of: frame) { _, new in frames.rects[card.id] = new }
            })
            .contextMenu { menu(card) }
            .popover(isPresented: Binding(get: { editing == card.id }, set: { if !$0 { editing = nil } }), arrowEdge: .trailing) {
                CardEditor(target: .edit(card)) { title, jiraKey in
                    store.update(card.id, title: title, jiraKey: jiraKey, in: week)
                }
            }
        if card.isSpilled {
            view
                .onTapGesture { onSelect(card.id) }
        } else {
            view
                .onTapGesture(count: 2) { editing = card.id }
                .onTapGesture { onSelect(card.id) }
                .onDrag {
                    DragSession.shared.begin()
                    return NSItemProvider(object: card.id.uuidString as NSString)
                }
        }
    }

    @ViewBuilder
    private func menu(_ card: Card) -> some View {
        if let to = card.movedTo {
            Button("Go to \(to.label)") { navigate(to) }
            Divider()
            Button("Delete", role: .destructive) { onDelete(card) }
        } else {
            Button("Edit…") { editing = card.id }
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

    /// Where a pointer at `point` (column coordinates) would insert: before the first card whose
    /// middle lies below it, else after the last card. Spilled cards sit at the bottom of a lane
    /// and stay there, so the index never goes past the first of them.
    private func insertionIndex(at point: CGPoint) -> Int {
        let limit = cards.firstIndex { $0.isSpilled } ?? cards.count
        for (index, card) in cards.enumerated() where index < limit {
            if let frame = frames.rects[card.id], point.y < frame.midY { return index }
        }
        return limit
    }

    private func perform(id: UUID, at index: Int) {
        let placement: Board.Placement = index < cards.count ? .before(cards[index].id) : .end
        store.move(id, to: lane, placement: placement, in: week)
        if indicator != nil { indicator = nil }
        if targeted { targeted = false }
    }
}

/// Whether a card drag is in progress, for every lane at once. Switched on when a drag starts
/// (`onDrag`, or a drag entering a lane) and off when the mouse button goes up, which is polled:
/// macOS does not always deliver the drop delegate's exit or drop callbacks when a session ends.
/// A lane draws its drop line and highlight only while this is on.
@Observable
final class DragSession {
    static let shared = DragSession()
    private(set) var active = false
    @ObservationIgnored private var watcher: Timer?

    func begin() {
        if !active { active = true }
        guard watcher == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            DispatchQueue.main.async { self?.end() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    func end() {
        watcher?.invalidate()
        watcher = nil
        if active { active = false }
    }
}

/// Tracks the drag over a lane: keeps the drop line at the insertion point and moves the card on
/// drop. The dragged item is the card's id as plain text (see `onDrag` in `LaneColumn.cell`).
private struct LaneDropDelegate: DropDelegate {
    let insertionIndex: (CGPoint) -> Int
    @Binding var indicator: Int?
    @Binding var targeted: Bool
    let dragEntered: () -> Void
    let perform: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }

    /// `dropUpdated` runs on every pointer move, several times per frame, so the state is only
    /// written when it changes.
    private func show(_ index: Int?, targeted on: Bool) {
        if indicator != index { indicator = index }
        if targeted != on { targeted = on }
    }

    func dropEntered(info: DropInfo) {
        show(insertionIndex(info.location), targeted: true)
        dragEntered()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        show(insertionIndex(info.location), targeted: true)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        show(nil, targeted: false)
    }

    func performDrop(info: DropInfo) -> Bool {
        let index = insertionIndex(info.location)
        show(nil, targeted: false)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? NSString, let id = UUID(uuidString: raw as String) else { return }
            DispatchQueue.main.async { perform(id, index) }
        }
        return true
    }
}

/// Card frames by id, so the drop line and the drop know which card the pointer is above.
private final class FrameRegistry {
    var rects: [UUID: CGRect] = [:]
}

/// A dark card like the Boards app's: Jira key in a muted mono chip next to the title; spilled
/// cards are struck through with "moved to Week k · Qn year" underneath.
struct CardView: View {
    let card: Card
    var selected = false

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
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: selected ? 2 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The add/edit popover: title and optional Jira key. Return saves, Escape or clicking outside
/// cancels.
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
    @FocusState private var titleFocused: Bool

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

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var heading: String {
        switch target {
        case .new(let lane): "New card in \(lane.shortTitle)"
        case .edit: "Edit card"
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Title", text: $title, axis: .vertical)
                .lineLimit(2...8)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($titleFocused)
                .onSubmit(save)
            Divider()
            TextField("Jira key (optional), e.g. BT-985", text: $jiraKey)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(save)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { titleFocused = true }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let key = jiraKey.trimmingCharacters(in: .whitespaces)
        onSave(trimmedTitle, key.isEmpty ? nil : key)
        dismiss()
    }
}
