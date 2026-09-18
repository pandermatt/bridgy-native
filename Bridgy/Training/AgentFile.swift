import BridgyEngine
import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A trained agent in one file: its description and its network.
    static let bridgyAgent = UTType(exportedAs: "ch.pandermatt.bridgy.agent", conformingTo: .data)
}

/// The shareable form of an agent: JSON holding the description and the
/// weights, so one file carries everything needed to play it anywhere.
struct AgentFile: Codable, Sendable {
    static let currentFormat = 1

    var format = AgentFile.currentFormat
    var agent: SavedAgent
    var weights: Data

    init(agent: SavedAgent, weights: NetworkWeights) {
        self.agent = agent
        self.weights = weights.data()
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> AgentFile {
        let file = try JSONDecoder().decode(AgentFile.self, from: data)
        guard file.format <= currentFormat else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "This agent was saved by a newer version of Bridgy."
            ])
        }
        // Checks the weights match the architecture before anything is saved.
        _ = try NetworkWeights(architecture: file.agent.parameters.architecture, data: file.weights)
        return file
    }

    var filename: String {
        agent.name.replacingOccurrences(of: "/", with: "-") + ".bridgyagent"
    }
}

/// An agent file for the share sheet, built when it is shared.
struct SharedAgent: Transferable {
    let file: AgentFile

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .bridgyAgent) { shared in
            let url = URL.temporaryDirectory.appendingPathComponent(shared.file.filename)
            try shared.file.encoded().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// An agent file for the save panel.
struct AgentDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.bridgyAgent]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
