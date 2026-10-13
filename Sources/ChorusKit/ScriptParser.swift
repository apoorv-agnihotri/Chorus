import Foundation

public enum ScriptParser {
    public static let reactions = ["laugh", "chuckle"]
    public static let vocalReactions = ["laugh", "chuckle", "sigh", "gasp", "cough", "clear throat", "shush", "groan", "sniff"]
    public static let deliveryStyles = ["happy", "angry", "surprised", "whispering", "crying", "sarcastic", "dramatic", "fear", "narration", "advertisement"]
    public static var expressions: [String] { vocalReactions + deliveryStyles }
    public static func parse(_ script: String, title: String = "Imported script",
                             previousSpeakers: [Speaker] = [], localVoices: [LocalVoice] = []) throws -> StudioProject {
        var speakers: [Speaker] = [], blocks: [Dialogue] = []
        var current: Speaker?, lines: [String] = []
        func flush() throws {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            lines.removeAll()
            guard !text.isEmpty else { return }
            guard let current else { throw StudioError.invalidScript("Add a speaker tag such as [rue] before the first line of dialogue.") }
            blocks.append(.init(speakerID: current.id, text: text))
        }
        for (index, raw) in script.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]"), line.filter({ $0 == "[" }).count == 1 {
                let name = String(line.dropFirst().dropLast())
                if canonicalExpression(name) != nil {
                    guard current != nil else { throw StudioError.invalidScript("Reaction at line \(index + 1) needs a speaker first.") }
                    lines.append(line); continue
                }
                guard name.range(of: "^[A-Za-z][A-Za-z0-9 _-]{0,39}$", options: .regularExpression) != nil else {
                    throw StudioError.invalidScript("Invalid speaker tag on line \(index + 1). Use a name such as [rue].")
                }
                if name.contains(" ") {
                    // Space-containing tags are ambiguous stage directions. Keep the importer explicit.
                    throw StudioError.invalidScript("Use a single name or underscores in speaker tags. [\(name)] may be an unsupported direction.")
                }
                try flush()
                if let existing = speakers.first(where: { $0.name.lowercased() == name.lowercased() }) { current = existing }
                else { let speaker = Speaker(name: name); speakers.append(speaker); current = speaker }
            } else { lines.append(raw) }
        }
        try flush()
        guard !blocks.isEmpty else { throw StudioError.invalidScript("The script has no dialogue. Add text beneath a speaker tag.") }
        return StudioProject(title: title, speakers: speakers, dialogue: blocks)
            .assigningVoices(previousSpeakers: previousSpeakers, localVoices: localVoices)
    }
    private static func canonicalExpression(_ tag: String) -> String? {
        let lower = tag.lowercased()
        if lower == "gasps" { return "gasp" }
        return expressions.contains(lower) ? lower : nil
    }
    /// Only known model tokens are accepted; arbitrary stage directions are rejected.
    public static func unsupportedTags(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]")
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap {
            let tag = source.substring(with: $0.range(at: 1))
            return canonicalExpression(tag) != nil ? nil : "[\(tag)]"
        }
    }
    public static func normalizedExpressions(in text: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]")
        let source = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let tag = source.substring(with: match.range(at: 1))
            if let canonical = canonicalExpression(tag), let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: "[\(canonical)]")
            }
        }
        return result
    }
}
