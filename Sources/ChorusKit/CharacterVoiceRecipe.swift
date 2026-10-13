import Foundation

public struct CharacterVoiceRecipe: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var prompt: String
    public var voice: String
    public var seed: UInt64
    public var pitchCents: Double
    public var speed: Double
    public var focusHz: Double
    public var focusGain: Double
    public var grit: Double
    public var kokoroBase: String? = nil
    public var bodyEQ: VoiceTone? = nil
    public var lab: VoiceLabSelection? = nil
    public var robot: Double
    public static let voices = ["alba", "marius", "javert", "jean", "fantine", "cosette", "eponine", "azelma"]
    public func validated() throws -> Self {
        guard version == 1, Self.voices.contains(voice), !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 600,
              pitchCents.isFinite, (-700...700).contains(pitchCents), speed.isFinite, (0.75...1.35).contains(speed),
              focusHz.isFinite, (80...4000).contains(focusHz), focusGain.isFinite, (-6...6).contains(focusGain),
              grit.isFinite, (0...0.2).contains(grit), robot.isFinite, (0...0.5).contains(robot) else {
            throw StudioError.invalidProject("This character voice contains unsupported settings.")
        }
        if let kokoroBase { _ = try KokoroRecipe(voice: kokoroBase).validated() }
        if let bodyEQ { _ = try bodyEQ.validated() }
        if let lab { _ = try lab.validated() }
        return self
    }
    public func preparedText(_ text: String) throws -> String {
        if kokoroBase != nil { return try VoiceSettings().preparedText(text) }
        let normalized = ScriptParser.normalizedExpressions(in: text)
        guard ScriptParser.unsupportedTags(in: text).isEmpty, !ScriptParser.expressions.contains(where: { normalized.contains("[\($0)]") }) else {
            throw StudioError.invalidScript("Remove bracketed expression directions before generating this character voice.")
        }
        return SpeechTextNormalizer.normalize(text)
    }
}

/// Local, bounded description-to-recipe mapping. The recipe is hidden from the UI.
public enum VoicePromptResolver {
    public static func resolve(_ prompt: String, seed: UInt64) throws -> CharacterVoiceRecipe {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 600 else { throw StudioError.invalidProject("Describe your voice in 3–600 characters.") }
        var text = trimmed.lowercased().replacingOccurrences(of: "-", with: " ")
        let aliases = ["spongebob": " male bright high pitched nasal energetic animated cartoon",
                       "walter white": " male low pitched measured firm warm gravelly restrained",
                       "wizard": " male deep warm slow gravelly", "fairy": " female airy high pitched bright",
                       "vampire": " male deep silky measured", "villain": " male deep silky measured"]
        for (name, traits) in aliases where text.contains(name) { text += traits }
        let words = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
        func has(_ options: String...) -> Bool { !words.isDisjoint(with: options) }
        let female = has("female", "woman", "girl", "feminine")
        let bright = has("bright", "energetic", "cartoon", "animated", "cheerful", "playful", "anime")
        let deep = has("deep", "low", "gravelly", "baritone", "bass")
        let voice = female ? (bright ? "eponine" : has("soft", "gentle", "airy") ? "cosette" : "alba") : bright ? "marius" : deep ? "javert" : "jean"
        var pitch: Double = has("high", "higher", "squeaky") ? 450 : deep ? -180 : 0
        var speed: Double = bright || has("fast", "faster") ? 1.12 : has("slow", "slower", "measured", "restrained", "calm") ? 0.90 : 1
        // A retry explores a nearby delivery while retaining requested traits.
        if seed != 42 { pitch += Double(Int(seed % 61) - 30); speed += Double(Int((seed / 61) % 5) - 2) * 0.01 }
        if has("less"), has("nasal") { text = text.replacingOccurrences(of: "nasal", with: "") }
        let nasal = text.contains("nasal")
        let recipe = CharacterVoiceRecipe(prompt: trimmed, voice: voice, seed: seed,
            pitchCents: min(700, max(-700, pitch)), speed: min(1.35, max(0.75, speed)),
            focusHz: nasal ? 1650 : has("warm", "silky", "smooth") ? 180 : 1000,
            focusGain: nasal ? 4.5 : has("warm", "silky", "smooth") ? 2 : 0,
            grit: has("gravelly", "raspy", "rough", "elderly") ? 0.06 : 0,
            robot: has("robot", "robotic", "metallic") ? 0.25 : 0)
        return try recipe.validated()
    }
}
