import Foundation

public struct Speaker: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// nil uses the app's default base; recognized names are resolved on import/load.
    public var voiceID: UUID?
    public init(id: UUID = UUID(), name: String, voiceID: UUID? = nil) {
        self.id = id; self.name = name; self.voiceID = voiceID
    }
}

public struct Dialogue: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var speakerID: UUID
    public var text: String
    public init(id: UUID = UUID(), speakerID: UUID, text: String) {
        self.id = id; self.speakerID = speakerID; self.text = text
    }
}

public struct StudioProject: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var title: String
    public var speakers: [Speaker]
    public var dialogue: [Dialogue]
    public var pause: Double
    public init(title: String = "Untitled script", speakers: [Speaker], dialogue: [Dialogue], pause: Double = 0.3) {
        self.title = title; self.speakers = speakers; self.dialogue = dialogue; self.pause = pause
    }
    public static var example: StudioProject {
        let rue = Speaker(name: "Rue", voiceID: BundledVoice.rue.id), kai = Speaker(name: "Kai", voiceID: BundledVoice.kai.id)
        return .init(title: "A little disbelief", speakers: [rue, kai], dialogue: [
            .init(speakerID: rue.id, text: "Did you really just say that?"),
            .init(speakerID: kai.id, text: "[laugh] Yes! And I'd say it again!"),
            .init(speakerID: rue.id, text: "That's unbelievable.")
        ])
    }
    public func validated() throws -> StudioProject {
        guard version == 1 else { throw StudioError.invalidProject("This project uses an unsupported file version.") }
        guard (0...3).contains(pause), pause.isFinite else { throw StudioError.invalidProject("Dialogue pause must be between 0 and 3 seconds.") }
        guard !speakers.isEmpty, Set(speakers.map(\.id)).count == speakers.count,
              Set(dialogue.map(\.id)).count == dialogue.count else {
            throw StudioError.invalidProject("Speaker and dialogue identifiers must be unique.")
        }
        let ids = Set(speakers.map(\.id))
        guard speakers.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              dialogue.allSatisfy({ ids.contains($0.speakerID) }) else {
            throw StudioError.invalidProject("Every dialogue block must have a named speaker.")
        }
        return self
    }
    public var taggedScript: String {
        dialogue.map { block in
            let name = speakers.first(where: { $0.id == block.speakerID })?.name ?? "speaker"
            return "[\(name)]\n\(block.text)"
        }.joined(separator: "\n\n")
    }
}

public enum StudioError: LocalizedError {
    case invalidProject(String), invalidScript(String), invalidAudio(String)
    public var errorDescription: String? {
        switch self { case .invalidProject(let s), .invalidScript(let s), .invalidAudio(let s): return s }
    }
}
