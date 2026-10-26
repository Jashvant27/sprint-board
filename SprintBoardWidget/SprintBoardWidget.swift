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

    /// Fixed heights, so what fits is computed exactly: the week header, a lane's header, a card
    /// row with one line of title or two, the spacing between rows, and the footer with "+n more"
    /// under each lane that overflows, drawn only when one does (its height leaves the row budget
    /// only then, so no card slot goes to it otherwise). Medium lays the lanes out two by two,
    /// where a footer line cannot align with both rows, so there the "+n more" sits at the right
    /// end of the lane's own header instead, and every row is one line.
    private enum Metrics {
        static let weekHeader: CGFloat = 16
        static let laneHeader: CGFloat = 12
        static let singleRow: CGFloat = 19
        static let doubleRow: CGFloat = 32
        static let rowSpacing: CGFloat = 3
        static let laneSpacing: CGFloat = 8
        static let footer: CGFloat = 12
        static let diagnostics: CGFloat = 12
    }

    /// A row: the card and the lines its title gets (one when it fits the column, else two).
    private struct Row: Identifiable {
        let card: Card
        let lines: Int
        var id: UUID { card.id }
        var height: CGFloat { lines == 1 ? Metrics.singleRow : Metrics.doubleRow }
    }

    private struct LanePlan {
        var rows: [Row] = []
        var extra = 0
    }

    private var maxLines: Int { family == .systemMedium ? 1 : 2 }

    /// Whether a title fits one line of the column: a text measure is not available in a widget,
    /// so this estimates from the character count with a generous width per character; a title
    /// that still wraps is cut with an ellipsis by the row's line limit rather than breaking the
    /// layout.
    private func lines(for card: Card, columnWidth: CGFloat) -> Int {
        guard maxLines > 1 else { return 1 }
        let keyWidth = card.jiraKey.map { CGFloat($0.count) * 5.6 + 4 } ?? 0
        let titleWidth = max(20, columnWidth - 10 - keyWidth)
        return CGFloat(card.title.count) * 6.2 <= titleWidth ? 1 : 2
    }

    /// Packs a lane's cards from the top until the next row would not fit.
    private func plan(_ cards: [Card], laneHeight: CGFloat, columnWidth: CGFloat) -> LanePlan {
        var plan = LanePlan()
        var used = Metrics.laneHeader
        for card in cards {
            let row = Row(card: card, lines: lines(for: card, columnWidth: columnWidth))
            if used + Metrics.rowSpacing + row.height > laneHeight { break }
            used += Metrics.rowSpacing + row.height
            plan.rows.append(row)
        }
        plan.extra = cards.count - plan.rows.count
        return plan
    }

    private func plans(_ board: Board, available: CGFloat, columnWidth: CGFloat) -> [Lane: LanePlan] {
        let laneHeight = family == .systemMedium ? (available - 6) / 2 : available
        return Dictionary(uniqueKeysWithValues: Lane.allCases.map {
            ($0, plan(board.cards(in: $0), laneHeight: laneHeight, columnWidth: columnWidth))
        })
    }

    private func content(_ board: Board) -> some View {
        GeometryReader { geo in
            let columns: CGFloat = family == .systemMedium ? 2 : 4
            let columnWidth = (geo.size.width - Metrics.laneSpacing * (columns - 1)) / columns
            let base = geo.size.height - Metrics.weekHeader - 6 - (entry.debugLogging ? Metrics.diagnostics + 6 : 0)
            // The footer is needed when a lane overflows even with the footer's space given to
            // rows; taking it away then can only make the overflow larger, never make it vanish.
            let footerNeeded = family != .systemMedium
                && plans(board, available: base, columnWidth: columnWidth).values.contains { $0.extra > 0 }
            let available = base - (footerNeeded ? Metrics.footer + 6 : 0)
            let plans = plans(board, available: available, columnWidth: columnWidth)
            VStack(alignment: .leading, spacing: 6) {
                header(board).frame(height: Metrics.weekHeader)
                if family == .systemMedium {
                    // Two rows of two lanes.
                    let laneHeight = (available - 6) / 2
                    VStack(spacing: 6) {
                        HStack(alignment: .top, spacing: Metrics.laneSpacing) {
                            laneView(.todo, plans[.todo] ?? LanePlan())
                            laneView(.prog, plans[.prog] ?? LanePlan())
                        }
                        .frame(height: laneHeight)
                        HStack(alignment: .top, spacing: Metrics.laneSpacing) {
                            laneView(.block, plans[.block] ?? LanePlan())
                            laneView(.done, plans[.done] ?? LanePlan())
                        }
                        .frame(height: laneHeight)
                    }
                } else {
                    HStack(alignment: .top, spacing: Metrics.laneSpacing) {
                        ForEach(Lane.allCases) { lane in
                            laneView(lane, plans[lane] ?? LanePlan())
                        }
                    }
                    .frame(height: available)
                }
                if footerNeeded {
                    // One column per lane, aligned with the lanes above.
                    HStack(alignment: .top, spacing: Metrics.laneSpacing) {
                        ForEach(Lane.allCases) { lane in
                            Text(moreLabel(plans[lane]?.extra ?? 0))
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

    private func moreLabel(_ extra: Int) -> String { extra > 0 ? "+\(extra) more" : "" }

    private func laneView(_ lane: Lane, _ plan: LanePlan) -> some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            HStack(spacing: 4) {
                Circle().fill(lane.color).frame(width: 6, height: 6)
                Text(lane.title).font(.system(size: 9, weight: .bold)).tracking(0.4)
                Text("\(plan.rows.count + plan.extra)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if family == .systemMedium {
                    Text(moreLabel(plan.extra))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: Metrics.laneHeader)
            ForEach(plan.rows) { row in
                cardLine(row)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func cardLine(_ row: Row) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if let key = row.card.jiraKey {
                Text(key)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text(row.card.title)
                .font(.system(size: 10.5))
                .strikethrough(row.card.isSpilled)
                .foregroundStyle(row.card.isSpilled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(row.lines)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: row.height)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
