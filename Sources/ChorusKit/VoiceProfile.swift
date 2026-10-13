import Foundation

public struct VoiceSettings: Codable, Equatable, Sendable {
    public var speed: Double = 1
    public var variation: Double = 0.8
    public var sentencePause: Double = 0
    public var commaPause: Double = 0
    public var expression: String = ""
    public init() {}
    public func validated() throws -> VoiceSettings {
        guard speed.isFinite, (0.75...1.35).contains(speed),
              variation.isFinite, (0.5...1.1).contains(variation),
              sentencePause.isFinite, (0...1.5).contains(sentencePause),
              commaPause.isFinite, (0...0.6).contains(commaPause),
              expression.isEmpty || ScriptParser.deliveryStyles.contains(expression) else {
            throw StudioError.invalidProject("This voice preset contains unsupported delivery settings.")
        }
        return self
    }
    public func preparedText(_ text: String) -> String {
        let normalized = SpeechTextNormalizer.normalize(ScriptParser.normalizedExpressions(in: text))
        // A script's explicit delivery direction takes precedence over the base preset.
        let hasDelivery = ScriptParser.deliveryStyles.contains { normalized.contains("[\($0)]") }
        return (expression.isEmpty || hasDelivery ? "" : "[\(expression)] ") + normalized
    }
}

public struct LocalVoice: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case cloned, preset, kokoro, character }
    public var id: UUID
    public var name: String
    public var filename: String?
    public var kind: Kind
    public var baseVoiceID: UUID?
    public var settings: VoiceSettings
    public var kokoro: KokoroRecipe?
    public var character: CharacterVoiceRecipe?
    public init(id: UUID = UUID(), name: String, filename: String? = nil, kind: Kind = .cloned,
                baseVoiceID: UUID? = nil, settings: VoiceSettings = .init(), kokoro: KokoroRecipe? = nil, character: CharacterVoiceRecipe? = nil) {
        self.id = id; self.name = name; self.filename = filename; self.kind = kind
        self.baseVoiceID = baseVoiceID; self.settings = settings; self.kokoro = kokoro; self.character = character
    }
    private enum CodingKeys: String, CodingKey { case id, name, filename, kind, baseVoiceID, settings, kokoro, character }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        filename = try values.decodeIfPresent(String.self, forKey: .filename)
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .cloned
        baseVoiceID = try values.decodeIfPresent(UUID.self, forKey: .baseVoiceID)
        settings = try values.decodeIfPresent(VoiceSettings.self, forKey: .settings) ?? .init()
        kokoro = try values.decodeIfPresent(KokoroRecipe.self, forKey: .kokoro)
        character = try values.decodeIfPresent(CharacterVoiceRecipe.self, forKey: .character)
        _ = try settings.validated()
        if kind == .character {
            guard let character else { throw StudioError.invalidProject("Missing character voice recipe.") }
            _ = try character.validated()
        }
        if kind == .kokoro {
            guard let kokoro else { throw StudioError.invalidProject("Missing Kokoro voice recipe.") }
            _ = try kokoro.validated()
            try kokoro.validate(settings: settings)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              kind != .cloned || (filename != nil && filename == URL(fileURLWithPath: filename!).lastPathComponent) else {
            throw StudioError.invalidProject("Invalid saved voice profile.")
        }
    }
}
