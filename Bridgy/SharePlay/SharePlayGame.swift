import BridgyEngine
import CoreTransferable
import Foundation
import GroupActivities
import Observation

/// A game of Bridgy for everyone on the call.
///
/// Whoever starts it plays Down; the friend who joins plays Across.
struct BridgyActivity: GroupActivity, Transferable {
    static let activityIdentifier = "ch.pandermatt.bridgy.play"

    var size: Int

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Play Bridgy"
        metadata.subtitle = "\(size)×\(size) board"
        metadata.type = .generic
        return metadata
    }

    static var transferRepresentation: some TransferRepresentation {
        GroupActivityTransferRepresentation { (activity: BridgyActivity) in activity }
    }
}

/// What goes over the wire: the game itself, which the engine's ledger keeps
/// in step, and the one thing the ledger doesn't know — what to call you.
private enum SharePlayMessage: Codable {
    case game(SharedGameMessage)
    case hello(name: String)
}

/// Runs a SharePlay game: joins the call's session, sends each move made
/// here, and plays each move made there.
///
/// The rules for staying in step — repeats, gaps, someone joining late, both
/// pressing start at once — live in `SharedGameLedger`, where the tests can
/// reach them. This is only the plumbing between that and the call.
@MainActor
@Observable
final class SharePlayGame {
    private(set) var isActive = false
    private(set) var friendName = "Friend"
    /// A line to show briefly, such as "Anna left the game".
    var notice: String?

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var groupSession: GroupSession<BridgyActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var ledger: SharedGameLedger?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var listening: Task<Void, Never>?
    /// Set on the device that pressed start, which plays Down.
    @ObservationIgnored private var startsWithSize: Int?

    init(model: AppModel) {
        self.model = model
    }

    /// Waits for sessions for the life of the app: one starts here, or a
    /// friend on the call starts one and this device is invited.
    func listen() {
        guard listening == nil else { return }
        listening = Task { [weak self] in
            for await session in BridgyActivity.sessions() {
                self?.join(session)
            }
        }
    }

    /// Offers a game to the call. The system asks whether to start it for
    /// everyone; if so, the session arrives through `listen()`.
    func start(size: Int) async {
        startsWithSize = size
        do {
            _ = try await BridgyActivity(size: size).activate()
        } catch {
            startsWithSize = nil
            notice = "Couldn’t start SharePlay."
        }
    }

    /// Another game, same call. You play Down this time.
    func playAgain() {
        guard let size = ledger?.state?.board.size, var ledger else { return }
        send(.game(ledger.start(size: size)))
        self.ledger = ledger
        begin()
    }

    func leave() {
        groupSession?.leave()
        end(notice: nil)
    }

    // MARK: - Session

    private func join(_ session: GroupSession<BridgyActivity>) {
        end(notice: nil)
        let messenger = GroupSessionMessenger(session: session)
        groupSession = session
        self.messenger = messenger
        ledger = SharedGameLedger(me: session.localParticipant.id)
        isActive = true

        tasks.append(Task { [weak self] in
            for await (message, context) in messenger.messages(of: SharePlayMessage.self) {
                self?.receive(message, from: context.source.id)
            }
        })
        tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated = state {
                    self?.end(notice: "SharePlay ended")
                    return
                }
            }
        })
        tasks.append(Task { [weak self] in
            var seen = 1
            for await participants in session.$activeParticipants.values {
                guard let self else { return }
                if participants.count > seen {
                    // Someone new: tell them who we are and, if there's a
                    // game, where it stands.
                    self.send(.hello(name: self.model.settings.sharePlayName))
                    if let history = self.ledger?.historyMessage() { self.send(.game(history)) }
                } else if participants.count < seen, participants.count <= 1 {
                    self.end(notice: "\(self.friendName) left the game")
                    session.leave()
                    return
                }
                seen = participants.count
            }
        })

        session.join()
        send(.hello(name: model.settings.sharePlayName))
        if let size = startsWithSize, var ledger {
            startsWithSize = nil
            send(.game(ledger.start(size: size)))
            self.ledger = ledger
            begin()
        } else {
            send(.game(.requestHistory))
        }
    }

    private func receive(_ message: SharePlayMessage, from sender: UUID) {
        switch message {
        case .hello(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            friendName = trimmed.isEmpty ? "Friend" : trimmed
            if model.session?.configuration.isShared == true { model.session?.renameFriend(friendName) }
        case .game(let message):
            guard var ledger else { return }
            let reaction = ledger.receive(message, from: sender)
            self.ledger = ledger
            switch reaction {
            case .none: break
            case .began, .replaced: begin()
            case .applied(let move):
                // Someone who wandered off to the Lab gets the game back as it stands.
                if model.session?.configuration.isShared == true { model.session?.playRemote(move) } else { begin() }
            case .reply(let reply): send(.game(reply))
            }
        }
    }

    /// Puts the ledger's game on screen, as a new session or over the
    /// current one when it's the same game caught up.
    private func begin() {
        guard let ledger, let state = ledger.state, let mine = ledger.myColour else { return }
        let friend = Seat.friend(name: friendName)
        let configuration = GameConfiguration(
            size: state.board.size,
            blue: mine == .blue ? .human : friend,
            red: mine == .red ? .human : friend
        )
        if let session = model.session, session.configuration == configuration,
           state.moveCount > 0, session.state.moves == Array(state.moves.prefix(session.state.moveCount)) {
            session.replace(with: state)
            return
        }
        let session = model.startSharedGame(configuration, state: state)
        session.onLocalMove = { [weak self] move in self?.played(move) }
        model.requestedTab = .play
    }

    private func played(_ move: Move) {
        guard var ledger, let message = ledger.play(move) else { return }
        self.ledger = ledger
        send(.game(message))
    }

    private func send(_ message: SharePlayMessage) {
        guard let messenger else { return }
        Task {
            try? await messenger.send(message)
        }
    }

    private func end(notice: String?) {
        tasks.forEach { $0.cancel() }
        tasks = []
        messenger = nil
        groupSession = nil
        ledger = nil
        guard isActive else { return }
        isActive = false
        if let notice { self.notice = notice }
        // The game stays on screen to look at, but can't go on alone.
        if model.session?.configuration.isShared == true, model.session?.state.isOver == false {
            model.session?.finish()
            model.session = nil
        }
    }
}
