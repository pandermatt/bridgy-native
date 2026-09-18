import Foundation
import Testing
@testable import BridgyEngine

/// Two ledgers wired together in memory, with a network that can repeat,
/// drop or hold back messages.
private struct Wire {
    var a: SharedGameLedger
    var b: SharedGameLedger
    var toA: [SharedGameMessage] = []
    var toB: [SharedGameMessage] = []

    init() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        a = SharedGameLedger(me: first)
        b = SharedGameLedger(me: second)
    }

    /// Delivers everything queued, including replies, until quiet.
    mutating func settle() {
        while !toA.isEmpty || !toB.isEmpty {
            for message in toA { if case .reply(let r) = a.receive(message, from: b.me) { toB.append(r) } }
            toA = []
            for message in toB { if case .reply(let r) = b.receive(message, from: a.me) { toA.append(r) } }
            toB = []
        }
    }
}

private func randomLegal(_ ledger: SharedGameLedger, _ rng: inout SeededRandomNumberGenerator) -> Move? {
    ledger.state?.legalMoves.randomElement(using: &rng)
}

@Suite("Shared game")
struct SharedGameTests {

    @Test("The starter plays Down and both sides agree move for move")
    func agree() {
        var wire = Wire()
        wire.toB.append(wire.a.start(size: 5))
        wire.settle()
        #expect(wire.a.myColour == .blue)
        #expect(wire.b.myColour == .red)
        var rng = SeededRandomNumberGenerator(seed: 1)
        while let state = wire.a.state, !state.isOver {
            if wire.a.isMyTurn, let move = randomLegal(wire.a, &rng), let m = wire.a.play(move) { wire.toB.append(m) }
            else if wire.b.isMyTurn, let move = randomLegal(wire.b, &rng), let m = wire.b.play(move) { wire.toA.append(m) }
            wire.settle()
            #expect(wire.a.state == wire.b.state)
        }
        #expect(wire.a.state?.winner != nil)
    }

    @Test("A repeated message changes nothing")
    func duplicates() {
        var wire = Wire()
        wire.toB.append(wire.a.start(size: 4))
        wire.settle()
        let message = wire.a.play(Move(kind: .v, row: 0, col: 0))!
        wire.toB += [message, message, message]
        wire.settle()
        #expect(wire.b.state?.moveCount == 1)
        #expect(wire.a.state == wire.b.state)
    }

    @Test("A move that skips ahead is noticed and mended from the history")
    func gap() {
        var wire = Wire()
        wire.toB.append(wire.a.start(size: 4))
        wire.settle()
        _ = wire.a.play(Move(kind: .v, row: 0, col: 0))     // lost on the way
        let reaction = wire.b.receive(.move(index: 1, cell: 5), from: wire.a.me)
        #expect(reaction == .reply(.requestHistory))
        wire.toA.append(.requestHistory)
        wire.settle()
        #expect(wire.b.state == wire.a.state)
        #expect(wire.b.isMyTurn)
    }

    @Test("Someone joining late gets the whole game")
    func lateJoin() {
        var wire = Wire()
        _ = wire.a.start(size: 5)                          // b wasn't there
        _ = wire.a.play(Move(kind: .v, row: 2, col: 2))
        wire.toA.append(.requestHistory)
        wire.settle()
        #expect(wire.b.state == wire.a.state)
        #expect(wire.b.myColour == .red)
    }

    @Test("Two people starting at once settle on the same Down")
    func race() {
        var wire = Wire()
        let fromA = wire.a.start(size: 5)
        let fromB = wire.b.start(size: 5)
        wire.toB.append(fromA)
        wire.toA.append(fromB)
        wire.settle()
        #expect(wire.a.down == wire.b.down)
        #expect(wire.a.myColour != wire.b.myColour)
    }

    @Test("A move out of turn is refused")
    func outOfTurn() {
        var wire = Wire()
        wire.toB.append(wire.a.start(size: 4))
        wire.settle()
        #expect(wire.b.play(Move(kind: .v, row: 0, col: 0)) == nil)
    }
}
