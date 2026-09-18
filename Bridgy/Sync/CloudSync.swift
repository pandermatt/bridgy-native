import CloudKit
import Foundation
import Observation
import os

/// Something that changed locally and should go to iCloud.
enum SyncChange: Sendable {
    case agentSaved(UUID), agentDeleted(UUID)
    case experimentSaved(UUID), experimentDeleted(UUID)
    case gameSaved(UUID), gameDeleted(UUID)
}

private let syncLog = Logger(subsystem: "ch.pandermatt.bridgy", category: "CloudSync")

/// Keeps agents, experiments, finished games and the game in progress the
/// same on every device signed in to the same iCloud account.
///
/// Built on `CKSyncEngine` over the private database, in one custom zone.
/// Each store reports its local changes; the engine batches and sends them,
/// and fetched changes are applied through the stores' `applyRemote` paths so
/// they don't echo back. Conflicts go to the last writer: a local change that
/// meets a newer server record is re-sent on top of it.
@MainActor
@Observable
final class CloudSync {

    enum Status: Equatable {
        case off
        case noAccount
        case syncing
        case upToDate(Date)
        case failed(String)

        var text: String {
            switch self {
            case .off: "Off"
            case .noAccount: "Sign in to iCloud in Settings to sync."
            case .syncing: "Syncing…"
            case .upToDate(let date): "Up to date · \(date.formatted(.relative(presentation: .named)))"
            case .failed(let message): message
            }
        }
    }

    static let containerID = "iCloud.ch.pandermatt.bridgy"
    private static let zoneID = CKRecordZone.ID(zoneName: "Bridgy")

    private(set) var status: Status = .off

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var saved = SavedState()
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// Kept between launches: the engine's own state, and the last server
    /// copy of each record so a save carries the right change tag.
    private struct SavedState: Codable {
        var engine: CKSyncEngine.State.Serialization?
        var systemFields: [String: Data] = [:]
        var zoneCreated = false
        var initialUploadDone = false
    }

