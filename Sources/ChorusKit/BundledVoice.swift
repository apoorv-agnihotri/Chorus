import Foundation

/// The five public bases plus hidden compatibility profiles for saved 0.2 presets.
public struct BundledVoice: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let detail: String
    public let resource: String?
    public let settings: VoiceSettings

    public static let rue = BundledVoice(
        id: UUID(uuidString: "5B55CE28-A76A-4C97-A8DA-CF39B254ADC2")!,
        name: "Rue", detail: "Female · American · actor, expressive & cinematic", resource: "rue-conds",
        settings: delivery(speed: 1, variation: 0.85, sentence: 0.25, clause: 0.10, style: "dramatic"))
    public static let kai = BundledVoice(
        id: UUID(uuidString: "5B55CE28-A76A-4C97-A8DA-CF39B254ADC3")!,
        name: "Kai", detail: "Male · American · actor, grounded & bold", resource: "kai-conds",
        settings: delivery(speed: 1, variation: 0.80, sentence: 0.25, clause: 0.10, style: "dramatic"))
    public static let atlas = BundledVoice(
        id: UUID(uuidString: "5B55CE28-A76A-4C97-A8DA-CF39B254ADC4")!,
        name: "Atlas", detail: "Male · American · narrator, deep & measured", resource: "atlas-conds",
        settings: delivery(speed: 0.90, variation: 0.65, sentence: 0.45, clause: 0.20, style: "narration"))
    public static let zia = BundledVoice(
        id: UUID(uuidString: "5B55CE28-A76A-4C97-A8DA-CF39B254ADC5")!,
        name: "Zia", detail: "Female · American · advertising, bright & enthusiastic", resource: "zia-conds",
        settings: delivery(speed: 1.10, variation: 0.85, sentence: 0.15, clause: 0.05, style: "advertisement"))
    public static let indie = BundledVoice(
        id: UUID(uuidString: "5B55CE28-A76A-4C97-A8DA-CF39B254ADC6")!,
        name: "Indie", detail: "Female · American · chill, soft & laid-back", resource: "indie-conds",
        settings: delivery(speed: 0.95, variation: 0.70, sentence: 0.30, clause: 0.15, style: ""))
    public static let all = [rue, kai, atlas, zia, indie]
    public static var defaultVoice: BundledVoice { rue }

    // Keep these identities and assets resolvable without advertising them as bases.
    public static let legacyModelDefault = BundledVoice(
        id: UUID(uuidString: "5B55CE28-A76A-4C97-A8DA-CF39B254ADC0")!,
        name: "Previous model voice", detail: "Compatibility base for an existing preset", resource: nil, settings: .init())
    public static let legacyPodcast = BundledVoice(
        id: UUID(uuidString: "5B55CE28-A76A-4C97-A8DA-CF39B254ADC1")!,
        name: "Previous podcast voice", detail: "Compatibility base for an existing preset", resource: "female_random_podcast-conds", settings: .init())
    public static func named(_ id: UUID?) -> BundledVoice? {
        (all + [legacyModelDefault, legacyPodcast]).first { $0.id == id }
    }
    public static func isPublicBase(_ id: UUID) -> Bool { all.contains { $0.id == id } }
    private static func delivery(speed: Double, variation: Double, sentence: Double, clause: Double, style: String) -> VoiceSettings {
        var settings = VoiceSettings()
        settings.speed = speed; settings.variation = variation
        settings.sentencePause = sentence; settings.commaPause = clause; settings.expression = style
        return settings
    }
}
