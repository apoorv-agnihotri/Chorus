import Foundation

public enum VoiceLabCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case identity, pitchBody, texture, delivery, characterStyle
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .identity: return "Identity"
        case .pitchBody: return "Pitch & Body"
        case .texture: return "Texture"
        case .delivery: return "Delivery"
        case .characterStyle: return "Character Style"
        }
    }
    public var detail: String {
        switch self {
        case .identity: return "Choose a voice identity."
        case .pitchBody: return "Choose the pitch and fullness of your voice."
        case .texture: return "Choose the texture of your voice."
        case .delivery: return "Choose how your voice delivers the words."
        case .characterStyle: return "Choose a style for your character."
        }
    }
}
public enum VoiceLabSupport: String, Codable, Sendable {
    case supported, experimental, unavailable
    public var label: String {
        switch self {
        case .supported: return "Supported"
        case .experimental: return "Experimental"
        case .unavailable: return "Experimental · unavailable"
        }
    }
}
public struct VoiceTone: Codable, Equatable, Sendable {
    public var frequency: Double
    public var gain: Double
    public init(frequency: Double, gain: Double) { self.frequency = frequency; self.gain = gain }
    public func validated() throws -> Self {
        guard frequency.isFinite, (80...4000).contains(frequency), gain.isFinite, (-6...6).contains(gain) else {
            throw StudioError.invalidProject("Invalid voice tone settings.")
        }
        return self
    }
}
fileprivate struct LabEffect: Sendable {
    var voice: String? = nil
    var kokoroBase: String? = nil
    var pitch: Double? = nil
    var rate: Double? = nil
    var tone: VoiceTone? = nil
    var focus: VoiceTone? = nil
    var grit: Double? = nil
    var robot: Double? = nil
}
public struct VoiceLabTrait: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let support: VoiceLabSupport
    public var isSelectable: Bool { support != .unavailable }
    fileprivate let effect: LabEffect?
}
public enum VoiceLabCatalog {
    private static func trait(_ id: String, _ title: String, _ detail: String, _ effect: LabEffect,
                              _ support: VoiceLabSupport = .supported) -> VoiceLabTrait {
        .init(id: id, title: title, detail: detail, support: support, effect: effect)
    }
    private static func unavailable(_ id: String, _ title: String, _ reason: String = "Needs a validated voice reference; current effects cannot reproduce this reliably.") -> VoiceLabTrait {
        .init(id: id, title: title, detail: reason, support: .unavailable, effect: nil)
    }
    public static func traits(in category: VoiceLabCategory) -> [VoiceLabTrait] {
        func option(_ id: String, _ name: String, _ effect: LabEffect, _ exact: Bool = false) -> VoiceLabTrait {
            trait(id, name, exact ? "Saved processing applied after Chatterbox synthesis." : "Character approximation using a base reference and saved processing; natural acting and speaker age are not guaranteed.", effect, exact ? .supported : .experimental)
        }
        func tone(_ hz: Double, _ gain: Double) -> VoiceTone { .init(frequency: hz, gain: gain) }
        switch category {
        case .identity:
            let names = ["Young", "Mature", "Elderly", "Androgynous", "Masculine", "Feminine", "Childlike", "Robotic", "Creature", "Narrator", "Heroic", "Villainous", "Regal", "Playful", "Mysterious", "Scholarly", "Rugged", "Gentle", "Ethereal", "Alien"]
            let ids = ["young", "mature", "elder", "androgynous", "masculine", "feminine", "child", "robotic", "creature", "narrator", "heroic", "villainous", "regal", "playful", "mysterious", "scholarly", "rugged", "gentle", "ethereal", "alien"]
            let bases = ["af_sky", "am_onyx", "am_santa", "af_alloy", "am_fenrir", "af_heart", "af_kore", "am_echo", "am_adam", "af_bella", "am_michael", "am_onyx", "am_liam", "am_puck", "af_nicole", "am_eric", "am_adam", "af_sarah", "af_aoede", "af_river"]
            return names.indices.map { option(ids[$0], names[$0], .init(voice: "alba", kokoroBase: bases[$0])) }
        case .pitchBody:
            return [option("ultra-deep", "Ultra Deep", .init(pitch: -650)), option("deep", "Deep", .init(pitch: -400), true), option("low", "Low", .init(pitch: -200), true), option("mid-low", "Mid-Low", .init(pitch: -100), true), option("natural", "Natural", .init(), true), option("mid-high", "Mid-High", .init(pitch: 100), true), option("high", "High", .init(pitch: 400), true), option("very-high", "Very High", .init(pitch: 600)), option("resonant", "Resonant", .init(tone: tone(250, 4))), option("chest", "Chest-Heavy", .init(tone: tone(150, 5))), option("thin", "Thin", .init(tone: tone(180, -4)), true), option("full", "Full-Bodied", .init(tone: tone(220, 3))), option("booming", "Booming", .init(pitch: -150, tone: tone(120, 5))), option("light", "Light", .init(tone: tone(250, -2))), option("dark", "Dark", .init(tone: tone(3200, -4)), true), option("bright-body", "Bright", .init(tone: tone(3000, 3)), true), option("hollow", "Hollow", .init(tone: tone(800, -5))), option("rounded", "Rounded", .init(tone: tone(500, 2))), option("sharp", "Sharp", .init(tone: tone(2500, 4))), option("warm", "Warm", .init(tone: tone(180, 3)), true)]
        case .texture:
            return [option("clean", "Clean", .init(focus: tone(1000,0), grit: 0, robot: 0), true), option("breathy", "Breathy", .init(focus: tone(3500, 2))), option("whisper", "Whispery", .init(focus: tone(2500, -2))), option("rasp", "Raspy", .init(grit: 0.08)), option("gravel", "Gravelly", .init(focus: tone(700, 2), grit: 0.12)), option("husky", "Husky", .init(focus: tone(400, 3), grit: 0.04)), option("nasal", "Nasal", .init(focus: tone(1650, 4.5))), option("airy", "Airy", .init(focus: tone(4000, 3))), option("metallic", "Metallic", .init(robot: 0.35), true), option("velvet", "Velvety", .init(focus: tone(2800, -2))), option("smoky", "Smoky", .init(focus: tone(1800, -2), grit: 0.03)), option("crunchy", "Crunchy", .init(grit: 0.18), true), option("smooth", "Smooth", .init(focus: tone(3200, -1), grit: 0)), option("grainy", "Grainy", .init(grit: 0.05)), option("buzz", "Buzzy", .init(robot: 0.15), true), option("dry", "Dry", .init(focus: tone(180, -2))), option("soft", "Soft", .init(focus: tone(2200, -3))), option("harsh", "Harsh", .init(focus: tone(2400, 4), grit: 0.1)), option("silky", "Silky", .init(focus: tone(2800, -1.5))), option("distorted", "Distorted", .init(grit: 0.2), true)]
        case .delivery:
            return [option("slow", "Slow", .init(rate: 0.8), true), option("very-slow", "Very Slow", .init(rate: 0.75), true), option("measured", "Measured", .init(rate: 0.9)), option("natural", "Natural", .init(), true), option("fast", "Fast", .init(rate: 1.2), true), option("rapid", "Rapid", .init(rate: 1.3), true), option("energetic", "Energetic", .init(rate: 1.15)), option("tired", "Exhausted", .init(rate: 0.82)), option("calm", "Calm", .init(rate: 0.92)), option("excited", "Excited", .init(rate: 1.18)), option("angry", "Angry", .init(rate: 1.08)), option("sad", "Sad", .init(rate: 0.85)), option("confident", "Confident", .init(rate: 1.02)), option("timid", "Timid", .init(rate: 0.94)), option("commanding", "Commanding", .init(rate: 0.95)), option("sleepy", "Sleepy", .init(rate: 0.78)), option("dramatic", "Dramatic", .init(rate: 0.88)), option("monotone", "Monotone", .init(rate: 1)), option("whimsical", "Whimsical", .init(rate: 1.1)), option("intense", "Intense", .init(rate: 1.05))]
        case .characterStyle:
            return [option("cartoon", "Cartoon", .init(pitch: 450, rate: 1.12, focus: tone(1650,4.5))), option("anime", "Anime", .init(pitch: 250, rate: 1.1)), option("cinematic", "Cinematic", .init(rate: 0.92, tone: tone(180,2))), option("fantasy", "Fantasy", .init(pitch: -200, rate: 0.9, tone: tone(180,2), grit: 0.06)), option("sci-fi", "Sci-Fi", .init(robot: 0.22)), option("documentary", "Documentary", .init(rate: 0.96)), option("podcast", "Podcast", .init(tone: tone(250,1))), option("storyteller", "Storyteller", .init(rate: 0.93)), option("wizard", "Old Wizard", .init(pitch: -250, rate: 0.82, grit: 0.07)), option("monster", "Monster", .init(pitch: -650, grit: 0.15)), option("detective", "Detective", .init(pitch: -100, rate: 0.97)), option("royalty", "Royalty", .init(rate: 0.91, tone: tone(400,2))), option("radio", "Radio Host", .init(focus: tone(2300,2))), option("npc", "Game NPC", .init(rate: 1.03)), option("hero", "Superhero", .init(pitch: -150, tone: tone(200,3))), option("fairy", "Fairy", .init(pitch: 500, rate: 1.08)), option("robot", "Android", .init(robot: 0.35), true), option("villain", "Villain", .init(pitch: -350, rate: 0.88)), option("comedy", "Comedy", .init(pitch: 150, rate: 1.13)), option("mystical", "Mystical", .init(pitch: 100, rate: 0.86, robot: 0.05))]
        }
    }
    private static func legacyTraits(in category: VoiceLabCategory) -> [VoiceLabTrait] {
        switch category {
        case .identity:
            return CharacterVoiceRecipe.voices.map {
                trait($0, KokoroVoice.name(for: VoiceLabCompiler.kokoroBase(for: $0)), "A Kokoro base reference, cloned into Chatterbox. Saved effects are applied to narration.", .init(voice: $0))
            } + [
                unavailable("child", "Child"), unavailable("teen", "Teenager"),
                unavailable("elder", "Elderly speaker"), unavailable("androgynous", "Androgynous"),
                unavailable("american", "American accent"), unavailable("british", "British accent"),
                unavailable("irish", "Irish accent"), unavailable("scottish", "Scottish accent"),
                unavailable("australian", "Australian accent"), unavailable("indian", "Indian accent"),
                unavailable("japanese", "Japanese accent"), unavailable("custom", "Custom reference")
            ]
        case .pitchBody:
            return [
                trait("natural", "Style default", "Use the original pitch or the selected style's suggestion.", .init()),
                trait("original", "Original pitch", "Keep the reference voice's pitch unchanged.", .init(pitch: 0)),
                trait("low", "Low", "Shift down two semitones; formants are unchanged.", .init(pitch: -200)),
                trait("deep", "Deep", "Shift down four semitones; formants are unchanged.", .init(pitch: -400)),
                trait("very-deep", "Very deep", "Shift down six semitones. Large shifts can sound processed.", .init(pitch: -600), .experimental),
                trait("raised", "Raised", "Shift up two semitones; formants are unchanged.", .init(pitch: 200)),
                trait("high", "High", "Shift up four semitones; formants are unchanged.", .init(pitch: 400)),
                trait("very-high", "Very high", "Shift up six semitones. Large shifts can sound processed.", .init(pitch: 600), .experimental),
                trait("warm", "Warm body", "Add low-frequency warmth with tone EQ.", .init(tone: .init(frequency: 180, gain: 3))),
                trait("lean", "Lean body", "Reduce low-frequency body with tone EQ.", .init(tone: .init(frequency: 180, gain: -3))),
                trait("presence", "Forward presence", "Emphasize upper-mid frequencies with tone EQ.", .init(tone: .init(frequency: 2500, gain: 3))),
                trait("mellow", "Mellow body", "Soften upper-mid frequencies with tone EQ.", .init(tone: .init(frequency: 2500, gain: -3))),
                unavailable("chest", "Chest resonance"), unavailable("head", "Head resonance"),
                unavailable("huge", "Huge anatomy"), unavailable("tiny", "Tiny anatomy"),
                unavailable("formants-low", "Lower formants"), unavailable("formants-high", "Higher formants"),
                unavailable("subharmonic", "Subharmonic bass"), unavailable("falsetto", "True falsetto")
            ]
        case .texture:
            return [
                trait("natural", "Style default", "Use the reference texture or the selected style's treatment.", .init()),
                trait("clean", "Clean", "Remove style saturation, modulation, and texture EQ.", .init(focus: .init(frequency: 1000, gain: 0), grit: 0, robot: 0)),
                trait("nasal", "Nasal focus", "Midrange EQ approximation; does not change nasal physiology.", .init(focus: .init(frequency: 1650, gain: 4.5)), .experimental),
                trait("bright", "Bright", "Emphasize higher frequencies with EQ.", .init(focus: .init(frequency: 3000, gain: 3))),
                trait("muffled", "Muffled", "Reduce higher frequencies with EQ; not a full low-pass filter.", .init(focus: .init(frequency: 3000, gain: -4.5))),
                trait("light-grit", "Light grit", "Gentle saturation adds harmonics; not natural vocal rasp.", .init(grit: 0.06)),
                trait("strong-grit", "Strong grit", "Stronger saturation adds distortion; not natural vocal rasp.", .init(grit: 0.15)),
                trait("metallic", "Metallic effect", "Ring modulation adds an electronic buzz, not a new speaker identity.", .init(robot: 0.35)),
                unavailable("breathy", "Breathy"), unavailable("whisper", "Natural whisper"),
                unavailable("hoarse", "Hoarse"), unavailable("vocal-fry", "Vocal fry"),
                unavailable("creaky", "Creaky"), unavailable("rasp", "Natural rasp"),
                unavailable("growl", "Growling"), unavailable("smoky", "Smoky"),
                unavailable("velvet", "Velvety"), unavailable("hollow", "Hollow resonance"),
                unavailable("double", "Double voice", "Requires additional DSP that has not been implemented or validated."),
                unavailable("airy", "Natural airiness")
            ]
        case .delivery:
            return [
                trait("natural", "Style default", "Use normal pacing or the selected style's suggestion.", .init()),
                trait("slow", "Slow", "Render at 0.80× speed while preserving pitch.", .init(rate: 0.8)),
                trait("relaxed", "Relaxed pace", "Render at 0.90× speed; this does not add calm acting.", .init(rate: 0.9)),
                trait("normal", "Normal pace", "Render at the reference's natural speed.", .init(rate: 1)),
                trait("brisk", "Brisk", "Render at 1.10× speed while preserving pitch.", .init(rate: 1.1)),
                trait("quick", "Quick", "Render at 1.20× speed while preserving pitch.", .init(rate: 1.2)),
                trait("rapid", "Rapid", "Render at 1.30× speed. This does not add excited acting.", .init(rate: 1.3)),
                unavailable("calm", "Calm acting"), unavailable("tired", "Exhausted"),
                unavailable("excited", "Excited acting"), unavailable("sarcastic", "Sarcastic"),
                unavailable("angry", "Angry"), unavailable("sad", "Sad"), unavailable("joyful", "Joyful"),
                unavailable("fearful", "Fearful"), unavailable("crying", "Crying"), unavailable("laughing", "Laughing"),
                unavailable("shouting", "Shouting"), unavailable("whispering", "Whispering"), unavailable("singing", "Singing")
            ]
        case .characterStyle:
            return [
                trait("unstyled", "Unstyled", "Use only your individual trait choices.", .init()),
                trait("robot", "Sci-fi robot effect", "Electronic ring modulation. Specific texture choices can override it.", .init(robot: 0.35)),
                trait("cartoon", "Animated cartoon", "Higher pitch, faster pacing, and nasal EQ. Does not add cartoon acting.", .init(pitch: 450, rate: 1.12, focus: .init(frequency: 1650, gain: 4.5)), .experimental),
                trait("narrator", "Warm narrator", "Warm EQ and slower pacing. Does not add narration performance.", .init(rate: 0.9, tone: .init(frequency: 180, gain: 2)), .experimental),
                trait("fantasy", "Fantasy narrator", "Lower pitch, warm EQ, slower pacing, and light saturation. Acting remains approximate.", .init(pitch: -200, rate: 0.9, tone: .init(frequency: 180, gain: 2), grit: 0.06), .experimental),
                unavailable("dragon", "Ancient dragon"), unavailable("wizard", "Wizard"),
                unavailable("vampire", "Vampire"), unavailable("villain", "Supervillain"),
                unavailable("hero", "Hero"), unavailable("anime", "Anime actor"), unavailable("child", "Child character"),
                unavailable("monster", "Monster"), unavailable("ghost", "Ghost"), unavailable("alien", "Alien"),
                unavailable("cinematic", "Cinematic actor"), unavailable("documentary", "Documentary acting"),
                unavailable("npc", "Game NPC"), unavailable("storybook", "Storybook acting"), unavailable("comedy", "Comedy acting")
            ]
        }
    }
    public static func trait(_ id: String, in category: VoiceLabCategory) -> VoiceLabTrait? {
        traits(in: category).first { $0.id == id } ?? legacyTraits(in: category).first { $0.id == id }
    }
}
public struct VoiceLabSelection: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var identity: String
    public var pitchBody: String
    public var texture: String
    public var delivery: String
    public var characterStyle: String
    public var seed: UInt64
    public init(identity: String = "mature", pitchBody: String = "natural", texture: String = "clean",
                delivery: String = "natural", characterStyle: String = "storyteller", seed: UInt64 = 42) {
        self.identity = identity; self.pitchBody = pitchBody; self.texture = texture
        self.delivery = delivery; self.characterStyle = characterStyle; self.seed = seed
    }
    public func id(in category: VoiceLabCategory) -> String {
        switch category {
        case .identity: return identity
        case .pitchBody: return pitchBody
        case .texture: return texture
        case .delivery: return delivery
        case .characterStyle: return characterStyle
        }
    }
    public mutating func select(_ id: String, in category: VoiceLabCategory) {
        switch category {
        case .identity: identity = id
        case .pitchBody: pitchBody = id
        case .texture: texture = id
        case .delivery: delivery = id
        case .characterStyle: characterStyle = id
        }
    }
    public func validated() throws -> Self {
        guard version == 1 else { throw StudioError.invalidProject("Unsupported Voice Lab version.") }
        for category in VoiceLabCategory.allCases {
            guard let trait = VoiceLabCatalog.trait(id(in: category), in: category), trait.isSelectable else {
                throw StudioError.invalidProject("This Voice Lab trait is unavailable: \(category.title).")
            }
        }
        return self
    }
    public var summary: String {
        VoiceLabCategory.allCases.compactMap { VoiceLabCatalog.trait(id(in: $0), in: $0)?.title }.joined(separator: " · ")
    }
    public static func randomized(seed: UInt64, includeExperimental: Bool = false) -> Self {
        var rng = LabRandom(state: seed), result = Self(seed: seed)
        for category in VoiceLabCategory.allCases {
            let options = VoiceLabCatalog.traits(in: category).filter { $0.isSelectable && (category == .identity || includeExperimental || $0.support == .supported) }
            result.select(options[Int(rng.next() % UInt64(options.count))].id, in: category)
        }
        return result
    }
}
private struct LabRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}
public enum VoiceLabCompiler {
    public static func kokoroBase(for identity: String) -> String {
        let bases = ["af_heart", "am_fenrir", "am_onyx", "am_adam", "af_bella", "af_nicole", "af_sarah", "af_sky"]
        return bases[CharacterVoiceRecipe.voices.firstIndex(of: identity) ?? 0]
    }
    public static func compile(_ selection: VoiceLabSelection) throws -> CharacterVoiceRecipe {
        let selection = try selection.validated()
        let identity = VoiceLabCatalog.trait(selection.identity, in: .identity)!
        var recipe = CharacterVoiceRecipe(prompt: selection.summary, voice: identity.effect!.voice!, seed: selection.seed,
            pitchCents: 0, speed: 1, focusHz: 1000, focusGain: 0, grit: 0, robot: 0)
        // Style provides suggestions. Explicit category choices override the same controls.
        for category in [VoiceLabCategory.characterStyle, .pitchBody, .texture, .delivery] {
            let effect = VoiceLabCatalog.trait(selection.id(in: category), in: category)!.effect!
            if let pitch = effect.pitch { recipe.pitchCents = pitch }
            if let rate = effect.rate { recipe.speed = rate }
            if let tone = effect.tone { recipe.bodyEQ = tone }
            if let focus = effect.focus { recipe.focusHz = focus.frequency; recipe.focusGain = focus.gain }
            if let grit = effect.grit { recipe.grit = grit }
            if let robot = effect.robot { recipe.robot = robot }
        }
        recipe.lab = selection
        recipe.kokoroBase = identity.effect?.kokoroBase ?? kokoroBase(for: selection.identity)
        return try recipe.validated()
    }
}
