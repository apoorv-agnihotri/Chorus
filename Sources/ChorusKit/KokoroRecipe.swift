import Foundation

/// A reproducible Kokoro preset; no model or audio is stored in the workspace.
public struct KokoroRecipe: Codable, Equatable, Sendable {
    public var voice: String
    public init(voice: String = "af_heart") { self.voice = voice }
    public func validated() throws -> Self {
        guard KokoroVoice.all.contains(where: { $0.id == voice }) else {
            throw StudioError.invalidProject("Choose an available Kokoro voice.")
        }
        return self
    }
    public func validate(settings: VoiceSettings) throws {
        _ = try settings.validated()
        guard settings.expression.isEmpty, settings.sentencePause == 0, settings.commaPause == 0 else {
            throw StudioError.invalidProject("Kokoro uses natural punctuation for pauses and does not support Chatterbox expression settings.")
        }
    }
    public func preparedText(_ text: String) throws -> String {
        let normalized = ScriptParser.normalizedExpressions(in: text)
        let tags = ScriptParser.vocalReactions + ScriptParser.deliveryStyles
        guard !tags.contains(where: { normalized.contains("[\($0)]") }), ScriptParser.unsupportedTags(in: text).isEmpty else {
            throw StudioError.invalidScript("Kokoro does not render expression tags. Remove the bracketed directions or choose a Chatterbox voice.")
        }
        return SpeechTextNormalizer.normalize(text)
    }
    /// Bound each inference allocation and let cancellation run between chunks.
    public static func chunks(_ text: String, limit: Int = 350) -> [String] {
        let limit = max(1, limit)
        var result: [String] = [], current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if current.count + word.count + 1 > limit, !current.isEmpty {
                result.append(current); current = ""
            }
            // Unusually long unbroken text must not bypass the allocation bound.
            var remainder = String(word)
            while remainder.count > limit {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(remainder.prefix(limit))); remainder = String(remainder.dropFirst(limit))
            }
            if !current.isEmpty { current += " " }
            current += remainder
            if current.last.map({ ".!?".contains($0) }) == true {
                result.append(current); current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

public struct KokoroVoice: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// American English presets match the runtime's English phonemizer.
    public static let all: [Self] = [
        .init(id: "af_heart", name: "Heart"), .init(id: "af_bella", name: "Bella"),
        .init(id: "af_nicole", name: "Nicole"), .init(id: "af_sarah", name: "Sarah"),
        .init(id: "af_sky", name: "Sky"), .init(id: "af_alloy", name: "Alloy"),
        .init(id: "af_aoede", name: "Aoede"), .init(id: "af_jessica", name: "Jessica"),
        .init(id: "af_kore", name: "Kore"), .init(id: "af_nova", name: "Nova"),
        .init(id: "af_river", name: "River"), .init(id: "am_adam", name: "Adam"),
        .init(id: "am_echo", name: "Echo"), .init(id: "am_eric", name: "Eric"),
        .init(id: "am_fenrir", name: "Fenrir"), .init(id: "am_liam", name: "Liam"),
        .init(id: "am_michael", name: "Michael"), .init(id: "am_onyx", name: "Onyx"),
        .init(id: "am_puck", name: "Puck"), .init(id: "am_santa", name: "Santa")
    ]
    public static func name(for id: String) -> String { all.first { $0.id == id }?.name ?? id }
}
