import BridgyEngine
import Foundation

/// Your record, worked out from the games you've finished in Play.
///
/// Only games with exactly one person in them count: a game between two
/// computers says nothing about you, and one between two people at the same
/// screen has no single "you".
struct PlayerStats {
    struct Line: Identifiable {
        var id: String { opponent }
        let opponent: String
        let symbol: String
        let overall: Record
        let asDown: Record
        let asAcross: Record
    }

    struct SizePoint: Identifiable {
        var id: Int { size }
        let size: Int
        let record: Record
    }

    let games: [PlayedGame]
    let overall: Record
    let asDown: Record
    let asAcross: Record
    let opponents: [Line]
    let bySize: [SizePoint]
    /// Fewest moves in a game you won.
    let fastestWin: PlayedGame?
    /// The largest board you've won on.
    let biggestWin: PlayedGame?
    /// When you first beat each built-in level, strongest first.
    let firstWins: [(level: Difficulty, date: Date)]

    init(history: [PlayedGame]) {
        let mine = history.filter { $0.configuration.soloHumanPlayer != nil }
        games = mine
        func won(_ game: PlayedGame) -> Bool { game.configuration.soloHumanPlayer == game.record.winner }
        func record(_ subset: [PlayedGame]) -> Record {
            Record(wins: subset.filter(won).count, games: subset.count)
        }
        overall = record(mine)
        asDown = record(mine.filter { $0.configuration.soloHumanPlayer == .blue })
        asAcross = record(mine.filter { $0.configuration.soloHumanPlayer == .red })

        var byOpponent: [String: [PlayedGame]] = [:]
        var symbols: [String: String] = [:]
        for game in mine {
            guard let me = game.configuration.soloHumanPlayer else { continue }
            let seat = game.configuration.seat(for: me.opponent)
            byOpponent[seat.displayName, default: []].append(game)
            symbols[seat.displayName] = seat.symbolName
        }
        // Built-in levels in ladder order, then agents by name.
        let ladder = Difficulty.allCases.map(\.displayName)
        opponents = byOpponent.keys.sorted { a, b in
            switch (ladder.firstIndex(of: a), ladder.firstIndex(of: b)) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a < b
            }
        }
        .map { name in
            let games = byOpponent[name] ?? []
            return Line(
                opponent: name, symbol: symbols[name] ?? "cpu",
                overall: record(games),
                asDown: record(games.filter { $0.configuration.soloHumanPlayer == .blue }),
                asAcross: record(games.filter { $0.configuration.soloHumanPlayer == .red })
            )
        }

        bySize = Dictionary(grouping: mine, by: \.record.size).keys.sorted().map { size in
            SizePoint(size: size, record: record(mine.filter { $0.record.size == size }))
        }

        let wins = mine.filter(won)
        fastestWin = wins.min { ($0.record.length, $0.date) < ($1.record.length, $1.date) }
        biggestWin = wins.max { ($0.record.size, $1.date) < ($1.record.size, $0.date) }

        var first: [Difficulty: Date] = [:]
        for game in wins {
            guard let me = game.configuration.soloHumanPlayer,
                  let level = game.configuration.seat(for: me.opponent).difficulty else { continue }
            first[level] = min(first[level] ?? game.date, game.date)
        }
        firstWins = Difficulty.allCases.reversed().compactMap { level in first[level].map { (level, $0) } }
    }
}
