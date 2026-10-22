import Foundation

/// Reads the Boards app's `.boards` files: a zip holding `contents.html`, whose
/// `<script id="contents" type="application/json">` carries the board as JSON
/// (`item.lists[].title`, `item.lists[].items[].title`).
enum BoardsImporter {
    struct LegacyList {
        var title: String
        var cards: [String]
    }

    enum ImportError: LocalizedError {
        case unzipFailed(Int32)
        case noContents
        case badJSON

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let code): "unzip exited with \(code)"
            case .noContents: "no contents script in contents.html"
            case .badJSON: "contents.html holds no board"
            }
        }
    }

    static func read(_ file: URL) throws -> [LegacyList] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", file.path, "contents.html"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ImportError.unzipFailed(process.terminationStatus) }
        return try parse(html: String(decoding: data, as: UTF8.self))
    }

    static func parse(html: String) throws -> [LegacyList] {
        guard let idRange = html.range(of: "id=\"contents\""),
              let open = html[idRange.upperBound...].range(of: ">"),
              let close = html[open.upperBound...].range(of: "</script>") else { throw ImportError.noContents }
        let json = Data(html[open.upperBound..<close.lowerBound].utf8)
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let item = root["item"] as? [String: Any],
              let lists = item["lists"] as? [[String: Any]] else { throw ImportError.badJSON }
        return lists.map { list in
            let cards = (list["items"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
            return LegacyList(title: list["title"] as? String ?? "", cards: cards)
        }
    }

    /// Maps the five old lists onto the four lanes. The Spillover cards come back separately: they
    /// are put in todo, marked moved to the next week, and the caller adds them to that week.
    static func board(from lists: [LegacyList], week: WeekID, date: Date) -> (board: Board, spilled: [String]) {
        var board = Board(week: week)
        var spilled: [String] = []
        for (index, list) in lists.enumerated() {
            let lane: Lane?
            switch list.title.lowercased().replacingOccurrences(of: " ", with: "") {
            case "todo": lane = .todo
            case "doing", "inprogress": lane = .prog
            case "blocked": lane = .block
            case "done": lane = .done
            case "spillover": lane = nil
            default: lane = index < 4 ? Lane.allCases[index] : nil
            }
            for title in list.cards where !title.trimmingCharacters(in: .whitespaces).isEmpty {
                if let lane {
                    board.append(Card(title: title, lane: lane, createdAt: date, updatedAt: date))
                } else {
                    board.append(Card(title: title, lane: .todo, createdAt: date, updatedAt: date, movedTo: week.next))
                    spilled.append(title)
                }
            }
        }
        return (board, spilled)
    }
}