    private static var stateURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        return base.appendingPathComponent("Bridgy/cloud-state.json")
    }

    /// Only where the app is signed with the iCloud entitlement. Creating a
    /// container without it is a crash, not an error.
    static var isAvailable: Bool {
        #if os(iOS) || os(visionOS)
        // Without the iCloud entitlement CloudKit traps on first use.
        BridgyBuild.hasPaidEntitlements
        #else
        false
        #endif
    }

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Starting and stopping

    func start() {
        guard Self.isAvailable, engine == nil, let model else { return }
        saved = (try? Data(contentsOf: Self.stateURL)).flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) } ?? SavedState()
        let database = CKContainer(identifier: Self.containerID).privateCloudDatabase
        let engine = CKSyncEngine(CKSyncEngine.Configuration(
            database: database, stateSerialization: saved.engine, delegate: self
        ))
        self.engine = engine

        model.agents.onChange = { [weak self] in self?.localChange($0) }
        model.library.onChange = { [weak self] in self?.localChange($0) }
        model.history.onChange = { [weak self] in self?.localChange($0) }
        observer = NotificationCenter.default.addObserver(
            forName: .bridgyCurrentGameSaved, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enqueueSave(Self.currentGameName) }
        }

        if !saved.zoneCreated {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        if !saved.initialUploadDone { uploadEverything() }

        status = .syncing
        Task { await checkAccount() }
    }

    func stop() {
        engine = nil
        model?.agents.onChange = nil
        model?.library.onChange = nil
        model?.history.onChange = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        status = .off
    }

    /// Fetch now, as when the app comes to the front.
    func syncNow() {
        guard let engine else { return }
        status = .syncing
        Task {
            do {
                try await engine.fetchChanges()
                try await engine.sendChanges()
                status = .upToDate(.now)
            } catch {
                status = .failed(Self.describe(error))
            }
        }
    }

    private func checkAccount() async {
        let accountStatus = try? await CKContainer(identifier: Self.containerID).accountStatus()
        if accountStatus != .available {
            status = .noAccount
        } else {
            syncNow()
        }
    }

    // MARK: - Local changes

    private static let currentGameName = "current-game"

    private static func name(_ kind: String, _ id: UUID) -> String { "\(kind)-\(id.uuidString)" }

    private func localChange(_ change: SyncChange) {
        switch change {
        case .agentSaved(let id): enqueueSave(Self.name("agent", id))
        case .agentDeleted(let id): enqueueDelete(Self.name("agent", id))
        case .experimentSaved(let id): enqueueSave(Self.name("experiment", id))
        case .experimentDeleted(let id): enqueueDelete(Self.name("experiment", id))
        case .gameSaved(let id): enqueueSave(Self.name("game", id))
        case .gameDeleted(let id): enqueueDelete(Self.name("game", id))
        }
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: Self.zoneID)
    }

    private func enqueueSave(_ name: String) {
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
    }

    private func enqueueDelete(_ name: String) {
        saved.systemFields[name] = nil
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(name))])
    }

    /// The first time sync is on, everything already here goes up.
    private func uploadEverything() {
        guard let model else { return }
        var names = model.agents.agents.map { Self.name("agent", $0.id) }
        names += model.library.experiments.filter { $0.status != .running }.map { Self.name("experiment", $0.id) }
        names += model.history.games.map { Self.name("game", $0.id) }
        if model.store.data() != nil { names.append(Self.currentGameName) }
        engine?.state.add(pendingRecordZoneChanges: names.map { .saveRecord(recordID($0)) })
        saved.initialUploadDone = true
        persist()
    }

    // MARK: - Records

    /// Builds the record for `name` from what's on disk now, on top of the
    /// last server copy so the change tag is right.
    private func record(named name: String) -> CKRecord? {
        guard let model else { return nil }
        let id = recordID(name)
        let record: CKRecord
        if let fields = saved.systemFields[name],
           let coder = try? NSKeyedUnarchiver(forReadingFrom: fields),
           let base = CKRecord(coder: coder) {
            coder.finishDecoding()
            record = base
        } else {
            record = CKRecord(recordType: Self.type(of: name), recordID: id)
        }

        let encoder = JSONEncoder()
        if name == Self.currentGameName {
            guard let data = model.store.data() else { return nil }
            record["json"] = data as NSData
        } else if let uuid = Self.uuid(in: name) {
            switch Self.type(of: name) {
            case "Agent":
                guard let agent = model.agents.agents.first(where: { $0.id == uuid }),
                      let json = try? encoder.encode(agent) else { return nil }
                record["json"] = json as NSData
                record["weights"] = CKAsset(fileURL: model.agents.weightsURL(for: uuid))
            case "Experiment":
                guard let experiment = model.library.experiment(uuid),
                      let json = try? encoder.encode(experiment) else { return nil }
                record["json"] = json as NSData
                let games = model.library.gamesURL(for: uuid)
                if FileManager.default.fileExists(atPath: games.path) {
                    record["games"] = CKAsset(fileURL: games)
                }
            case "PlayedGame":
                guard let game = model.history.game(uuid), let json = try? encoder.encode(game) else { return nil }
                record["json"] = json as NSData
            default:
                return nil
            }
        }
        return record
    }

    private static func type(of name: String) -> String {
        if name == currentGameName { return "CurrentGame" }
        if name.hasPrefix("agent-") { return "Agent" }
        if name.hasPrefix("experiment-") { return "Experiment" }
        return "PlayedGame"
    }

    private static func uuid(in name: String) -> UUID? {
        guard let dash = name.firstIndex(of: "-") else { return nil }
        return UUID(uuidString: String(name[name.index(after: dash)...]))
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        saved.systemFields[record.recordID.recordName] = coder.encodedData
    }

    /// A record from another device, applied to the matching store.
    private func apply(_ record: CKRecord) {
        guard let model else { return }
        remember(record)
        let name = record.recordID.recordName
        let decoder = JSONDecoder()
        guard let json = record["json"] as? Data else { return }
        switch record.recordType {
        case "Agent":
            guard let agent = try? decoder.decode(SavedAgent.self, from: json),
                  let url = (record["weights"] as? CKAsset)?.fileURL,
                  let weights = try? Data(contentsOf: url) else { return }
            try? model.agents.applyRemote(agent, weights: weights)
        case "Experiment":
            guard let experiment = try? decoder.decode(Experiment.self, from: json) else { return }
            // One running here right now keeps its own games.
            guard !model.runner.isRunning(experiment.id) else { return }
            let games = (record["games"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
            model.library.applyRemote(experiment, games: games)
        case "PlayedGame":
            guard let game = try? decoder.decode(PlayedGame.self, from: json) else { return }
            model.history.merge(game)
        case "CurrentGame":
            // A game being played here wins over one from elsewhere.
            guard model.session == nil, model.tableGame == nil else { return }
            model.store.applyRemote(json)
            model.refreshResumable()
        default:
            syncLog.notice("Ignoring unknown record \(name, privacy: .public)")
        }
    }

    private func applyDeletion(of id: CKRecord.ID) {
        guard let model else { return }
        let name = id.recordName
        saved.systemFields[name] = nil
        guard let uuid = Self.uuid(in: name) else { return }
        switch Self.type(of: name) {
        case "Agent": model.agents.removeRemote(uuid)
        case "Experiment": if !model.runner.isRunning(uuid) { model.library.removeRemote(uuid) }
        case "PlayedGame": model.history.removeRemote(uuid)
        default: break
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in Settings to sync."
        case .networkUnavailable, .networkFailure: return "Offline — will sync when connected."
        case .quotaExceeded: return "iCloud storage is full."
        case .badContainer, .missingEntitlement, .permissionFailure:
            return "iCloud isn't set up for Bridgy yet (container \(containerID))."
        default: return error.localizedDescription
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSync: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saved.engine = update.stateSerialization
            persist()

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                saved.initialUploadDone = false
                uploadEverything()
                status = .syncing
            case .signOut, .switchAccounts:
                // Another person's data must not mix with this one's.
                saved = SavedState()
                persist()
                status = .noAccount
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
                saved.zoneCreated = false
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications { apply(modification.record) }
            for deletion in changes.deletions { applyDeletion(of: deletion.recordID) }
            persist()

        case .sentDatabaseChanges(let sent):
            if sent.savedZones.contains(where: { $0.zoneID == Self.zoneID }) {
                saved.zoneCreated = true
                persist()
            }
            for failure in sent.failedZoneSaves {
                status = .failed(Self.describe(failure.error))
            }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { remember(record) }
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    // Last writer wins: take the server's change tag and send again.
                    if let server = failure.error.serverRecord { remember(server) }
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                case .zoneNotFound:
                    saved.zoneCreated = false
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                case .unknownItem:
                    saved.systemFields[name] = nil
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                default:
                    status = .failed(Self.describe(failure.error))
                }
            }
            persist()

        case .didSendChanges, .didFetchChanges:
            if case .syncing = status { status = .upToDate(.now) }
            if case .upToDate = status { status = .upToDate(.now) }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await MainActor.run { self.record(named: id.recordName) }
        }
    }
}
