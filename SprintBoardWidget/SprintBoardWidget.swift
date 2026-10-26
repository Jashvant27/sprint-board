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

    /// Fixed heights, so the number of rows that fit is computed exactly: the week header, a lane's
    /// header, a card row with one line of title (Medium) or two (Large, Extra Large), the spacing
    /// between rows, and the footer with "+n more" under each lane that overflows, drawn only when
    /// one does (its height leaves the row budget only then, so no card slot goes to it otherwise).
    /// Medium lays the lanes out two by two, where a footer line cannot align with both rows, so
    /// there the "+n more" sits at the right end of the lane's own header instead.
    private enum Metrics {
        static let weekHeader: CGFloat = 16
        static let laneHeader: CGFloat = 12
        static let singleRow: CGFloat = 19
        static let doubleRow: CGFloat = 32
        static let rowSpacing: CGFloat = 3
        static let footer: CGFloat = 12
        static let diagnostics: CGFloat = 12
    }

    private func rows(in laneHeight: CGFloat, rowHeight: CGFloat) -> Int {
        max(0, Int((laneHeight - Metrics.laneHeader) / (rowHeight + Metrics.rowSpacing)))
    }

    /// Rows per lane for the space the lanes get in this family.
    private func limit(for available: CGFloat) -> Int {
        family == .systemMedium
            ? rows(in: (available - 6) / 2, rowHeight: Metrics.singleRow)
            : rows(in: available, rowHeight: Metrics.doubleRow)
    }

    private func overflow(_ board: Board, limit: Int) -> [(lane: Lane, count: Int)] {
        Lane.allCases.compactMap { lane in
            let extra = board.count(in: lane) - limit
            return extra > 0 ? (lane, extra) : nil
        }
    }

    private func content(_ board: Board) -> some View {
        GeometryReader { geo in
            let base = geo.size.height - Metrics.weekHeader - 6 - (entry.debugLogging ? Metrics.diagnostics + 6 : 0)
            // The footer is needed when a lane overflows even with the footer's space given to
            // rows; taking it away then can only make the overflow larger, never make it vanish.
            let footerNeeded = family != .systemMedium && !overflow(board, limit: limit(for: base)).isEmpty
            let available = base - (footerNeeded ? Metrics.footer + 6 : 0)
            let limit = limit(for: available)
            VStack(alignment: .leading, spacing: 6) {
                header(board).frame(height: Metrics.weekHeader)
                if family == .systemMedium {
                    // Two rows of two lanes.
                    let laneHeight = (available - 6) / 2
                    VStack(spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            laneView(.todo, board, limit: limit, rowHeight: Metrics.singleRow, lines: 1)
                            laneView(.prog, board, limit: limit, rowHeight: Metrics.singleRow, lines: 1)
                        }
                        .frame(height: laneHeight)
                        HStack(alignment: .top, spacing: 8) {
                            laneView(.block, board, limit: limit, rowHeight: Metrics.singleRow, lines: 1)
                            laneView(.done, board, limit: limit, rowHeight: Metrics.singleRow, lines: 1)
                        }
                        .frame(height: laneHeight)
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Lane.allCases) { lane in
                            laneView(lane, board, limit: limit, rowHeight: Metrics.doubleRow, lines: 2)
                        }
                    }
                    .frame(height: available)
                }
                if footerNeeded {
                    // One column per lane, aligned with the lanes above.
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Lane.allCases) { lane in
                            Text(moreLabel(board.count(in: lane) - limit))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(height: Metrics.footer)
                }
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

    private func moreLabel(_ extra: Int) -> String { extra > 0 ? "+\(extra) more" : "" }

    private func laneView(_ lane: Lane, _ board: Board, limit: Int, rowHeight: CGFloat, lines: Int) -> some View {
        let cards = board.cards(in: lane)
        let shown = Array(cards.prefix(limit))
        return VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            HStack(spacing: 4) {
                Circle().fill(lane.color).frame(width: 6, height: 6)
                Text(lane.title).font(.system(size: 9, weight: .bold)).tracking(0.4)
                Text("\(cards.count)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if family == .systemMedium {
                    Text(moreLabel(cards.count - shown.count))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: Metrics.laneHeader)
            ForEach(shown) { card in
                cardLine(card, lines: lines, height: rowHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func cardLine(_ card: Card, lines: Int, height: CGFloat) -> some View {
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
        .frame(height: height)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var diagnostics: some View {
        if entry.debugLogging {
            Text("\(SharedStore.diagnostics) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: Metrics.diagnostics)
        }
    }
}
