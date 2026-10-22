import SwiftUI
import WidgetKit

@main
struct SprintBoardWidgetBundle: WidgetBundle {
    var body: some Widget {
        SprintBoardWidget()
    }
}

/// Read-only: the current week's four lanes from the app's snapshot. Clicking anywhere opens the
/// app on that week.
struct SprintBoardWidget: Widget {
    let kind = "SprintBoardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BoardProvider()) { entry in
            BoardWidgetView(entry: entry)
        }
        .configurationDisplayName("Sprint Board")
        .description("This week's board: to do, in progress, blocked and done.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let week: WeekID
    let board: Board?
    let debugLogging: Bool
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: .now, week: .current, board: nil, debugLogging: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(entry(at: .now, snapshot: SharedStore.loadSnapshot()))
    }

    /// One entry now and one at each of the next four Mondays 00:00, so the widget flips to the
    /// new week on its own; the app reloads the timeline after every change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let snapshot = SharedStore.loadSnapshot()
        var entries = [entry(at: .now, snapshot: snapshot)]
        var week = WeekID.current
        for _ in 0..<4 {
            week = week.next
            entries.append(entry(at: week.monday, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, snapshot: SharedStore.Snapshot?) -> BoardEntry {
        let week = WeekID(date: date)
        return BoardEntry(date: date, week: week, board: snapshot?.board(for: week), debugLogging: SharedStore.debugLogging)
    }
}

struct BoardWidgetView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let board = entry.board {
                content(board)
            } else {
                empty
            }
        }
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
        .widgetURL(URL(string: "sprintboard://week/\(entry.week.urlPath)"))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(nil)
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "rectangle.split.3x1").font(.title2).foregroundStyle(.tertiary)
                    Text("No board for \(entry.week.title) yet").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Click to open Sprint Board").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            Spacer()
            diagnostics
        }
    }

    private func content(_ board: Board) -> some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 6) {
                header(board)
                if family == .systemMedium {
                    // Two rows of two lanes.
                    let rowHeight = (geo.size.height - 22 - 6) / 2
                    let limit = max(1, Int((rowHeight - 16) / 13))
                    VStack(spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            laneView(.todo, board, limit: limit, lines: 1)
                            laneView(.prog, board, limit: limit, lines: 1)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            laneView(.block, board, limit: limit, lines: 1)
                            laneView(.done, board, limit: limit, lines: 1)
                        }
                    }
                } else {
                    let limit = max(1, Int((geo.size.height - 22 - 16) / 29))
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Lane.allCases) { lane in
                            laneView(lane, board, limit: limit, lines: 2)
                        }
                    }
                }
                Spacer(minLength: 0)
                diagnostics
            }
        }
    }

    private func header(_ board: Board?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.week.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(entry.week.dateRange).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let board {
                Text("\(board.doneCount)/\(board.totalCount) done")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func laneView(_ lane: Lane, _ board: Board, limit: Int, lines: Int) -> some View {
        let cards = board.cards(in: lane)
        let shown = Array(cards.prefix(limit))
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(lane.color).frame(width: 6, height: 6)
                Text(lane.title).font(.system(size: 9, weight: .bold)).tracking(0.4)
                Text("\(cards.count)").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            ForEach(shown) { card in
                cardLine(card, lines: lines)
            }
            if shown.count < cards.count {
                Text("+\(cards.count - shown.count) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func cardLine(_ card: Card, lines: Int) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if let key = card.jiraKey {
                Text(key)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text(card.title)
                .font(.system(size: 10.5))
                .strikethrough(card.isSpilled)
                .foregroundStyle(card.isSpilled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(lines)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var diagnostics: some View {
        if entry.debugLogging {
            Text("\(SharedStore.diagnostics) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
