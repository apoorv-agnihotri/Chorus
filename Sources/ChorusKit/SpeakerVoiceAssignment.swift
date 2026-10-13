import Foundation

extension StudioProject {
    /// Editing a block must not change other blocks that share an imported speaker.
    public mutating func assignVoice(_ voiceID: UUID?, toDialogue dialogueID: UUID) {
        guard let blockIndex = dialogue.firstIndex(where: { $0.id == dialogueID }),
              let speakerIndex = speakers.firstIndex(where: { $0.id == dialogue[blockIndex].speakerID }),
              speakers[speakerIndex].voiceID != voiceID else { return }
        let original = speakers[speakerIndex]
        if dialogue.contains(where: { $0.id != dialogueID && $0.speakerID == original.id }) {
            let replacement = Speaker(name: original.name, voiceID: voiceID)
            speakers.append(replacement)
            dialogue[blockIndex].speakerID = replacement.id
        } else {
            speakers[speakerIndex].voiceID = voiceID
        }
    }

    /// Resolve unassigned speaker tags without replacing a user's explicit choices.
    /// Names use a lowercase lookup key; the script's display spelling is retained.
    public func assigningVoices(previousSpeakers: [Speaker] = [], localVoices: [LocalVoice] = []) -> StudioProject {
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var resolved = self
        for index in resolved.speakers.indices {
            guard resolved.speakers[index].voiceID == nil else { continue }
            let name = key(resolved.speakers[index].name)
            if let previous = previousSpeakers.first(where: { key($0.name) == name && $0.voiceID != nil }) {
                resolved.speakers[index].voiceID = previous.voiceID
            } else if let local = localVoices.first(where: { key($0.name) == name }) {
                resolved.speakers[index].voiceID = local.id
            } else if let base = BundledVoice.all.first(where: { key($0.name) == name }) {
                resolved.speakers[index].voiceID = base.id
            }
        }
        return resolved
    }
}
